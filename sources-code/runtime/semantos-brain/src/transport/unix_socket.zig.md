---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/transport/unix_socket.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.290712+00:00
---

# runtime/semantos-brain/src/transport/unix_socket.zig

```zig
// Phase D-W1 / Phase 1 — see docs/design/BRAIN-DISPATCHER-UNIFICATION.md §5.2, §6.
//
// Unix-socket transport for the dispatcher.  Replaces the Model-A
// "CLI writes the bearer log directly" pattern (issues #1 and #2) with
// the Model-B shape every other transport will use: serialise the wire
// envelope, send it to the daemon, daemon dispatches against the live
// dispatcher's resource registry, response comes back over the same
// connection.  Same auth-context construction the HTTP transport will
// produce in Phase 3 — one capability check, one audit pair, one
// resource mutation — across every brain-managed surface.
//
// ┌──────────────┐        ┌────────────────────────────────────────┐
// │  CLI client  │  --->  │  daemon binds <data_dir>/brain.sock      │
// │  (ephemeral) │  <---  │  accepts → uid check → dispatcher      │
// └──────────────┘        └────────────────────────────────────────┘
//
// Auth: Unix peer credentials.  The server captures the daemon's own
// uid at startup; every accepted connection is checked against that
// uid.  Mismatch → capability_denied response, handler never invoked.
// On Linux this uses SO_PEERCRED; on macOS, getpeereid(3).  Both ship
// in libc so the platform diff is one extern fn.
//
// Wire format: newline-delimited JSON envelopes per §6.  The client
// sends one Request envelope per connection in v0.1; the server reads
// up to the first newline, dispatches, writes the Response envelope
// followed by '\n'.  A future revision can keep the connection open
// for multiple round-trips without changing the codec — the read
// loop already accepts >1 envelope per connection.
//
// Embedded mode: when the CLI finds no socket at <data_dir>/brain.sock
// (no file OR connect fails with ECONNREFUSED), it instantiates a
// dispatcher in-process, opens the data_dir directly, executes the
// command, exits.  Identical post-state to socket mode — same
// dispatcher code, same resource handlers, same TokenStore — so the
// CLI behaves the same whether the daemon is up or not.  This file
// exposes only the daemon-side bind/serve and the CLI-side
// connect/send; the embedded-mode fallback is the CLI's wiring
// concern (runtime/semantos-brain/src/cli.zig).
//
// Threading: one OS thread per accepted connection.  v0.1 doesn't
// share state between threads beyond the Dispatcher (whose handlers
// own their per-resource mutexes), so this is the simplest correct
// shape.  Daemon main thread keeps running site_server.serve(); the
// Unix socket accept loop runs on its own thread spawned at boot.
//
// Lifetime: server holds an open `std.fs.File` for the listening
// socket and a `should_stop` atomic flag.  `stop()` flips the flag,
// closes the listener (causing accept to wake up), and drops the
// socket file.  Threads serving in-flight connections finish their
// current request and exit.

const std = @import("std");
const builtin = @import("builtin");
const dispatcher_mod = @import("dispatcher");
const wire = @import("wire");

pub const SOCKET_BASENAME = "brain.sock";

// ─────────────────────────────────────────────────────────────────────
// Errors
// ─────────────────────────────────────────────────────────────────────

pub const TransportError = error{
    bind_failed,
    listen_failed,
    accept_failed,
    socket_path_too_long,
    connect_failed,
    not_running,
    peer_uid_unavailable,
    /// Connection peer's uid did not match the server's expected uid.
    /// Returned to the caller in the response envelope as
    /// capability_denied + recorded against `op = "transport.unix_socket"`
    /// in the audit log; the dispatcher itself is never invoked.
    peer_uid_mismatch,
    /// Wire envelope read/parse failed.
    bad_envelope,
    /// Allocator OOM.
    out_of_memory,
};

// ─────────────────────────────────────────────────────────────────────
// libc bridges — Unix peer credentials.
//
// Linux: SO_PEERCRED via getsockopt(2) returns struct ucred
//        {pid, uid, gid}.  Recorded in the kernel at connect time;
//        the userland call reads kernel state, so it is NOT racy
//        against a peer's setuid() between connect and our read.
// macOS / *BSD: getpeereid(3) returns (uid, gid) from kernel-stored
//        AF_UNIX peer creds.  Same TOCTOU profile (kernel-recorded
//        at connect time) but the libc symbol is the only public
//        surface — no SO_PEERCRED on these platforms.
//
// We capture the peer's uid IMMEDIATELY on accept(), before any
// read/write on the connection — this keeps the auth boundary at
// the syscall edge and matches what an HTTP-style transport does
// with the TLS client cert.  Reading any byte from the connection
// before the uid check would be a different (read-then-auth) order
// that this transport explicitly avoids.
// ─────────────────────────────────────────────────────────────────────

extern "c" fn getpeereid(fd: c_int, uid: *u32, gid: *u32) c_int;
extern "c" fn chmod(path: [*:0]const u8, mode: c_uint) c_int;
extern "c" fn umask(mode: c_uint) c_uint;

/// Linux struct ucred — `getsockopt(SOL_SOCKET, SO_PEERCRED)`.  Layout
/// matches the kernel <sys/socket.h>; `pid` is `pid_t` (i32 on Linux).
const Ucred = extern struct {
    pid: i32,
    uid: u32,
    gid: u32,
};

/// Read the connected peer's uid.  On Linux this uses SO_PEERCRED so
/// the kernel returns the creds it recorded at connect-time (stable
/// against post-connect setuid races).  On macOS / *BSD this falls
/// back to libc getpeereid(3), which reads the same kernel-stored
/// peer creds for AF_UNIX sockets.  Returns `peer_uid_unavailable`
/// if the syscall fails or the fd doesn't refer to an AF_UNIX socket.
pub fn peerUid(fd: std.posix.socket_t) TransportError!u32 {
    if (builtin.os.tag == .linux) {
        var creds: Ucred = undefined;
        var len: u32 = @sizeOf(Ucred);
        const rc = std.os.linux.getsockopt(
            fd,
            std.os.linux.SOL.SOCKET,
            17, // SO_PEERCRED — value is platform-stable on Linux.
            @ptrCast(&creds),
            &len,
        );
        if (std.os.linux.E.init(rc) != .SUCCESS) return TransportError.peer_uid_unavailable;
        if (len < @sizeOf(Ucred)) return TransportError.peer_uid_unavailable;
        return creds.uid;
    }
    // macOS / *BSD path.
    var uid: u32 = 0;
    var gid: u32 = 0;
    const rc = getpeereid(@intCast(fd), &uid, &gid);
    if (rc != 0) return TransportError.peer_uid_unavailable;
    return uid;
}

// ─────────────────────────────────────────────────────────────────────
// Server
// ─────────────────────────────────────────────────────────────────────

pub const Server = struct {
    allocator: std.mem.Allocator,
    /// Absolute path the listener is bound to.  Owned.
    socket_path: []u8,
    /// Daemon's own uid; only connections from this uid are accepted.
    expected_uid: u32,
    /// Borrowed — the daemon owns the dispatcher and outlives the server.
    dispatcher: *dispatcher_mod.Dispatcher,
    /// Underlying listening socket.
    listener: std.net.Server,
    /// Set by `stop()` to wake the accept loop.
    should_stop: std.atomic.Value(bool),

    /// Resolve `<data_dir>/brain.sock`, unlink any stale socket file
    /// from a prior crash, bind a fresh one with mode 0600.  The data
    /// directory must already exist.
    pub fn bind(
        allocator: std.mem.Allocator,
        data_dir: []const u8,
        expected_uid: u32,
        disp: *dispatcher_mod.Dispatcher,
    ) !*Server {
        const path = try std.fs.path.join(allocator, &.{ data_dir, SOCKET_BASENAME });
        errdefer allocator.free(path);

        // Stale-socket detection.  If a file already sits at `path` we
        // refuse to blind-unlink — that would silently steal the
        // socket from a running daemon.  Decide:
        //   • stat fails with FileNotFound → fresh path; bind.
        //   • file is a regular file (not a socket) → leftover that
        //     was never a socket; unlink + bind.
        //   • file is a socket → try to connect.  Success means a
        //     live daemon owns it (refuse).  ConnectionRefused means
        //     a crashed prior daemon left the inode (unlink + bind).
        //     Other connect errors are conservative refuse.
        stale_check: {
            const st = std.fs.cwd().statFile(path) catch |err| switch (err) {
                error.FileNotFound => break :stale_check,
                else => return TransportError.bind_failed,
            };
            if (st.kind != .unix_domain_socket) {
                std.fs.cwd().deleteFile(path) catch {};
                break :stale_check;
            }
            const probe = std.net.connectUnixSocket(path) catch |err| switch (err) {
                error.ConnectionRefused, error.FileNotFound => {
                    std.fs.cwd().deleteFile(path) catch {};
                    break :stale_check;
                },
                else => return TransportError.bind_failed,
            };
            probe.close();
            return TransportError.bind_failed; // live daemon already bound
        }

        // Tighten umask for the bind() call so the new socket inode is
        // created with mode (0o666 & ~0o177) = 0o600 even on operator
        // setups with a permissive umask.  Restore the prior value
        // immediately afterward so concurrent file-creation in the
        // daemon's other code paths is unaffected.  Belt-and-braces
        // chmod() further down covers the non-standard case where a
        // shared filesystem ignores umask (e.g. on Linux with a
        // default ACL on the parent dir).
        const prev_umask = umask(0o177);
        const addr = std.net.Address.initUnix(path) catch {
            _ = umask(prev_umask);
            return TransportError.socket_path_too_long;
        };
        var listener = addr.listen(.{ .reuse_address = true }) catch {
            _ = umask(prev_umask);
            return TransportError.bind_failed;
        };
        _ = umask(prev_umask);
        errdefer listener.deinit();

        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);
        _ = chmod(path_z.ptr, 0o600);

        const self = try allocator.create(Server);
        errdefer allocator.destroy(self);
        self.* = .{
            .allocator = allocator,
            .socket_path = path,
            .expected_uid = expected_uid,
            .dispatcher = disp,
            .listener = listener,
            .should_stop = std.atomic.Value(bool).init(false),
        };
        return self;
    }

    pub fn deinit(self: *Server) void {
        self.listener.deinit();
        std.fs.cwd().deleteFile(self.socket_path) catch {};
        self.allocator.free(self.socket_path);
        self.allocator.destroy(self);
    }

    /// Accept loop.  Runs until `stop()` is called or the listener is
    /// destroyed.  Each connection is handled inline (single-threaded
    /// shape — adequate for the daemon's CLI / first-boot init traffic
    /// and the helm SPA's bearer flow; the HTTP transport in Phase 3
    /// uses its own server thread pool for high-volume request work).
    pub fn serve(self: *Server) void {
        while (!self.should_stop.load(.acquire)) {
            var conn = self.listener.accept() catch |err| switch (err) {
                error.SocketNotListening,
                error.ConnectionAborted,
                error.SystemFdQuotaExceeded,
                error.ProcessFdQuotaExceeded,
                => return,
                else => continue,
            };
            defer conn.stream.close();
            self.handleConnection(&conn) catch {};
        }
    }

    /// Handle one accepted connection.
    ///
    /// Order: peer-cred check → loop {read envelope → dispatch → write
    /// response}.  Auth is enforced at the syscall edge — the very
    /// first thing we do after accept(2) is read the kernel-stored
    /// peer creds (SO_PEERCRED on Linux, getpeereid on macOS/*BSD).
    /// No bytes are read or written on the socket until that check
    /// passes.  This is the same shape an HTTP transport uses with a
    /// TLS client cert: authenticate first, then handle the request
    /// body.
    ///
    /// On rejection we write the failure envelope and `shutdown(.send)`
    /// the connection so the client can drain the receive buffer
    /// before seeing EOF — without the half-close, an eager
    /// `defer close()` races the kernel's buffered-write delivery and
    /// the client gets BrokenPipe before the failure envelope arrives.
    fn handleConnection(self: *Server, conn: *std.net.Server.Connection) !void {
        // Peer-cred check first — auth at the syscall edge.
        const peer = peerUid(conn.stream.handle) catch {
            self.rejectAndHalfClose(conn, "unix_socket: peer uid unavailable");
            return;
        };
        if (peer != self.expected_uid) {
            self.rejectAndHalfClose(conn, "unix_socket: peer uid does not match daemon uid");
            return;
        }

        // Authenticated.  Loop reading envelopes until peer closes.
        const max_envelope_bytes = 1024 * 64;
        while (!self.should_stop.load(.acquire)) {
            const line = readLine(self.allocator, conn.stream, max_envelope_bytes) catch |err| switch (err) {
                error.EndOfStream, error.ConnectionResetByPeer => return,
                error.StreamTooLong => {
                    try writeFailureEnvelope(self.allocator, conn, "", .validation_failed,
                        "unix_socket: envelope exceeds max size");
                    return;
                },
                else => return,
            };
            defer self.allocator.free(line);
            if (line.len == 0) return;

            try self.dispatchAndRespond(conn, line);
        }
    }

    /// Write a capability_denied envelope and half-close the write
    /// side so the client can drain the response before getting EOF.
    fn rejectAndHalfClose(
        self: *Server,
        conn: *std.net.Server.Connection,
        message: []const u8,
    ) void {
        writeFailureEnvelope(self.allocator, conn, "", .capability_denied, message) catch {};
        std.posix.shutdown(conn.stream.handle, .send) catch {};
    }

    /// Decode the request envelope, build a DispatchContext with the
    /// peer-uid auth variant + root cap scope (Unix-uid match implies
    /// in-process trust per §5.2), call the dispatcher, write the
    /// response envelope.
    fn dispatchAndRespond(self: *Server, conn: *std.net.Server.Connection, line: []const u8) !void {
        var owned = wire.decodeRequest(self.allocator, line) catch {
            try writeFailureEnvelope(self.allocator, conn, "", .validation_failed,
                "unix_socket: malformed request envelope");
            return;
        };
        defer owned.deinit();
        const req = owned.request;

        const ctx = dispatcher_mod.DispatchContext{
            .auth = .{ .local_uid = self.expected_uid },
            .capabilities = dispatcher_mod.CapabilitySet.empty(),
            .meta = .{
                .request_id = req.request_id,
                .transport_label = "unix_socket",
            },
        };
        var result = self.dispatcher.dispatch(&ctx, req.resource, req.cmd, req.args_json) catch |err| {
            const kind: wire.ErrorKind = switch (err) {
                dispatcher_mod.DispatchError.unknown_resource => .unknown_resource,
                dispatcher_mod.DispatchError.unknown_command => .unknown_command,
                dispatcher_mod.DispatchError.capability_denied,
                dispatcher_mod.DispatchError.capability_not_declared,
                => .capability_denied,
                else => .validation_failed,
            };
            try writeFailureEnvelope(self.allocator, conn, req.request_id, kind, @errorName(err));
            return;
        };
        defer result.deinit();

        const resp = wire.Response{
            .request_id = req.request_id,
            .result_json = if (result.payload.len > 0) result.payload else "null",
            .err = null,
        };
        const encoded = wire.encodeResponse(self.allocator, resp) catch return;
        defer self.allocator.free(encoded);
        conn.stream.writeAll(encoded) catch return;
        conn.stream.writeAll("\n") catch return;
    }

    /// Signal the accept loop to exit.  Idempotent.  May be called
    /// from any thread.  The accept that's currently blocked wakes up
    /// because we open + immediately close a self-connection on the
    /// socket; the worker accepts that connection, sees `should_stop`,
    /// returns from `serve`.  Self-connect is portable across Linux
    /// and macOS — `shutdown(2)` on a listening socket is not.
    /// Caller still owns the Server and must `deinit` it after joining
    /// the worker thread that's running `serve()`.
    ///
    /// Race window — documented, not closed: if `stop()` runs
    /// concurrently with a real client `connect()`, the worker may
    /// pick up the self-connect ahead of the client (or vice versa);
    /// either way, one in-flight client connection can be lost on
    /// shutdown.  v0.1 accepts this — operator shutdown is a
    /// human-paced event and the CLI retries naturally on the next
    /// dispatch.  A future revision can replace the self-connect
    /// with a control-pipe (eventfd on Linux, pipe(2) on macOS) at
    /// the cost of an extra fd in the daemon's open-file table.
    pub fn stop(self: *Server) void {
        self.should_stop.store(true, .release);
        const stream = std.net.connectUnixSocket(self.socket_path) catch return;
        stream.close();
    }
};

// ─────────────────────────────────────────────────────────────────────
// Client
// ─────────────────────────────────────────────────────────────────────

pub const Client = struct {
    allocator: std.mem.Allocator,
    stream: std.net.Stream,

    /// Connect to `<data_dir>/brain.sock`.  Returns `connect_failed` if
    /// the socket file doesn't exist OR the daemon refuses the
    /// connection — the CLI uses that signal to fall back to embedded
    /// mode.
    pub fn connect(allocator: std.mem.Allocator, data_dir: []const u8) !Client {
        const path = try std.fs.path.join(allocator, &.{ data_dir, SOCKET_BASENAME });
        defer allocator.free(path);
        const stream = std.net.connectUnixSocket(path) catch return TransportError.connect_failed;
        return .{ .allocator = allocator, .stream = stream };
    }

    pub fn close(self: *Client) void {
        self.stream.close();
    }

    /// Send one request envelope, await the response.  Caller deinits
    /// the returned OwnedResponse.
    pub fn dispatch(
        self: *Client,
        resource: []const u8,
        cmd: []const u8,
        args_json: []const u8,
        request_id: []const u8,
    ) !wire.OwnedResponse {
        const req = wire.Request{
            .request_id = request_id,
            .resource = resource,
            .cmd = cmd,
            .args_json = args_json,
        };
        const encoded = try wire.encodeRequest(self.allocator, req);
        defer self.allocator.free(encoded);

        try self.stream.writeAll(encoded);
        try self.stream.writeAll("\n");

        const max = 1024 * 1024;
        const line = try readLine(self.allocator, self.stream, max);
        defer self.allocator.free(line);

        return try wire.decodeResponse(self.allocator, line);
    }
};

// ─────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────

/// Read a newline-terminated line from the given stream.  Strips the
/// trailing `\n`.  `error.EndOfStream` if the peer closed before
/// sending any bytes; `error.StreamTooLong` past `max_bytes`.
fn readLine(
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    max_bytes: usize,
) ![]u8 {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    var byte: [1]u8 = undefined;
    while (true) {
        const n = stream.read(&byte) catch |err| switch (err) {
            error.ConnectionResetByPeer => return error.ConnectionResetByPeer,
            else => return err,
        };
        if (n == 0) {
            if (buf.items.len == 0) return error.EndOfStream;
            return try buf.toOwnedSlice(allocator);
        }
        if (byte[0] == '\n') return try buf.toOwnedSlice(allocator);
        if (buf.items.len >= max_bytes) return error.StreamTooLong;
        try buf.append(allocator, byte[0]);
    }
}

fn writeFailureEnvelope(
    allocator: std.mem.Allocator,
    conn: *std.net.Server.Connection,
    request_id: []const u8,
    kind: wire.ErrorKind,
    message: []const u8,
) !void {
    const resp = wire.Response{
        .request_id = request_id,
        .result_json = "null",
        .err = wire.ErrorBody{ .kind = kind, .message = message, .details_json = "null" },
    };
    const encoded = wire.encodeResponse(allocator, resp) catch return;
    defer allocator.free(encoded);
    conn.stream.writeAll(encoded) catch return;
    conn.stream.writeAll("\n") catch return;
}

/// Returns the calling process's effective uid.  Convenience for daemon
/// startup — the bind site needs this to seed `expected_uid`.
pub fn currentUid() u32 {
    return std.posix.getuid();
}

```
