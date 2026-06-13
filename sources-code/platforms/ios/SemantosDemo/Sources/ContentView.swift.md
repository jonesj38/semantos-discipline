---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/ios/SemantosDemo/Sources/ContentView.swift
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.986382+00:00
---

# platforms/ios/SemantosDemo/Sources/ContentView.swift

```swift
// ContentView.swift — Demo UI exercising all Semantos kernel paths
// Phase 30F: Initialize, Write/Read cells, Capability check, LINEAR consume, Anchor.

import SwiftUI

struct ContentView: View {
    @StateObject private var vm = DemoViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // ── Status ──
                    GroupBox("Kernel Status") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Circle()
                                    .fill(vm.isInitialized ? Color.green : Color.red)
                                    .frame(width: 10, height: 10)
                                Text(vm.isInitialized ? "Initialized" : "Not Initialized")
                                Spacer()
                                Text("v\(vm.kernelVersion)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // ── Actions ──
                    GroupBox("Actions") {
                        VStack(spacing: 12) {
                            ActionButton(title: "Initialize Kernel", icon: "power") {
                                vm.initializeKernel()
                            }

                            ActionButton(title: "Write Cell", icon: "square.and.pencil") {
                                vm.writeSampleCell()
                            }

                            ActionButton(title: "Read Cell", icon: "doc.text.magnifyingglass") {
                                vm.readSampleCell()
                            }

                            ActionButton(title: "Verify Cell Proof", icon: "checkmark.shield") {
                                vm.verifyCellProof()
                            }

                            ActionButton(title: "Capability Check", icon: "lock.shield") {
                                vm.checkCapability()
                            }

                            ActionButton(title: "LINEAR Consume", icon: "bolt.circle") {
                                vm.consumeLinear()
                            }

                            ActionButton(title: "Shutdown Kernel", icon: "power.circle") {
                                vm.shutdownKernel()
                            }
                        }
                    }

                    // ── Output Log ──
                    GroupBox("Output") {
                        ScrollView {
                            Text(vm.outputLog)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 200)
                    }

                    // ── Last Error ──
                    if let error = vm.lastError {
                        GroupBox("Last Error") {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Semantos Demo")
        }
    }
}

struct ActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 24)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ViewModel

@MainActor
class DemoViewModel: ObservableObject {
    @Published var isInitialized = false
    @Published var kernelVersion = "unknown"
    @Published var outputLog = ""
    @Published var lastError: String?

    private var kernel: SemantosKernel?
    private let samplePath = "/demo/hello"
    private let sampleData = "Hello, Semantos!".data(using: .utf8)!

    func initializeKernel() {
        let kernel = SemantosKernel()
        do {
            try kernel.initialize()
            self.kernel = kernel
            self.isInitialized = true
            self.kernelVersion = SemantosKernel.version
            log("Kernel initialized (version: \(kernelVersion))")
            lastError = nil
        } catch {
            log("INIT FAILED: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    func shutdownKernel() {
        kernel?.shutdown()
        kernel = nil
        isInitialized = false
        log("Kernel shut down")
        lastError = nil
    }

    func writeSampleCell() {
        guard let kernel = kernel else {
            log("ERROR: Kernel not initialized")
            return
        }
        do {
            try kernel.cellWrite(path: samplePath, data: sampleData)
            let hex = sampleData.map { String(format: "%02x", $0) }.joined()
            log("WRITE \(samplePath): \(sampleData.count) bytes [\(hex)]")
            lastError = nil
        } catch {
            log("WRITE FAILED: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    func readSampleCell() {
        guard let kernel = kernel else {
            log("ERROR: Kernel not initialized")
            return
        }
        do {
            if let data = try kernel.cellRead(path: samplePath) {
                let hex = data.map { String(format: "%02x", $0) }.joined()
                let str = String(data: data, encoding: .utf8) ?? "(binary)"
                log("READ \(samplePath): \(data.count) bytes [\(hex)]")
                log("  text: \"\(str)\"")

                // Verify round-trip
                if data == sampleData {
                    log("  ROUND-TRIP: identical bytes confirmed")
                } else {
                    log("  ROUND-TRIP: MISMATCH! Written \(sampleData.count)B, read \(data.count)B")
                }
            } else {
                log("READ \(samplePath): not found")
            }
            lastError = nil
        } catch {
            log("READ FAILED: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    func verifyCellProof() {
        guard let kernel = kernel else {
            log("ERROR: Kernel not initialized")
            return
        }
        do {
            // Build a SHA-256 proof of the sample data
            // The kernel expects the first 32 bytes to be the SHA-256 hash
            let hash = sha256(data: sampleData)
            try kernel.cellVerify(path: samplePath, proof: hash)
            log("VERIFY \(samplePath): proof valid")
            lastError = nil
        } catch {
            log("VERIFY FAILED: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    func checkCapability() {
        guard let kernel = kernel else {
            log("ERROR: Kernel not initialized")
            return
        }
        let certId = "test-cert-001".data(using: .utf8)!
        let domainFlag: UInt32 = 0x01

        do {
            try kernel.capabilityCheck(certId: certId, domainFlag: domainFlag)
            log("CAPABILITY CHECK: granted (cert=test-cert-001, domain=0x01)")
            lastError = nil
        } catch let error as SemantosError {
            switch error {
            case .denied:
                log("CAPABILITY CHECK: denied (expected without identity callback)")
            case .callbackNotRegistered:
                log("CAPABILITY CHECK: identity callback not registered (expected in demo)")
            default:
                log("CAPABILITY CHECK: \(error.localizedDescription)")
            }
            lastError = error.localizedDescription
        } catch {
            log("CAPABILITY CHECK FAILED: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    func consumeLinear() {
        guard let kernel = kernel else {
            log("ERROR: Kernel not initialized")
            return
        }
        let consumerCert = "consumer-cert-001".data(using: .utf8)!

        do {
            try kernel.linearConsume(path: samplePath, consumerCert: consumerCert)
            log("LINEAR CONSUME \(samplePath): consumed successfully")
            lastError = nil
        } catch let error as SemantosError {
            switch error {
            case .alreadyConsumed:
                log("LINEAR CONSUME: already consumed (expected on second call)")
            case .denied:
                log("LINEAR CONSUME: cell is not LINEAR type")
            default:
                log("LINEAR CONSUME: \(error.localizedDescription)")
            }
            lastError = error.localizedDescription
        } catch {
            log("LINEAR CONSUME FAILED: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        outputLog += "[\(timestamp)] \(message)\n"
    }

    /// Simple SHA-256 using CommonCrypto (available on all Apple platforms).
    private func sha256(data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { buf in
            guard let ptr = buf.baseAddress else { return }
            CC_SHA256(ptr, CC_LONG(buf.count), &hash)
        }
        return Data(hash)
    }
}

// CommonCrypto bridge — available on all Apple platforms without import
#if canImport(CommonCrypto)
import CommonCrypto
#else
// Fallback type definitions for compilation outside Xcode
typealias CC_LONG = UInt32
func CC_SHA256(_ data: UnsafeRawPointer, _ len: CC_LONG, _ md: UnsafeMutablePointer<UInt8>) -> UnsafeMutablePointer<UInt8>? {
    // This branch should never execute on iOS/macOS
    return nil
}
#endif

```
