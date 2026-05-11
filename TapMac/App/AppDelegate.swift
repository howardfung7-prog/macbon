import Cocoa
import SwiftUI
import Combine

/// MacBon 妙控机身 — AppDelegate
/// 管理菜单栏图标、全局状态和核心模块生命周期
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?

    private let accelerometerReader = AccelerometerReader()
    private let tapDetector = TapDetector()
    private let actionManager = ActionManager()
    private let settings = AppSettings.shared

    private var cancellables = Set<AnyCancellable>()

    /// 屏幕是否处于非活跃状态（关闭/休眠/屏保），此时应忽略拍击
    private var isScreenInactive = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 MacBon 正在启动...")

        // ── 单实例保护：检测是否已有另一个 MacBon 进程在运行 ──
        let bundleID = Bundle.main.bundleIdentifier ?? "tech.macbon.app"
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if running.count > 1 {
            // 已有实例在运行，激活旧实例并退出自身
            running.first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })?
                   .activate(options: .activateIgnoringOtherApps)
            NSApp.terminate(nil)
            return
        }

        // 同步开机自启状态
        settings.syncLaunchAtLoginStatus()

        // 创建自定义音频文件夹
        setupAudioFolder()

        // 设置菜单栏
        setupMenuBar()

        // 监听屏幕/休眠状态
        registerScreenNotifications()

        // 连接模块：加速度计 → 拍击检测 → 动作执行
        setupPipeline()

        // 启动加速度计监听
        do {
            try accelerometerReader.start()
            print("✅ MacBon 已启动 — 加速度计连接成功")
        } catch {
            print("❌ 加速度计启动失败: \(error.localizedDescription)")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "加速度计启动失败"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        accelerometerReader.stop()
        print("👋 MacBon 已退出")
    }

    // MARK: - 菜单栏设置

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = createMenuBarIcon()
            updateMenuBarTitle()
        }

        // 构建下拉菜单
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "MacBon", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        // 显示当前动作绑定（tag 101/102/103 用于实时更新）
        let tapLabels = [
            NSLocalizedString("menu.tap1", comment: ""),
            NSLocalizedString("menu.tap2", comment: ""),
            NSLocalizedString("menu.tap3", comment: "")
        ]
        let tapActions = [settings.singleTapAction, settings.doubleTapAction, settings.tripleTapAction]
        let tapTags = [101, 102, 103]
        for (index, (label, action)) in zip(tapLabels, tapActions).enumerated() {
            let item = NSMenuItem(title: "\(label) → \(action.name)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.tag = tapTags[index]
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let countTitle = String(format: NSLocalizedString("menu.totalTaps", comment: ""), settings.totalTapCount)
        let countItem = NSMenuItem(title: countTitle, action: nil, keyEquivalent: "")
        countItem.isEnabled = false
        countItem.tag = 100
        menu.addItem(countItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: NSLocalizedString("menu.settings", comment: ""),
            action: #selector(openSettings), keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: NSLocalizedString("menu.quit", comment: ""),
            action: #selector(quitApp), keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        print("📌 菜单栏图标已创建")
    }

    /// 创建菜单栏图标：笔记本电脑 + 两侧震动小点
    private func createMenuBarIcon() -> NSImage {
        let size = NSSize(width: 22, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            // 笔记本图标居中绘制
            if let laptop = NSImage(systemSymbolName: "laptopcomputer",
                                     accessibilityDescription: "MacBon") {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                let configured = laptop.withSymbolConfiguration(config) ?? laptop
                let laptopSize = NSSize(width: 16, height: 12)
                let laptopOrigin = NSPoint(
                    x: (rect.width - laptopSize.width) / 2,
                    y: (rect.height - laptopSize.height) / 2
                )
                configured.draw(in: NSRect(origin: laptopOrigin, size: laptopSize))
            }

            // 左侧震动竖线
            let lineColor = NSColor.labelColor
            lineColor.withAlphaComponent(0.7).setStroke()
            let left1 = NSBezierPath()
            left1.move(to: NSPoint(x: 2, y: 4))
            left1.line(to: NSPoint(x: 2, y: 12))
            left1.lineWidth = 1.2
            left1.lineCapStyle = .round
            left1.stroke()

            lineColor.withAlphaComponent(0.4).setStroke()
            let left2 = NSBezierPath()
            left2.move(to: NSPoint(x: 0, y: 6))
            left2.line(to: NSPoint(x: 0, y: 10))
            left2.lineWidth = 1.0
            left2.lineCapStyle = .round
            left2.stroke()

            // 右侧震动竖线
            lineColor.withAlphaComponent(0.7).setStroke()
            let right1 = NSBezierPath()
            right1.move(to: NSPoint(x: 20, y: 4))
            right1.line(to: NSPoint(x: 20, y: 12))
            right1.lineWidth = 1.2
            right1.lineCapStyle = .round
            right1.stroke()

            lineColor.withAlphaComponent(0.4).setStroke()
            let right2 = NSBezierPath()
            right2.move(to: NSPoint(x: 22, y: 6))
            right2.line(to: NSPoint(x: 22, y: 10))
            right2.lineWidth = 1.0
            right2.lineCapStyle = .round
            right2.stroke()

            return true
        }
        image.isTemplate = true  // 自动适配深色/浅色菜单栏
        return image
    }

    private func updateMenuTapItems(single: ActionType, double: ActionType, triple: ActionType) {
        guard let menu = statusItem?.menu else { return }
        let labels = [
            NSLocalizedString("menu.tap1", comment: ""),
            NSLocalizedString("menu.tap2", comment: ""),
            NSLocalizedString("menu.tap3", comment: "")
        ]
        let actions = [single, double, triple]
        let tags = [101, 102, 103]
        for (index, tag) in tags.enumerated() {
            if let item = menu.item(withTag: tag) {
                item.title = "\(labels[index]) → \(actions[index].name)"
            }
        }
    }

    private func updateMenuBarTitle() {
        guard let button = statusItem?.button else { return }
        if settings.showTapCount {
            button.title = " \(settings.totalTapCount)"
        } else {
            button.title = ""
        }
    }

    // MARK: - 核心管线

    private func setupPipeline() {
        // 灵敏度 → AccelerometerReader 的 tapThreshold
        // sensitivity 0.0（最不灵敏）→ 阈值 0.50g（需要重拍）
        // sensitivity 0.5（中等）    → 阈值 0.35g
        // sensitivity 1.0（最灵敏）  → 阈值 0.20g（轻拍即触发）
        settings.$sensitivity
            .sink { [weak self] value in
                let threshold = 0.50 - (value * 0.30)
                self?.accelerometerReader.tapThreshold = threshold
                NSLog("[MacBon] 灵敏度=%.0f%% → 阈值=%.2fg", value * 100, threshold)
            }
            .store(in: &cancellables)

        settings.$cooldown
            .sink { [weak self] value in
                self?.tapDetector.cooldown = value
            }
            .store(in: &cancellables)

        // 动作绑定变更时实时更新菜单
        Publishers.CombineLatest3(
            settings.$singleTapAction,
            settings.$doubleTapAction,
            settings.$tripleTapAction
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] single, double, triple in
            self?.updateMenuTapItems(single: single, double: double, triple: triple)
        }
        .store(in: &cancellables)

        settings.$tapGap
            .sink { [weak self] value in
                self?.tapDetector.tapGap = value
            }
            .store(in: &cancellables)

        // 加速度计尖峰 → 拍击检测器
        accelerometerReader.spikePublisher
            .sink { [weak self] spike in
                self?.tapDetector.receivedSpike(magnitude: spike.magnitude, timestamp: spike.timestamp)
            }
            .store(in: &cancellables)

        // 拍击事件 → 执行动作
        tapDetector.tapEventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleTapEvent(event)
            }
            .store(in: &cancellables)

        print("🔗 管线已连接: 加速度计 → 拍击检测 → 动作执行")
    }

    /// 处理拍击事件
    private func handleTapEvent(_ event: TapEvent) {
        // 屏幕关闭/休眠/屏保期间不执行任何动作
        guard !isScreenInactive else {
            NSLog("[MacBon] 屏幕非活跃状态，忽略拍击")
            return
        }

        settings.totalTapCount += event.tapCount
        MiningTracker.shared.recordTap()
        updateMenuBarTitle()

        // 更新菜单中的计数显示
        if let menu = statusItem.menu,
           let countItem = menu.item(withTag: 100) {
            countItem.title = String(format: NSLocalizedString("menu.totalTaps", comment: ""), settings.totalTapCount)
        }

        let actionType = settings.action(for: event.tapCount)
        print("🖐 检测到 \(event.tapCount) 次拍击 (力度: \(String(format: "%.2f", event.intensity))) → 执行: \(actionType.name)")

        // 设置音量
        if settings.dynamicVolume {
            actionManager.volume = Float(event.intensity * settings.volume)
        } else {
            actionManager.volume = Float(settings.volume)
        }

        actionManager.execute(action: actionType)
    }

    // MARK: - 音频文件夹

    private func setupAudioFolder() {
        let url = settings.customAudioFolderURL
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            print("📁 已创建音频文件夹: \(url.path)")
        }
    }

    // MARK: - 菜单动作

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
            .environmentObject(settings)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("menu.settings", comment: "")
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false

        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 屏幕状态监听

    /// 注册系统通知：显示器开关、休眠/唤醒、屏保启停
    private func registerScreenNotifications() {
        let ws = NSWorkspace.shared.notificationCenter
        let dc = DistributedNotificationCenter.default()

        // 1. 显示器关闭/打开
        ws.addObserver(self, selector: #selector(screenDidSleep),
                       name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(screenDidWake),
                       name: NSWorkspace.screensDidWakeNotification, object: nil)

        // 2. 系统休眠/唤醒
        ws.addObserver(self, selector: #selector(systemWillSleep),
                       name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(systemDidWake),
                       name: NSWorkspace.didWakeNotification, object: nil)

        // 3. 屏保启动/停止
        dc.addObserver(self, selector: #selector(screenSaverDidStart),
                       name: NSNotification.Name("com.apple.screensaver.didstart"), object: nil)
        dc.addObserver(self, selector: #selector(screenSaverDidStop),
                       name: NSNotification.Name("com.apple.screensaver.didstop"), object: nil)

        NSLog("[MacBon] 屏幕状态监听已注册")
    }

    @objc private func screenDidSleep() {
        isScreenInactive = true
        tapDetector.reset()
        NSLog("[MacBon] 显示器已关闭 — 暂停响应拍击")
    }

    @objc private func screenDidWake() {
        isScreenInactive = false
        NSLog("[MacBon] 显示器已唤醒 — 恢复响应拍击")
    }

    @objc private func systemWillSleep() {
        isScreenInactive = true
        tapDetector.reset()
        NSLog("[MacBon] 系统即将休眠 — 暂停响应拍击")
    }

    @objc private func systemDidWake() {
        // 系统唤醒后延迟 1 秒再恢复，避免开盖动作触发误拍
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.isScreenInactive = false
            NSLog("[MacBon] 系统已唤醒 — 恢复响应拍击")
        }
    }

    @objc private func screenSaverDidStart() {
        isScreenInactive = true
        tapDetector.reset()
        NSLog("[MacBon] 屏保已启动 — 暂停响应拍击")
    }

    @objc private func screenSaverDidStop() {
        isScreenInactive = false
        NSLog("[MacBon] 屏保已停止 — 恢复响应拍击")
    }

    @objc private func quitApp() {
        accelerometerReader.stop()
        NSApp.terminate(nil)
    }
}
