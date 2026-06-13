---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/world-beam/apps/world_host/lib/world_host/cell_engine.ex
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.317786+00:00
---

# runtime/world-beam/apps/world_host/lib/world_host/cell_engine.ex

```ex
defmodule WorldHost.CellEngine do
  @moduledoc """
  Per-region Wasmex instance of the cell-engine WASM kernel.

  One engine per region. Each Region supervisor starts an instance under
  `WorldHost.CellEngineDynSupervisor` and registers it in
  `WorldHost.CellEngineRegistry` keyed by region_id.

  Public API all takes a region_id as the first argument:

    * `check_substructural_op(region_id, linearity, op)` — K1 gate DUP/DROP.
    * `execute_named_host_call(region_id, name)` — run a script that
      dispatches through OP_CALLHOST.
    * `register_host_fn(region_id, name, fun)` — make `name` callable
      from within a script running in that region.
    * `clear_host_functions(region_id)` — wipe the registry for a region.

  Host-function registry is an ETS table with keys `{region_id, name}`
  so lookups from inside the Wasmex callback don't have to re-enter the
  GenServer mailbox (that would deadlock — the callback fires inside a
  `GenServer.call`).
  """

  use GenServer
  require Logger

  @io_base 0x300000
  @io_script @io_base + 0x1000

  @cell_size 1024
  @magic_1 0xDEADBEEF
  @magic_2 0xCAFEBABE
  @magic_3 0x13371337
  @magic_4 0x42424242

  @op_pushdata1 0x4C
  @op_pushdata2 0x4D
  @op_drop 0x75
  @op_dup 0x76
  @op_true 0x51
  @op_callhost 0xD0

  @err_cannot_duplicate_linear 22
  @err_cannot_discard_linear 23
  @err_cannot_duplicate_affine 24
  @err_cannot_discard_relevant 25
  @err_unknown_host_function -1

  @dispatch_table :world_host_cell_engine_dispatch

  # Resolved at runtime so the path works both in the source tree and inside
  # a mix release (priv/ is bundled by `mix release` and unpacked alongside
  # the BEAM VM — compile-time Path.expand(__DIR__) would bake in the source
  # path and break on any machine that only has the release tarball).
  #
  # To build the WASM: run `mix wasm` from runtime/world-beam/ (or
  # `cd core/cell-engine && zig build` manually).
  defp wasm_path, do: Application.app_dir(:world_host, "priv/cell-engine.wasm")

  def start_link(opts) do
    region_id = Keyword.fetch!(opts, :region_id)
    GenServer.start_link(__MODULE__, region_id, name: via(region_id))
  end

  def via(region_id), do: {:via, Registry, {WorldHost.CellEngineRegistry, region_id}}

  def check_substructural_op(region_id, linearity, op)
      when is_binary(region_id) and linearity in [:linear, :affine, :relevant] and
             op in [:dup, :drop] do
    GenServer.call(via(region_id), {:check, linearity, op})
  end

  def execute_named_host_call(region_id, name)
      when is_binary(region_id) and is_binary(name) and byte_size(name) <= 255 do
    GenServer.call(via(region_id), {:call_host, name})
  end

  def register_host_fn(region_id, name, fun)
      when is_binary(region_id) and is_binary(name) and is_function(fun, 0) do
    ensure_table!()
    :ets.insert(@dispatch_table, {{region_id, name}, fun})
    :ok
  end

  def clear_host_functions(region_id) when is_binary(region_id) do
    ensure_table!()
    :ets.match_delete(@dispatch_table, {{region_id, :_}, :_})
    :ok
  end

  def get_wasmex(region_id) when is_binary(region_id) do
    GenServer.call(via(region_id), :get_wasmex)
  end

  @impl true
  def init(region_id) do
    ensure_table!()
    {:ok, %{region_id: region_id, wasmex: nil}, {:continue, :boot}}
  end

  @impl true
  def handle_continue(:boot, state) do
    path = wasm_path()

    unless File.exists?(path) do
      raise "cell-engine.wasm missing at #{path} — run `mix wasm` from runtime/world-beam/"
    end

    bytes = File.read!(path)
    region_id = state.region_id

    imports = %{
      "host" => %{
        "host_call_by_name" =>
          {:fn, [:i32, :i32], [:i32],
           fn caller, ptr, len ->
             dispatch_host_call(region_id, caller, ptr, len)
           end},
        "host_fetch_cell" =>
          {:fn, [:i32, :i32, :i32, :i32], [:i32], fn _c, _o, _s, _off, _out -> 0 end}
      }
    }

    {:ok, pid} = Wasmex.start_link(%{bytes: bytes, imports: imports})
    {:ok, [init_rc]} = Wasmex.call_function(pid, :kernel_init, [])

    if init_rc != 0 do
      Logger.warning("kernel_init(#{region_id}) returned non-zero: #{init_rc}")
    end

    {:ok, _} = Wasmex.call_function(pid, :kernel_set_enforcement, [1])

    Logger.debug("cell-engine booted for region=#{region_id} (wasmex pid #{inspect(pid)})")
    {:noreply, %{state | wasmex: pid}}
  end

  @impl true
  def handle_call({:check, linearity, op}, _from, %{wasmex: pid} = state) do
    {:reply, do_check(pid, linearity, op), state}
  end

  def handle_call({:call_host, name}, _from, %{wasmex: pid} = state) do
    {:reply, do_call_host(pid, name), state}
  end

  def handle_call(:get_wasmex, _from, %{wasmex: pid} = state) do
    {:reply, pid, state}
  end

  defp do_check(pid, linearity, op) do
    {:ok, _} = Wasmex.call_function(pid, :kernel_reset, [])
    {:ok, _} = Wasmex.call_function(pid, :kernel_set_enforcement, [1])

    script = build_substructural_script(linearity, op)

    case load_and_execute(pid, script) do
      {:ok, 0} -> {:ok, :accepted}
      {:ok, rc} -> classify_substructural(rc, pid)
      err -> err
    end
  end

  defp classify_substructural(@err_cannot_duplicate_linear, _),
    do: {:error, {:linearity_violation, "cannot_duplicate_linear", @err_cannot_duplicate_linear}}

  defp classify_substructural(@err_cannot_discard_linear, _),
    do: {:error, {:linearity_violation, "cannot_discard_linear", @err_cannot_discard_linear}}

  defp classify_substructural(@err_cannot_duplicate_affine, _),
    do: {:error, {:linearity_violation, "cannot_duplicate_affine", @err_cannot_duplicate_affine}}

  defp classify_substructural(@err_cannot_discard_relevant, _),
    do: {:error, {:linearity_violation, "cannot_discard_relevant", @err_cannot_discard_relevant}}

  defp classify_substructural(rc, pid),
    do: {:error, {:kernel_error, rc, read_error_message(pid)}}

  defp do_call_host(pid, name) do
    {:ok, _} = Wasmex.call_function(pid, :kernel_reset, [])
    script = build_callhost_script(name)

    case load_and_execute(pid, script) do
      {:ok, 0} -> {:ok, :accepted}
      {:ok, @err_unknown_host_function} -> {:error, :unknown_host_function}
      {:ok, rc} -> {:error, {:kernel_error, rc, read_error_message(pid)}}
      err -> err
    end
  end

  defp dispatch_host_call(region_id, caller, ptr, len) do
    name = read_wasm_string(caller, ptr, len)

    case :ets.lookup(@dispatch_table, {region_id, name}) do
      [{_, fun}] ->
        result = fun.()

        cond do
          is_integer(result) and result >= 1 and result <= 0x7FFFFFFF -> result
          # Coerce anything unrepresentable-as-positive-i32 to 1 so the
          # script still verifies as truthy.
          true -> 1
        end

      [] ->
        # 0xFFFFFFFF as signed i32 is -1. Wasmex's i32 return type only
        # accepts values in [-2^31, 2^31-1], so we pass -1 here; the kernel
        # reads the u32 bit pattern and sees 0xFFFFFFFF → unknown_host_function.
        -1
    end
  end

  defp read_wasm_string(%{caller: caller, memory: memory}, ptr, len) do
    Wasmex.Memory.read_binary(caller, memory, ptr, len)
  end

  defp read_wasm_string(_ctx, _ptr, _len), do: ""

  defp load_and_execute(pid, script) do
    {:ok, mem} = Wasmex.memory(pid)
    {:ok, store} = Wasmex.store(pid)

    :ok = Wasmex.Memory.write_binary(store, mem, @io_script, script)

    {:ok, [load_rc]} =
      Wasmex.call_function(pid, :kernel_load_script, [@io_script, byte_size(script)])

    if load_rc != 0 do
      {:error, {:kernel_error, load_rc, "kernel_load_script failed (rc=#{load_rc})"}}
    else
      {:ok, [exec_rc]} = Wasmex.call_function(pid, :kernel_execute, [])
      {:ok, exec_rc}
    end
  end

  defp read_error_message(pid) do
    {:ok, mem} = Wasmex.memory(pid)
    {:ok, store} = Wasmex.store(pid)

    case Wasmex.call_function(pid, :kernel_get_error, []) do
      {:ok, [ptr]} when is_integer(ptr) and ptr > 0 ->
        raw = Wasmex.Memory.read_binary(store, mem, ptr, 256)

        case :binary.split(raw, <<0>>) do
          [head, _] -> head
          [all] -> all
        end

      _ ->
        ""
    end
  end

  defp build_substructural_script(linearity, op) do
    cell = build_cell(linearity)
    op_byte = substructural_opcode(op)
    len_lo = rem(@cell_size, 256)
    len_hi = div(@cell_size, 256)

    tail =
      case op do
        :drop -> <<op_byte, @op_true>>
        _ -> <<op_byte>>
      end

    <<@op_pushdata2, len_lo, len_hi, cell::binary, tail::binary>>
  end

  defp build_callhost_script(name) do
    <<@op_pushdata1, byte_size(name), name::binary, @op_callhost>>
  end

  defp build_cell(linearity) do
    lin_value = linearity_value(linearity)
    type_hash = :binary.copy(<<0xAA>>, 32)
    owner_id = :binary.copy(<<0xBB>>, 16)

    core =
      <<
        @magic_1::little-32,
        @magic_2::little-32,
        @magic_3::little-32,
        @magic_4::little-32,
        lin_value::little-32,
        1::little-32,
        1::little-32,
        0,
        0,
        type_hash::binary,
        owner_id::binary
      >>

    pad = :binary.copy(<<0>>, @cell_size - byte_size(core))
    <<core::binary, pad::binary>>
  end

  defp substructural_opcode(:dup), do: @op_dup
  defp substructural_opcode(:drop), do: @op_drop

  defp linearity_value(:linear), do: 1
  defp linearity_value(:affine), do: 2
  defp linearity_value(:relevant), do: 3

  defp ensure_table! do
    if :ets.whereis(@dispatch_table) == :undefined do
      :ets.new(@dispatch_table, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])
    end

    :ok
  end
end

```
