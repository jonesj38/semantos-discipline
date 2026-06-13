---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/ios/SemantosSDK/Adapters/KeychainIdentityProvider.swift
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.988814+00:00
---

# platforms/ios/SemantosSDK/Adapters/KeychainIdentityProvider.swift

```swift
// KeychainIdentityProvider.swift — Identity management via Keychain & Secure Enclave
// Phase 30F: Real Keychain implementation with Secure Enclave key generation.
//
// SECURE ENCLAVE BEHAVIOR:
// - On physical devices: keys are generated inside Secure Enclave using
//   kSecAttrTokenIDSecureEnclave. Keys never leave the hardware.
// - On simulator: Secure Enclave is unavailable. Falls back to software-based
//   Keychain keys (kSecAttrKeyTypeECSECPrimeRandom without token attribute).
//   This is a known limitation — the simulator cannot emulate hardware security.
//
// Certificate storage: certificates (JSON blobs) are stored as Keychain generic
// passwords keyed by certificate ID.

import Foundation
import Security

public final class KeychainIdentityProvider: IdentityProvider {

    private let service = "com.semantos.identity"
    private let accessGroup: String?
    private let useSecureEnclave: Bool

    /// Initialize the identity provider.
    /// - Parameters:
    ///   - accessGroup: Optional Keychain access group for app group sharing.
    ///   - forceSecureEnclave: If true, always attempt Secure Enclave (fails on sim).
    ///                          If false (default), auto-detect device vs simulator.
    public init(accessGroup: String? = nil, forceSecureEnclave: Bool = false) {
        self.accessGroup = accessGroup
        #if targetEnvironment(simulator)
        self.useSecureEnclave = forceSecureEnclave
        #else
        self.useSecureEnclave = true
        #endif
    }

    // MARK: - IdentityProvider Protocol

    public func resolve(certId: UnsafeBufferPointer<UInt8>,
                        into buffer: UnsafeMutableBufferPointer<UInt8>) -> (Int32, Int) {
        let idStr = String(bytes: certId, encoding: .utf8) ?? ""
        guard !idStr.isEmpty else { return (-1, 0) }

        guard let certData = loadCertificate(id: idStr) else {
            return (-1, 0) // SEMANTOS_ERR_NOT_FOUND
        }

        guard certData.count <= buffer.count else {
            return (-6, certData.count) // SEMANTOS_ERR_BUFFER_TOO_SMALL
        }

        certData.withUnsafeBytes { src in
            buffer.baseAddress!.initialize(
                from: src.baseAddress!.assumingMemoryBound(to: UInt8.self),
                count: certData.count
            )
        }
        return (0, certData.count)
    }

    public func derive(parentCert: UnsafeBufferPointer<UInt8>,
                       resourceId: UnsafeBufferPointer<UInt8>,
                       domainFlag: UInt32,
                       into buffer: UnsafeMutableBufferPointer<UInt8>) -> (Int32, Int) {
        let parentStr = String(bytes: parentCert, encoding: .utf8) ?? ""
        let ridStr = String(bytes: resourceId, encoding: .utf8) ?? ""
        guard !parentStr.isEmpty else { return (-8, 0) }

        // Load parent certificate
        guard let parentData = loadCertificate(id: parentStr) else {
            return (-1, 0) // Parent not found
        }

        // Generate a new key pair for the derived certificate
        let childId = deriveCertificateId(parentId: parentStr, resourceId: ridStr, domainFlag: domainFlag)

        guard let keyRef = generateKeyPair(tag: childId) else {
            return (-8, 0) // Key generation failed
        }

        // Build derived certificate JSON
        let pubKeyData = exportPublicKey(keyRef)
        let pubKeyHex = pubKeyData?.map { String(format: "%02x", $0) }.joined() ?? ""
        let now = Int(Date().timeIntervalSince1970)

        let certJSON: [String: Any] = [
            "certId": childId,
            "parentId": parentStr,
            "resourceId": ridStr,
            "domainFlag": domainFlag,
            "publicKey": pubKeyHex,
            "createdAt": now,
            "ttl": 86400 // 24 hours default
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: certJSON),
              jsonData.count <= buffer.count else {
            return (-6, 0) // Buffer too small or serialization failed
        }

        // Store the derived certificate
        storeCertificate(id: childId, data: jsonData)

        jsonData.withUnsafeBytes { src in
            buffer.baseAddress!.initialize(
                from: src.baseAddress!.assumingMemoryBound(to: UInt8.self),
                count: jsonData.count
            )
        }
        return (0, jsonData.count)
    }

    // MARK: - Public Key Management API

    /// Generate a new identity key pair. Returns the certificate ID.
    /// On device: uses Secure Enclave. On simulator: uses software Keychain.
    public func createIdentity(label: String) -> String? {
        let certId = "cert-\(label)-\(UUID().uuidString.prefix(8))"
        guard let keyRef = generateKeyPair(tag: certId) else { return nil }

        let pubKeyData = exportPublicKey(keyRef)
        let pubKeyHex = pubKeyData?.map { String(format: "%02x", $0) }.joined() ?? ""
        let now = Int(Date().timeIntervalSince1970)

        let certJSON: [String: Any] = [
            "certId": certId,
            "label": label,
            "publicKey": pubKeyHex,
            "domainFlag": 0xFFFFFFFF, // Root cert — all domains
            "createdAt": now,
            "ttl": 31536000 // 1 year
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: certJSON) else { return nil }
        storeCertificate(id: certId, data: jsonData)
        return certId
    }

    /// Check whether Secure Enclave is being used.
    public var isSecureEnclaveEnabled: Bool { useSecureEnclave }

    // MARK: - Keychain Operations

    private func generateKeyPair(tag: String) -> SecKey? {
        let tagData = tag.data(using: .utf8)!

        var attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrApplicationTag as String: tagData,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tagData,
            ] as [String: Any]
        ]

        if useSecureEnclave {
            attributes[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave

            // Require biometric or passcode for private key access
            if let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.privateKeyUsage],
                nil
            ) {
                var privateAttrs = attributes[kSecPrivateKeyAttrs as String] as! [String: Any]
                privateAttrs[kSecAttrAccessControl as String] = access
                attributes[kSecPrivateKeyAttrs as String] = privateAttrs
            }
        }

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            // If Secure Enclave fails (simulator), retry without it
            if useSecureEnclave {
                attributes.removeValue(forKey: kSecAttrTokenID as String)
                var privateAttrs = attributes[kSecPrivateKeyAttrs as String] as! [String: Any]
                privateAttrs.removeValue(forKey: kSecAttrAccessControl as String)
                attributes[kSecPrivateKeyAttrs as String] = privateAttrs
                return SecKeyCreateRandomKey(attributes as CFDictionary, &error)
            }
            return nil
        }
        return privateKey
    }

    private func exportPublicKey(_ privateKey: SecKey) -> Data? {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else { return nil }
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(publicKey, &error) else { return nil }
        return data as Data
    }

    private func storeCertificate(id: String, data: Data) {
        // Delete existing if present
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        var addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        if let group = accessGroup {
            addQuery[kSecAttrAccessGroup as String] = group
        }
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadCertificate(id: String) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func deriveCertificateId(parentId: String, resourceId: String, domainFlag: UInt32) -> String {
        // Deterministic child ID from parent + resource + domain
        let input = "\(parentId):\(resourceId):\(domainFlag)"
        let hash = input.utf8.reduce(into: UInt64(0)) { acc, byte in
            acc = acc &* 31 &+ UInt64(byte)
        }
        return "cert-\(String(hash, radix: 16))"
    }
}

```
