import Cocoa
import SwiftUI
import Combine

// MARK: - 应用入口
// 使用传统 main.swift 方式启动，确保菜单栏应用正常工作

// 单实例保护：如果已有 MacBon 在运行，激活已有实例并退出当前进程
let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
if runningApps.count > 1 {
    // 激活已在运行的实例
    runningApps.first { $0 != NSRunningApplication.current }?.activate()
    NSLog("[MacBon] 已有实例在运行，退出当前进程")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
