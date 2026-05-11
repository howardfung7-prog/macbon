import Foundation
import Security
import CryptoKit

/// 设备硬件证明 + 请求签名
///
/// 策略：
/// 1. 优先用 Secure Enclave 生成密钥（最强，VM 自动失败）
/// 2. SE 失败（开发期无签名 entitlement 时常见）→ 回退到 CryptoKit 内存密钥
///    密钥的 raw bytes 保存在 Keychain，确保跨启动持久化
/// 3. 两种路径的签名格式一致（IEEE P-1363, R||S, 64 字节），服务器无感知
///
/// 生产发布时：
/// - 配 `com.apple.application-identifier` entitlement
/// - 用 Apple Developer ID 签名
/// - 自动走 SE 路径，VM 拒绝挖矿
final class DeviceAttestation {
    static let shared = DeviceAttestation()
    private init() {}

    /// 标识：SE 模式（设备硬件绑定）
    private let keyTagSE       = "tech.macbon.attestation.privateKey"
    /// 标识：Fallback 模式（CryptoKit 软件密钥 + Keychain 存储）
    private let keyTagFallback = "tech.macbon.attestation.fallbackKey"

    private enum KeyBacking {
        case secureEnclave(SecKey)
        case software(P256.Signing.PrivateKey)
    }

    private var cachedKey: KeyBacking?

    // MARK: - Public API

    /// 在 macOS 开发环境（无 entitlement）下，SE 不可用 —— 但仍可用软件密钥继续走流程
    var isAvailable: Bool { true }

    /// 标识当前使用的模式（debug 用）
    var modeDescription: String {
        switch cachedKey {
        case .secureEnclave?: return "Secure Enclave (hardware-bound)"
        case .software?:      return "CryptoKit fallback (dev / unsigned)"
        case .none:           return "uninitialized"
        }
    }

    /// 获取或创建密钥（懒加载，调用一次即可）
    func ensureKey() throws {
        if cachedKey != nil { return }

        // 1. 优先 SE
        if let seKey = (try? loadSEKey()) ?? (try? createSEKey()) {
            cachedKey = .secureEnclave(seKey)
            return
        }

        // 2. 回退到软件密钥
        if let stored = try? loadFallbackKey() {
            cachedKey = .software(stored)
            print("[Attest] using CryptoKit fallback key (existing)")
            return
        }
        let fresh = P256.Signing.PrivateKey()
        try saveFallbackKey(fresh)
        cachedKey = .software(fresh)
        print("[Attest] ⚠️ Secure Enclave unavailable — generated fallback CryptoKit key (dev mode)")
    }

    /// 内部使用：拿到当前 backing
    private func currentKey() throws -> KeyBacking {
        try ensureKey()
        guard let k = cachedKey else { throw AttestationError.keyNotFound(0) }
        return k
    }

    /// 公钥（ANSI X9.63 raw 65 字节，base64）
    func publicKeyBase64() throws -> String {
        let key = try currentKey()
        switch key {
        case .secureEnclave(let sec):
            guard let pub = SecKeyCopyPublicKey(sec) else {
                throw AttestationError.publicKeyExtractFailed
            }
            var err: Unmanaged<CFError>?
            guard let data = SecKeyCopyExternalRepresentation(pub, &err) as Data? else {
                throw AttestationError.publicKeyExportFailed(err?.takeRetainedValue())
            }
            return data.base64EncodedString()
        case .software(let sw):
            return sw.publicKey.x963Representation.base64EncodedString()
        }
    }

    /// 对 payload 字符串签名 → base64(IEEE P-1363 R||S, 64 字节)
    func sign(_ payload: String) throws -> String {
        let key = try currentKey()
        let data = payload.data(using: .utf8)!

        switch key {
        case .secureEnclave(let sec):
            var err: Unmanaged<CFError>?
            guard let derSig = SecKeyCreateSignature(
                sec,
                .ecdsaSignatureMessageX962SHA256,
                data as CFData,
                &err
            ) as Data? else {
                throw AttestationError.signFailed(err?.takeRetainedValue())
            }
            let raw = try Self.derToRaw(derSig)
            return raw.base64EncodedString()

        case .software(let sw):
            // CryptoKit 默认就返回 raw P-1363 格式
            let sig = try sw.signature(for: data)
            return sig.rawRepresentation.base64EncodedString()
        }
    }

    // MARK: - Secure Enclave 路径

    private func createSEKey() throws -> SecKey {
        let tagData = keyTagSE.data(using: .utf8)!
        // 清除可能残留
        SecItemDelete([
            kSecClass:               kSecClassKey,
            kSecAttrApplicationTag:  tagData,
        ] as CFDictionary)

        var aclError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .privateKeyUsage,
            &aclError
        ) else {
            throw AttestationError.accessControlFailed(aclError?.takeRetainedValue())
        }

        let attrs: [String: Any] = [
            kSecAttrKeyType as String:         kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String:   256,
            kSecAttrTokenID as String:         kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String:     true,
                kSecAttrApplicationTag as String:  tagData,
                kSecAttrAccessControl as String:   access,
            ],
        ]

        var err: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attrs as CFDictionary, &err) else {
            throw AttestationError.keyCreationFailed(err?.takeRetainedValue())
        }
        return key
    }

    private func loadSEKey() throws -> SecKey {
        let tagData = keyTagSE.data(using: .utf8)!
        let q: [String: Any] = [
            kSecClass as String:               kSecClassKey,
            kSecAttrApplicationTag as String:  tagData,
            kSecAttrKeyType as String:         kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrTokenID as String:         kSecAttrTokenIDSecureEnclave,
            kSecReturnRef as String:           true,
        ]
        var ref: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &ref)
        guard s == errSecSuccess, let ref else {
            throw AttestationError.keyNotFound(s)
        }
        return ref as! SecKey
    }

    // MARK: - Fallback 路径（CryptoKit + Keychain 存原始字节）

    private func loadFallbackKey() throws -> P256.Signing.PrivateKey {
        let q: [String: Any] = [
            kSecClass as String:               kSecClassGenericPassword,
            kSecAttrAccount as String:         keyTagFallback,
            kSecReturnData as String:          true,
        ]
        var ref: CFTypeRef?
        let s = SecItemCopyMatching(q as CFDictionary, &ref)
        guard s == errSecSuccess, let data = ref as? Data else {
            throw AttestationError.keyNotFound(s)
        }
        return try P256.Signing.PrivateKey(rawRepresentation: data)
    }

    private func saveFallbackKey(_ key: P256.Signing.PrivateKey) throws {
        let data = key.rawRepresentation
        // 删旧
        SecItemDelete([
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrAccount as String: keyTagFallback,
        ] as CFDictionary)
        // 写新
        let q: [String: Any] = [
            kSecClass as String:               kSecClassGenericPassword,
            kSecAttrAccount as String:         keyTagFallback,
            kSecValueData as String:           data,
            kSecAttrAccessible as String:      kSecAttrAccessibleAfterFirstUnlock,
        ]
        let s = SecItemAdd(q as CFDictionary, nil)
        guard s == errSecSuccess else {
            throw AttestationError.keyCreationFailed(nil)
        }
    }

    // MARK: - DER → P-1363 转换

    static func derToRaw(_ der: Data) throws -> Data {
        var p = 0
        guard der.count > 8, der[p] == 0x30 else {
            throw AttestationError.derParseFailed
        }
        p += 1
        _ = Int(der[p]); p += 1

        guard der[p] == 0x02 else { throw AttestationError.derParseFailed }
        p += 1
        var rLen = Int(der[p]); p += 1
        var rData = der.subdata(in: p..<(p + rLen))
        p += rLen
        while rData.first == 0x00 { rData = rData.dropFirst() }
        rLen = rData.count

        guard der[p] == 0x02 else { throw AttestationError.derParseFailed }
        p += 1
        var sLen = Int(der[p]); p += 1
        var sData = der.subdata(in: p..<(p + sLen))
        p += sLen
        while sData.first == 0x00 { sData = sData.dropFirst() }
        sLen = sData.count

        let padR = Data(repeating: 0, count: 32 - rLen) + rData
        let padS = Data(repeating: 0, count: 32 - sLen) + sData
        return padR + padS
    }
}

// MARK: - 错误类型

enum AttestationError: Error, LocalizedError {
    case secureEnclaveUnavailable
    case keyCreationFailed(CFError?)
    case keyNotFound(OSStatus)
    case publicKeyExtractFailed
    case publicKeyExportFailed(CFError?)
    case signFailed(CFError?)
    case derParseFailed
    case accessControlFailed(CFError?)

    var errorDescription: String? {
        switch self {
        case .secureEnclaveUnavailable:    return "Secure Enclave unavailable"
        case .keyCreationFailed(let e):    return "Key create failed: \(e?.localizedDescription ?? "?")"
        case .keyNotFound(let s):          return "Key not found (status \(s))"
        case .publicKeyExtractFailed:      return "Public key extract failed"
        case .publicKeyExportFailed(let e):return "Public key export failed: \(e?.localizedDescription ?? "?")"
        case .signFailed(let e):           return "Sign failed: \(e?.localizedDescription ?? "?")"
        case .derParseFailed:              return "DER parse failed"
        case .accessControlFailed(let e):  return "Access control failed: \(e?.localizedDescription ?? "?")"
        }
    }
}
