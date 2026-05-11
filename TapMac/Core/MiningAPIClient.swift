import Foundation

/// 与挖矿后端通信的轻量 HTTP 客户端
/// 所有方法均为 async，调用方负责在合适上下文中执行
struct MiningAPIClient {
    static let shared = MiningAPIClient()

    private let baseURL = "https://ikmjwquwrqxpkxwtgjkw.supabase.co/functions/v1"
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10
        return URLSession(configuration: cfg)
    }()

    // MARK: - Attestation

    /// 注册设备公钥到服务器（一次性，幂等）
    /// 返回 true = 已注册（无论是本次新注册还是之前注册过）
    func registerAttestation(deviceID: String) async -> Bool {
        do {
            let publicKey = try DeviceAttestation.shared.publicKeyBase64()
            guard let url = URL(string: "\(baseURL)/attest") else { return false }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode([
                "deviceID":  deviceID,
                "publicKey": publicKey,
            ])
            let (_, resp) = try await session.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            print("[Attest] registration failed: \(error)")
            return false
        }
    }

    // MARK: - Connectivity

    /// 简单 ping，返回服务器是否可达
    func ping() async -> Bool {
        guard let url = URL(string: "\(baseURL)/ping") else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Submit Hour

    struct HourReport: Encodable {
        let deviceID: String
        let solAddress: String
        let utcDate: String   // "2026-05-09"
        let utcHour: Int      // 0–23
        let tapCount: Int
    }

    struct HourResponse: Decodable {
        let success: Bool
        let tokenBalance: Double   // 累计 Token 余额
        let message: String?
    }

    /// 向服务器提交某小时的拍击数据，返回最新 Token 余额
    func submitHour(_ report: HourReport) async throws -> Double {
        guard let url = URL(string: "\(baseURL)/report") else {
            throw URLError(.badURL)
        }

        // 签名 payload：必须与服务端 canonical 完全一致
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let canonical = "\(report.deviceID)|\(report.solAddress)|\(report.utcDate)|\(report.utcHour)|\(report.tapCount)|\(timestamp)"
        let signature = try DeviceAttestation.shared.sign(canonical)

        let payload: [String: Any] = [
            "deviceID":   report.deviceID,
            "solAddress": report.solAddress,
            "utcDate":    report.utcDate,
            "utcHour":    report.utcHour,
            "tapCount":   report.tapCount,
            "timestamp":  timestamp,
            "signature":  signature,
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            print("[API] /report \(status) — \(body)")
            print("[API] canonical was: \(canonical)")
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(HourResponse.self, from: data)
        guard decoded.success else { throw URLError(.badServerResponse) }
        return decoded.tokenBalance
    }

    // MARK: - Daily Device Sync

    /// 每日向服务器注册/同步设备信息，返回服务器端最新累计余额
    ///
    /// POST /sync
    /// { deviceID, solAddress, utcDate, completedHours, localBalance }
    struct DeviceSync: Encodable {
        let deviceID: String
        let solAddress: String
        let utcDate: String      // "2026-05-09"
        let completedHours: Int  // 当日已完成小时数
        let localBalance: Double // 本地缓存的余额（供服务器校验）
    }

    struct SyncResponse: Decodable {
        let success: Bool
        let tokenBalance: Double    // 服务器权威余额
        let activeDevices: Int?     // 全网近30天活跃设备数
        let airdropUnlocked: Bool?  // 是否已达5万台，开启空投
        let message: String?
    }

    func syncDevice(_ sync: DeviceSync) async throws -> SyncResponse {
        guard let url = URL(string: "\(baseURL)/sync") else {
            throw URLError(.badURL)
        }

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        // canonical 不含 localBalance（Double 序列化跨语言不一致；不影响安全性）
        let canonical = "\(sync.deviceID)|\(sync.solAddress)|\(sync.utcDate)|\(sync.completedHours)|\(timestamp)"
        let signature = try DeviceAttestation.shared.sign(canonical)

        let payload: [String: Any] = [
            "deviceID":       sync.deviceID,
            "solAddress":     sync.solAddress,
            "utcDate":        sync.utcDate,
            "completedHours": sync.completedHours,
            "localBalance":   sync.localBalance,
            "timestamp":      timestamp,
            "signature":      signature,
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(SyncResponse.self, from: data)
        guard decoded.success else { throw URLError(.badServerResponse) }
        return decoded
    }

    // MARK: - Network Stats

    /// 全网实时统计 — 用于 Mining 标签页顶部展示
    struct NetworkStats: Decodable {
        let activeDevices:    Int
        let totalDistributed: Double
        let totalLocked:      Double
        let todayRewards:     Double
        let asOf:             String
    }

    /// 调用 /stats 拉取全网统计（公开接口，无需鉴权）
    func fetchStats() async -> NetworkStats? {
        guard let url = URL(string: "\(baseURL)/stats") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(NetworkStats.self, from: data)
        } catch {
            return nil
        }
    }
}
