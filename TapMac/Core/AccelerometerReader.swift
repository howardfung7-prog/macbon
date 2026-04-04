import Foundation
import IOKit
import IOKit.hid
import Combine

// MARK: - 加速度计数据模型

/// 三轴加速度数据结构
struct AccelerationData {
    let x: Double
    let y: Double
    let z: Double
    let timestamp: TimeInterval

    /// 计算加速度的总幅度（含重力）
    var magnitude: Double {
        sqrt(x * x + y * y + z * z)
    }
}

/// 加速度尖峰事件：当检测到加速度突变超过阈值时触发
struct AccelerationSpike {
    let acceleration: AccelerationData
    let deltaMagnitude: Double
    let magnitude: Double
    let timestamp: TimeInterval
}

// MARK: - 加速度计读取器

/// AccelerometerReader —— MacBon 的核心模块
///
/// 通过 IOKit 访问 Apple Silicon MacBook 内置的 SPU（Sensor Processing Unit）加速度计。
/// 传感器芯片为 Bosch BMI286，数据以 22 字节原始 HID 报告传输，采样率约 800Hz。
///
/// 关键技术点：
/// 1. 通过 IOServiceMatching("AppleSPUHIDDevice") 查找传感器
/// 2. 加速度计: UsagePage=0xFF00, Usage=3
/// 3. 必须先唤醒 AppleSPUHIDDriver（设置 ReportingState 和 PowerState）
/// 4. 使用 IOHIDDeviceRegisterInputReportWithTimeStampCallback 接收原始报告
/// 5. 报告为 22 字节，XYZ 数据从偏移 6 开始，每轴 4 字节 Int32 LE，除以 65536 得到 g 值
final class AccelerometerReader {

    // MARK: - 常量

    /// SPU 设备的 IOKit 服务类名
    private static let spuDeviceClassName = "AppleSPUHIDDevice"

    /// SPU 驱动的 IOKit 服务类名（需要唤醒）
    private static let spuDriverClassName = "AppleSPUHIDDriver"

    /// Apple 厂商特定 Usage Page
    private static let vendorUsagePage: Int = 0xFF00

    /// 加速度计的 Usage（在 SPU 设备中为 3）
    private static let accelerometerUsage: Int = 3

    /// IMU 报告长度（字节）
    private static let reportLength: Int = 22

    /// XYZ 数据在报告中的起始偏移
    private static let dataOffset: Int = 6

    /// Q16.16 定点数转换因子
    private static let scaleFactor: Double = 65536.0

    /// 重力加速度基准值
    private static let gravityBaseline: Double = 1.0

    // MARK: - 配置属性

    /// 敲击检测的加速度变化阈值（单位：g）
    var tapThreshold: Double = 0.35

    /// 两次敲击之间的最小间隔（秒）
    /// 窗口清空后需 ~50ms 重新填充提供自然防抖，0.12s 允许快速连拍
    var minimumTapInterval: TimeInterval = 0.12

    // MARK: - Combine 发布者

    /// 发布原始加速度数据流
    let accelerationPublisher = PassthroughSubject<AccelerationData, Never>()

    /// 发布加速度尖峰事件
    let spikePublisher = PassthroughSubject<AccelerationSpike, Never>()

    // MARK: - 私有属性

    /// 匹配到的加速度计 HID 设备
    private var hidDevice: IOHIDDevice?

    /// 原始报告缓冲区
    private var reportBuffer: UnsafeMutablePointer<UInt8>?

    /// 当前是否正在读取
    private(set) var isRunning = false

    /// 滑动窗口：存储最近 N 个采样的幅度值
    private var magnitudeWindow: [Double] = []
    private static let windowSize: Int = 40  // 约 50ms 的窗口（800Hz × 0.05s）
    private var debugRangeCounter: UInt64 = 0

    /// 上一次检测到敲击的时间戳
    private var lastTapTimestamp: TimeInterval = 0

    /// 用于回调的上下文指针
    private var callbackContext: UnsafeMutableRawPointer?

    /// 累计采样数
    private var sampleCount: UInt64 = 0

    /// 唤醒的驱动服务引用（需要在停止时恢复）
    private var driverServices: [io_object_t] = []

    // MARK: - 初始化与销毁

    init() {}

    deinit {
        stop()
    }

    // MARK: - 公开方法

    /// 启动加速度计读取
    func start() throws {
        guard !isRunning else {
            NSLog("[AccelerometerReader] 已在运行中")
            return
        }

        NSLog("[AccelerometerReader] 正在初始化 SPU 加速度计...")

        // 第一步：唤醒 SPU 驱动
        wakeSPUDrivers()

        // 第二步：查找加速度计 SPU 设备
        guard let device = findAccelerometerDevice() else {
            throw AccelerometerError.deviceNotFound
        }

        // 第三步：打开设备
        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            NSLog("[AccelerometerReader] 设备打开失败: %d", openResult)
            throw AccelerometerError.failedToOpen(ioReturn: openResult)
        }
        NSLog("[AccelerometerReader] 设备打开成功")

        // 第四步：分配报告缓冲区
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: AccelerometerReader.reportLength)
        buffer.initialize(repeating: 0, count: AccelerometerReader.reportLength)
        reportBuffer = buffer

        // 第五步：注册原始报告回调
        callbackContext = Unmanaged.passUnretained(self).toOpaque()

        IOHIDDeviceRegisterInputReportWithTimeStampCallback(
            device,
            buffer,
            AccelerometerReader.reportLength,
            spuReportCallback,
            callbackContext
        )

        // 第六步：调度到主 RunLoop
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        hidDevice = device
        isRunning = true
        sampleCount = 0
        magnitudeWindow.removeAll()

        NSLog("[AccelerometerReader] ✅ 加速度计已启动，敲击阈值: %.2fg", tapThreshold)
    }

    /// 停止加速度计
    func stop() {
        guard isRunning else { return }

        NSLog("[AccelerometerReader] 正在停止... (共采集 %llu 个样本)", sampleCount)

        if let device = hidDevice {
            IOHIDDeviceRegisterInputReportWithTimeStampCallback(device, reportBuffer!, AccelerometerReader.reportLength, nil, nil)
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        // 释放缓冲区
        reportBuffer?.deallocate()
        reportBuffer = nil

        // 休眠 SPU 驱动（省电）
        sleepSPUDrivers()

        hidDevice = nil
        callbackContext = nil
        isRunning = false

        NSLog("[AccelerometerReader] 加速度计已停止")
    }

    // MARK: - SPU 驱动管理

    /// 唤醒 SPU 驱动，让传感器开始报告数据
    private func wakeSPUDrivers() {
        var iterator: io_iterator_t = 0
        let matchDict = IOServiceMatching(AccelerometerReader.spuDriverClassName)

        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator)
        guard result == KERN_SUCCESS else {
            NSLog("[AccelerometerReader] 未找到 SPU 驱动服务")
            return
        }

        var service = IOIteratorNext(iterator)
        var count = 0

        while service != 0 {
            // 设置传感器报告状态为活跃
            IORegistryEntrySetCFProperty(service, "SensorPropertyReportingState" as CFString, 1 as CFNumber)
            IORegistryEntrySetCFProperty(service, "SensorPropertyPowerState" as CFString, 1 as CFNumber)
            IORegistryEntrySetCFProperty(service, "ReportInterval" as CFString, 1000 as CFNumber)

            driverServices.append(service)
            count += 1
            service = IOIteratorNext(iterator)
        }

        IOObjectRelease(iterator)
        NSLog("[AccelerometerReader] 已唤醒 %d 个 SPU 驱动", count)
    }

    /// 休眠 SPU 驱动（省电）
    private func sleepSPUDrivers() {
        for service in driverServices {
            IORegistryEntrySetCFProperty(service, "SensorPropertyReportingState" as CFString, 0 as CFNumber)
            IORegistryEntrySetCFProperty(service, "SensorPropertyPowerState" as CFString, 0 as CFNumber)
            IOObjectRelease(service)
        }
        driverServices.removeAll()
        NSLog("[AccelerometerReader] SPU 驱动已休眠")
    }

    // MARK: - 设备查找

    /// 通过 IOServiceMatching 查找加速度计 SPU 设备
    private func findAccelerometerDevice() -> IOHIDDevice? {
        var iterator: io_iterator_t = 0
        let matchDict = IOServiceMatching(AccelerometerReader.spuDeviceClassName)

        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator)
        guard result == KERN_SUCCESS else {
            NSLog("[AccelerometerReader] 未找到 SPU 设备服务")
            return nil
        }

        var service = IOIteratorNext(iterator)
        var foundDevice: IOHIDDevice?

        while service != 0 {
            // 读取设备属性
            let usagePageRef = IORegistryEntryCreateCFProperty(service, "PrimaryUsagePage" as CFString, kCFAllocatorDefault, 0)
            let usageRef = IORegistryEntryCreateCFProperty(service, "PrimaryUsage" as CFString, kCFAllocatorDefault, 0)

            let usagePage = (usagePageRef?.takeRetainedValue() as? Int) ?? 0
            let usage = (usageRef?.takeRetainedValue() as? Int) ?? 0

            NSLog("[AccelerometerReader] SPU 设备: UsagePage=0x%04X Usage=%d", usagePage, usage)

            if usagePage == AccelerometerReader.vendorUsagePage &&
               usage == AccelerometerReader.accelerometerUsage {
                NSLog("[AccelerometerReader] ✅ 找到加速度计！(UsagePage=0x%04X, Usage=%d)", usagePage, usage)

                // 从 IOService 创建 IOHIDDevice
                if let deviceRef = IOHIDDeviceCreate(kCFAllocatorDefault, service) {
                    foundDevice = deviceRef
                } else {
                    NSLog("[AccelerometerReader] ❌ IOHIDDeviceCreate 失败")
                }

                IOObjectRelease(service)
                break
            }

            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        IOObjectRelease(iterator)

        if foundDevice == nil {
            NSLog("[AccelerometerReader] ❌ 未找到加速度计 SPU 设备 (UsagePage=0xFF00, Usage=3)")
        }

        return foundDevice
    }

    // MARK: - 报告解析

    /// 解析 22 字节的 IMU 原始报告
    ///
    /// 报告格式：
    ///   字节 [0..5]:  报告头（ID、序号等）
    ///   字节 [6..9]:  X 轴加速度（Int32 LE, Q16.16 定点数）
    ///   字节 [10..13]: Y 轴加速度
    ///   字节 [14..17]: Z 轴加速度
    ///   字节 [18..21]: 保留/校验
    fileprivate func handleReport(_ report: UnsafeMutablePointer<UInt8>, length: Int, timestamp: UInt64) {
        guard length >= AccelerometerReader.reportLength else { return }

        let offset = AccelerometerReader.dataOffset

        // 读取 Int32 LE 并转换为 Double（Q16.16 定点数 → g）
        let rawX = readInt32LE(report, offset: offset)
        let rawY = readInt32LE(report, offset: offset + 4)
        let rawZ = readInt32LE(report, offset: offset + 8)

        let x = Double(rawX) / AccelerometerReader.scaleFactor
        let y = Double(rawY) / AccelerometerReader.scaleFactor
        let z = Double(rawZ) / AccelerometerReader.scaleFactor

        let now = ProcessInfo.processInfo.systemUptime
        let data = AccelerationData(x: x, y: y, z: z, timestamp: now)

        sampleCount += 1

        // 每 800 个样本（约 1 秒）输出一次调试信息
        if sampleCount % 800 == 1 {
            NSLog("[AccelerometerReader] 采样 #%llu: x=%.4f y=%.4f z=%.4f mag=%.4f",
                  sampleCount, data.x, data.y, data.z, data.magnitude)
        }

        accelerationPublisher.send(data)
        detectTap(data)
    }

    /// 从缓冲区读取 Int32 Little-Endian
    private func readInt32LE(_ buffer: UnsafeMutablePointer<UInt8>, offset: Int) -> Int32 {
        let b0 = Int32(buffer[offset])
        let b1 = Int32(buffer[offset + 1]) << 8
        let b2 = Int32(buffer[offset + 2]) << 16
        let b3 = Int32(buffer[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }

    // MARK: - 敲击检测

    /// 敲击检测算法（极差版）
    ///
    /// 用窗口内的 max - min（极差）来判断是否发生拍击。
    /// 静止时极差很小（<0.01），拍击时极差会显著增大。
    /// 同时监控每个轴的变化，避免幅度相互抵消。
    private func detectTap(_ data: AccelerationData) {
        let currentMagnitude = data.magnitude

        // 更新滑动窗口
        magnitudeWindow.append(currentMagnitude)
        if magnitudeWindow.count > AccelerometerReader.windowSize {
            magnitudeWindow.removeFirst()
        }

        // 窗口未满时不检测
        guard magnitudeWindow.count == AccelerometerReader.windowSize else { return }

        // 计算窗口内的极差（最大值 - 最小值）
        let windowMax = magnitudeWindow.max() ?? 0
        let windowMin = magnitudeWindow.min() ?? 0
        let range = windowMax - windowMin

        // 每秒记录一次当前极差（用于调试校准）
        sampleCount += 0 // sampleCount already updated in handleReport
        if magnitudeWindow.count == AccelerometerReader.windowSize {
            debugRangeCounter += 1
            if debugRangeCounter % 200 == 0 {
                NSLog("[AccelerometerReader] 📊 当前极差=%.4f (阈值=%.2f) 静止时请记录此值", range, tapThreshold)
            }
        }

        // 只在极差显著时记录
        if range > 0.03 {
            NSLog("[AccelerometerReader] 极差=%.4f (阈值=%.2f) mag=%.4f", range, tapThreshold, currentMagnitude)
        }

        guard range > tapThreshold else { return }

        let now = data.timestamp
        guard (now - lastTapTimestamp) > minimumTapInterval else { return }
        lastTapTimestamp = now

        // 触发后清空窗口
        magnitudeWindow.removeAll()

        let spike = AccelerationSpike(
            acceleration: data,
            deltaMagnitude: range,
            magnitude: range,
            timestamp: now
        )

        NSLog("[AccelerometerReader] 🖐 检测到敲击！极差=%.4fg 坐标=(%.2f, %.2f, %.2f)",
              range, data.x, data.y, data.z)

        spikePublisher.send(spike)
    }
}

// MARK: - SPU 原始报告回调（C 函数指针）

/// IOKit HID 原始报告回调
///
/// Apple Silicon 的 SPU 加速度计以 22 字节原始报告传输数据，
/// 必须使用此类回调（而非 InputValueCallback）。
private func spuReportCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex,
    timeStamp: UInt64
) {
    guard result == kIOReturnSuccess else { return }
    guard let context = context else { return }

    let reader = Unmanaged<AccelerometerReader>.fromOpaque(context).takeUnretainedValue()
    reader.handleReport(report, length: reportLength, timestamp: timeStamp)
}

// MARK: - 错误类型

enum AccelerometerError: LocalizedError {
    case deviceNotFound
    case failedToOpen(ioReturn: IOReturn)
    case deviceDisconnected

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "未找到加速度计设备。请确认此 Mac 配备 Apple Silicon 芯片（M1 Pro 及以上）且为笔记本机型。"
        case .failedToOpen(let ioReturn):
            return "无法打开加速度计连接 (IOReturn: \(ioReturn))。请检查系统权限设置。"
        case .deviceDisconnected:
            return "加速度计设备意外断开连接。"
        }
    }
}
