import Foundation
import Combine
import IOKit

/// 每日挖矿进度追踪器
///
/// 规则：
/// - UTC 00:00 重置；24 小时内任意 6 个自然小时均可获得奖励
/// - 当前小时内至少拍击 1 次即为"完成"；达到 6 小时后当日封顶
/// - SOL 地址绑定后，每小时结束时自动向服务器上传数据
class MiningTracker: ObservableObject {
    static let shared = MiningTracker()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let hourTaps        = "mining.hourTaps"       // [Int] 24元素
        static let dayKey          = "mining.dayKey"
        static let solAddress      = "mining.solAddress"
        static let deviceID        = "mining.deviceID"
        static let uploadStatus    = "mining.uploadStatus"   // [String: String]
        static let tokenBalance    = "mining.tokenBalance"
        static let lastSyncDay     = "mining.lastSyncDay"    // 上次每日同步的日期
        static let activeDevices   = "mining.activeDevices"  // 全网活跃设备数
        static let airdropUnlocked = "mining.airdropUnlocked"
        static let hasUsedModify   = "mining.hasUsedModify"  // 是否已用过一次修改机会
        static let attested        = "mining.attested"       // 公钥已成功注册到服务器
    }

    static let maxRewardedHours = 6
    static let minimumTaps      = 1

    // MARK: - Enums

    enum ConnectionStatus { case checking, connected, disconnected }

    enum UploadStatus: String {
        case uploading, uploaded, failed
    }

    // MARK: - Published State

    @Published private(set) var hourTaps: [Int]        = Array(repeating: 0, count: 24)
    @Published private(set) var solAddress: String     = ""
    @Published private(set) var connectionStatus: ConnectionStatus = .checking
    @Published private(set) var uploadStatus: [Int: UploadStatus] = [:]  // UTC hour → status
    @Published private(set) var tokenBalance: Double   = 0
    @Published private(set) var activeDevices: Int     = 0     // 全网活跃设备数
    @Published private(set) var airdropUnlocked: Bool  = false // 是否开启空投
    @Published private(set) var hasUsedModify: Bool    = false // 是否已用过一次修改机会

    // 全网实时统计（每 30 秒刷新）
    @Published private(set) var totalDistributed: Double = 0
    @Published private(set) var totalLocked: Double      = 0
    @Published private(set) var todayPool: Double        = 0

    let deviceID: String

    // MARK: - Private

    private var lastKnownHour: Int  = -1
    private var connCheckCounter    = 0

    // MARK: - Init

    private init() {
        self.deviceID        = Self.resolveDeviceID(defaults: UserDefaults.standard)
        self.solAddress      = defaults.string(forKey: Keys.solAddress) ?? ""
        self.tokenBalance    = defaults.double(forKey: Keys.tokenBalance)
        self.activeDevices   = defaults.integer(forKey: Keys.activeDevices)
        self.airdropUnlocked = defaults.bool(forKey: Keys.airdropUnlocked)
        self.hasUsedModify   = defaults.bool(forKey: Keys.hasUsedModify)
        loadOrReset()

        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.tick()
        }

        // 全网统计 — 每 30 秒拉一次
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { await self?.refreshNetworkStats() }
        }

        // 启动时：硬件证明 → 检查连接 → 每日同步 → 上传未完成小时 → 拉全网统计
        Task {
            await ensureAttested()
            await checkConnection()
            await dailySync()
            await uploadPendingHours()
            await refreshNetworkStats()
        }
    }

    // MARK: - Device Attestation

    /// 首次启动时把 Secure Enclave 公钥注册到服务器
    /// 已注册则跳过
    private func ensureAttested() async {
        if defaults.bool(forKey: Keys.attested) { return }

        guard DeviceAttestation.shared.isAvailable else {
            print("[Attest] ⚠️ Secure Enclave unavailable — running in VM or unsupported hardware?")
            return
        }
        do {
            _ = try DeviceAttestation.shared.ensureKey()
        } catch {
            print("[Attest] ❌ key generation failed: \(error)")
            return
        }
        let ok = await MiningAPIClient.shared.registerAttestation(deviceID: deviceID)
        if ok {
            defaults.set(true, forKey: Keys.attested)
            print("[Attest] ✅ device key registered with server")
        } else {
            print("[Attest] ⚠️ registration request failed; will retry next launch")
        }
    }

    // MARK: - Network Stats

    @MainActor
    private func refreshNetworkStats() async {
        guard let stats = await MiningAPIClient.shared.fetchStats() else { return }
        self.activeDevices    = stats.activeDevices
        self.totalDistributed = stats.totalDistributed
        self.totalLocked      = stats.totalLocked
        self.todayPool        = stats.todayRewards
        self.airdropUnlocked  = stats.activeDevices >= 50_000
        defaults.set(stats.activeDevices, forKey: Keys.activeDevices)
        defaults.set(self.airdropUnlocked, forKey: Keys.airdropUnlocked)
    }

    private func tick() {
        checkDayRollover()
        objectWillChange.send()

        let hour = currentUTCHour
        if lastKnownHour >= 0 && hour != lastKnownHour {
            // 整点切换：上传刚结束的那个小时
            let prev = lastKnownHour
            Task { await uploadHour(prev) }
        }
        lastKnownHour = hour

        connCheckCounter += 1
        if connCheckCounter % 5 == 0 {
            Task { await checkConnection() }
        }
    }

    // MARK: - Device ID

    private static func resolveDeviceID(defaults: UserDefaults) -> String {
        if let cached = defaults.string(forKey: Keys.deviceID) { return cached }
        let hwUUID = readHardwareUUID() ?? UUID().uuidString
        let clean  = hwUUID.replacingOccurrences(of: "-", with: "").uppercased()
        let id     = "MAC-" + String(clean.prefix(8))
        defaults.set(id, forKey: Keys.deviceID)
        return id
    }

    private static func readHardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        guard service != 0 else { return nil }
        let ref = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString,
                                                  kCFAllocatorDefault, 0)
        return ref?.takeRetainedValue() as? String
    }

    // MARK: - SOL Address

    /// 空投开启前可修改一次；空投开启后永久锁定
    var canModifyAddress: Bool {
        !solAddress.isEmpty && !hasUsedModify && !airdropUnlocked
    }

    func saveSolAddress(_ address: String) {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard isValidSolAddress(trimmed) else { return }

        if solAddress.isEmpty {
            // 首次绑定
            solAddress = trimmed
            defaults.set(trimmed, forKey: Keys.solAddress)
        } else if canModifyAddress {
            // 唯一一次修改机会
            solAddress    = trimmed
            hasUsedModify = true
            defaults.set(trimmed, forKey: Keys.solAddress)
            defaults.set(true,    forKey: Keys.hasUsedModify)
        } else {
            return
        }
        Task { await uploadPendingHours() }
    }

    func isValidSolAddress(_ address: String) -> Bool {
        let s = address.trimmingCharacters(in: .whitespaces)
        // Solana 钱包地址 = 32字节 Ed25519 公钥，Base58 编码后为 43-44 字符
        guard (43...44).contains(s.count) else { return false }
        let base58 = CharacterSet(charactersIn:
            "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        return s.unicodeScalars.allSatisfy { base58.contains($0) }
    }

    // MARK: - Day Key (UTC)

    private var todayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }

    // MARK: - Persistence

    private func loadOrReset() {
        let savedDay = defaults.string(forKey: Keys.dayKey) ?? ""
        if savedDay == todayKey,
           let taps = defaults.array(forKey: Keys.hourTaps) as? [Int], taps.count == 24 {
            hourTaps = taps
            uploadStatus = loadUploadStatus()
        } else {
            resetDay()
        }
    }

    private func resetDay() {
        hourTaps     = Array(repeating: 0, count: 24)
        uploadStatus = [:]
        defaults.set(todayKey,   forKey: Keys.dayKey)
        defaults.set(hourTaps,   forKey: Keys.hourTaps)
        defaults.removeObject(forKey: Keys.uploadStatus)
        // 新的一天：立即触发每日同步
        Task { await dailySync() }
    }

    func checkDayRollover() {
        if (defaults.string(forKey: Keys.dayKey) ?? "") != todayKey { resetDay() }
    }

    private func loadUploadStatus() -> [Int: UploadStatus] {
        guard let raw = defaults.dictionary(forKey: Keys.uploadStatus) as? [String: String]
        else { return [:] }
        var result: [Int: UploadStatus] = [:]
        for (k, v) in raw {
            if let hour = Int(k), let status = UploadStatus(rawValue: v) {
                result[hour] = status
            }
        }
        return result
    }

    private func saveUploadStatus() {
        var raw: [String: String] = [:]
        for (hour, status) in uploadStatus { raw[String(hour)] = status.rawValue }
        defaults.set(raw, forKey: Keys.uploadStatus)
    }

    // MARK: - Recording (main thread)

    func recordTap() {
        checkDayRollover()
        guard !isMaxedOut || !currentHourCompleted else { return }
        hourTaps[currentUTCHour] += 1
        defaults.set(hourTaps, forKey: Keys.hourTaps)
    }

    // MARK: - Network: Connectivity

    func checkConnection() async {
        await MainActor.run { connectionStatus = .checking }
        let ok = await MiningAPIClient.shared.ping()
        await MainActor.run { connectionStatus = ok ? .connected : .disconnected }
    }

    // MARK: - Network: Daily Sync

    /// 每天向服务器同步一次设备信息（设备ID + SOL地址 + 余额）
    /// 防止重复：同一 UTC 日期只发送一次
    func dailySync() async {
        guard !solAddress.isEmpty else { return }

        // 同一天已同步过则跳过
        let lastSync = defaults.string(forKey: Keys.lastSyncDay) ?? ""
        guard lastSync != todayKey else { return }

        let payload = MiningAPIClient.DeviceSync(
            deviceID:       deviceID,
            solAddress:     solAddress,
            utcDate:        todayKey,
            completedHours: completedHoursCount,
            localBalance:   tokenBalance
        )

        do {
            let resp = try await MiningAPIClient.shared.syncDevice(payload)
            await MainActor.run {
                tokenBalance    = resp.tokenBalance
                activeDevices   = resp.activeDevices  ?? activeDevices
                airdropUnlocked = resp.airdropUnlocked ?? airdropUnlocked
                defaults.set(resp.tokenBalance,            forKey: Keys.tokenBalance)
                defaults.set(resp.activeDevices ?? 0,      forKey: Keys.activeDevices)
                defaults.set(resp.airdropUnlocked ?? false, forKey: Keys.airdropUnlocked)
                defaults.set(todayKey,                     forKey: Keys.lastSyncDay)
                connectionStatus = .connected
            }
        } catch {
            // 同步失败不更新 lastSyncDay，下次启动会重试
            await MainActor.run { connectionStatus = .disconnected }
        }
    }

    // MARK: - Network: Upload

    func uploadHour(_ utcHour: Int) async {
        guard !solAddress.isEmpty else { return }
        guard hourTaps[utcHour] >= Self.minimumTaps else { return }
        guard uploadStatus[utcHour] != .uploaded else { return }
        guard uploadStatus[utcHour] != .uploading else { return }

        await MainActor.run { uploadStatus[utcHour] = .uploading }

        let report = MiningAPIClient.HourReport(
            deviceID:   deviceID,
            solAddress: solAddress,
            utcDate:    todayKey,
            utcHour:    utcHour,
            tapCount:   hourTaps[utcHour]
        )

        do {
            let balance = try await MiningAPIClient.shared.submitHour(report)
            print("[Upload] ✅ hour \(utcHour) → balance \(balance)")
            await MainActor.run {
                uploadStatus[utcHour] = .uploaded
                tokenBalance          = balance
                defaults.set(balance, forKey: Keys.tokenBalance)
                saveUploadStatus()
                connectionStatus = .connected
            }
        } catch {
            print("[Upload] ❌ hour \(utcHour) failed: \(error)")
            await MainActor.run {
                uploadStatus[utcHour] = .failed
                connectionStatus      = .disconnected
            }
        }
    }

    /// 上传今日所有已完成但尚未上传的小时
    func uploadPendingHours() async {
        for hour in 0..<24 where hourTaps[hour] >= Self.minimumTaps
                                  && uploadStatus[hour] != .uploaded {
            await uploadHour(hour)
        }
    }

    // MARK: - Computed Properties

    var currentUTCHour: Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.component(.hour, from: Date())
    }

    var currentHourTaps: Int    { hourTaps[currentUTCHour] }
    var currentHourCompleted: Bool { currentHourTaps >= Self.minimumTaps }

    var completedHoursCount: Int {
        min(hourTaps.filter { $0 >= Self.minimumTaps }.count, Self.maxRewardedHours)
    }

    var isMaxedOut: Bool { completedHoursCount >= Self.maxRewardedHours }

    /// 已完成的 UTC 小时列表（升序，最多 6 个）
    var completedUTCHours: [Int] {
        Array(
            hourTaps.enumerated()
                .filter { $0.element >= Self.minimumTaps }
                .map { $0.offset }
                .prefix(Self.maxRewardedHours)
        )
    }

    /// 第 index 盏灯对应的上传状态
    func uploadStatusForSlot(_ index: Int) -> UploadStatus? {
        let hours = completedUTCHours
        guard index < hours.count else { return nil }
        return uploadStatus[hours[index]]
    }

    var secondsToNextHour: TimeInterval {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let next = cal.nextDate(after: Date(),
                                matching: DateComponents(minute: 0, second: 0),
                                matchingPolicy: .nextTime)!
        return max(0, next.timeIntervalSinceNow)
    }

    // MARK: - Slot Status（6 盏灯）

    enum SlotStatus: Equatable { case completed, active, pending }

    func slotStatus(at index: Int) -> SlotStatus {
        if index < completedHoursCount { return .completed }
        if index == completedHoursCount && !isMaxedOut { return .active }
        return .pending
    }
}
