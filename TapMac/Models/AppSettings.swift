import Foundation
import Combine
import ServiceManagement

/// 应用设置管理器 — 使用 UserDefaults 持久化所有用户偏好
/// 单例模式，全局通过 `AppSettings.shared` 访问
class AppSettings: ObservableObject, @unchecked Sendable {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: - Keys
    private enum Keys {
        static let singleTapAction = "singleTapAction"
        static let doubleTapAction = "doubleTapAction"
        static let tripleTapAction = "tripleTapAction"
        static let sensitivity     = "sensitivity"
        static let cooldown        = "cooldown"
        static let tapGap          = "tapGap"
        static let volume          = "volume"
        static let dynamicVolume   = "dynamicVolume"
        static let showTapCount    = "showTapCount"
        static let launchAtLogin   = "launchAtLogin"
        static let totalTapCount   = "totalTapCount"
    }

    // MARK: - 默认值
    private enum Defaults {
        static let singleTapAction: ActionType = .muteToggle
        static let doubleTapAction: ActionType = .lockScreen
        static let tripleTapAction: ActionType = .quickMemo
        static let sensitivity: Double     = 0.5
        static let cooldown: Double        = 0.8
        static let tapGap: Double          = 0.8
        static let volume: Double          = 0.8
        static let dynamicVolume: Bool     = false
        static let showTapCount: Bool      = true
        static let launchAtLogin: Bool     = false
        static let totalTapCount: Int      = 0
    }

    // ── 动作绑定 ──

    @Published var singleTapAction: ActionType {
        didSet { defaults.set(singleTapAction.rawValue, forKey: Keys.singleTapAction) }
    }

    @Published var doubleTapAction: ActionType {
        didSet { defaults.set(doubleTapAction.rawValue, forKey: Keys.doubleTapAction) }
    }

    @Published var tripleTapAction: ActionType {
        didSet { defaults.set(tripleTapAction.rawValue, forKey: Keys.tripleTapAction) }
    }

    // ── 检测参数 ──

    @Published var sensitivity: Double {
        didSet { defaults.set(sensitivity, forKey: Keys.sensitivity) }
    }

    @Published var cooldown: Double {
        didSet { defaults.set(cooldown, forKey: Keys.cooldown) }
    }

    @Published var tapGap: Double {
        didSet { defaults.set(tapGap, forKey: Keys.tapGap) }
    }

    // ── 音频 ──

    @Published var volume: Double {
        didSet { defaults.set(volume, forKey: Keys.volume) }
    }

    @Published var dynamicVolume: Bool {
        didSet { defaults.set(dynamicVolume, forKey: Keys.dynamicVolume) }
    }

    // ── 界面 ──

    @Published var showTapCount: Bool {
        didSet { defaults.set(showTapCount, forKey: Keys.showTapCount) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    // ── 统计 ──

    @Published var totalTapCount: Int {
        didSet { defaults.set(totalTapCount, forKey: Keys.totalTapCount) }
    }

    // ── 自定义音频文件夹 ──

    var customAudioFolderURL: URL {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("MacBon")
            .appendingPathComponent("Sounds")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - 初始化

    private init() {
        if let raw = defaults.string(forKey: Keys.singleTapAction),
           let action = ActionType(rawValue: raw) {
            self.singleTapAction = action
        } else {
            self.singleTapAction = Defaults.singleTapAction
        }

        if let raw = defaults.string(forKey: Keys.doubleTapAction),
           let action = ActionType(rawValue: raw) {
            self.doubleTapAction = action
        } else {
            self.doubleTapAction = Defaults.doubleTapAction
        }

        if let raw = defaults.string(forKey: Keys.tripleTapAction),
           let action = ActionType(rawValue: raw) {
            self.tripleTapAction = action
        } else {
            self.tripleTapAction = Defaults.tripleTapAction
        }

        self.sensitivity = defaults.object(forKey: Keys.sensitivity) != nil
            ? defaults.double(forKey: Keys.sensitivity) : Defaults.sensitivity

        self.cooldown = defaults.object(forKey: Keys.cooldown) != nil
            ? defaults.double(forKey: Keys.cooldown) : Defaults.cooldown

        self.tapGap = defaults.object(forKey: Keys.tapGap) != nil
            ? defaults.double(forKey: Keys.tapGap) : Defaults.tapGap

        self.volume = defaults.object(forKey: Keys.volume) != nil
            ? defaults.double(forKey: Keys.volume) : Defaults.volume

        self.dynamicVolume = defaults.object(forKey: Keys.dynamicVolume) != nil
            ? defaults.bool(forKey: Keys.dynamicVolume) : Defaults.dynamicVolume

        self.showTapCount = defaults.object(forKey: Keys.showTapCount) != nil
            ? defaults.bool(forKey: Keys.showTapCount) : Defaults.showTapCount

        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) != nil
            ? defaults.bool(forKey: Keys.launchAtLogin) : Defaults.launchAtLogin

        self.totalTapCount = defaults.integer(forKey: Keys.totalTapCount)
    }

    // MARK: - 公共方法

    func action(for tapCount: Int) -> ActionType {
        switch tapCount {
        case 1:  return singleTapAction
        case 2:  return doubleTapAction
        case 3:  return tripleTapAction
        default: return singleTapAction
        }
    }

    func resetToDefaults() {
        singleTapAction = Defaults.singleTapAction
        doubleTapAction = Defaults.doubleTapAction
        tripleTapAction = Defaults.tripleTapAction
        sensitivity     = Defaults.sensitivity
        cooldown        = Defaults.cooldown
        tapGap          = Defaults.tapGap
        volume          = Defaults.volume
        dynamicVolume   = Defaults.dynamicVolume
        showTapCount    = Defaults.showTapCount
        launchAtLogin   = Defaults.launchAtLogin
        totalTapCount   = Defaults.totalTapCount
    }

    // MARK: - Launch at Login

    private func applyLaunchAtLogin(_ enable: Bool) {
        let service = SMAppService.mainApp
        do {
            if enable {
                if service.status != .enabled {
                    try service.register()
                    print("[MacBon] Launch at login enabled")
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                    print("[MacBon] Launch at login disabled")
                }
            }
        } catch {
            print("[MacBon] Launch at login error: \(error.localizedDescription)")
        }
    }

    /// 启动时同步实际注册状态到 UI
    func syncLaunchAtLoginStatus() {
        let registered = SMAppService.mainApp.status == .enabled
        if launchAtLogin != registered {
            launchAtLogin = registered
        }
    }
}
