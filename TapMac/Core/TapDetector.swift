import Foundation
import Combine

// MARK: - 拍击事件模型

struct TapEvent {
    let tapCount: Int      // 拍击次数: 1, 2, 或 3
    let intensity: Double  // 拍击力度 0.0~1.0
    let timestamp: Date
}

// MARK: - 拍击检测引擎

/// 拍击检测器：接收加速度尖峰事件，识别单击/双击/三击模式
/// 通过时间窗口和冷却期机制区分不同拍击模式，过滤打字振动干扰
class TapDetector: ObservableObject, @unchecked Sendable {

    // MARK: - 可配置参数

    /// 灵敏度：0.0（最不灵敏）~ 1.0（最灵敏），影响触发阈值
    @Published var sensitivity: Double = 0.5

    /// 两次拍击之间允许的最大间隔（秒）
    /// 设为 0.8s，等用户确实停止拍击后再确认最终拍数
    @Published var tapGap: Double = 0.8

    /// 触发动作后的冷却时间（秒），防止误触发
    @Published var cooldown: Double = 0.8

    // MARK: - 事件发布

    /// 外部订阅此 subject 接收最终的拍击事件
    let tapEventPublisher = PassthroughSubject<TapEvent, Never>()

    // MARK: - 内部状态（由 serialQueue 保护线程安全）

    /// 串行队列，保证所有状态修改在同一队列上执行
    private let serialQueue = DispatchQueue(label: "com.macbon.tapdetector", qos: .userInteractive)

    /// 当前连续拍击的时间戳列表
    private var tapTimestamps: [TimeInterval] = []

    /// 当前连续拍击的峰值力度列表
    private var intensities: [Double] = []

    /// 上次触发动作的时间，用于冷却期判断
    private var lastTriggerTime: TimeInterval = 0

    /// 等待窗口到期的定时器；窗口到期后确定最终拍击次数
    private var pendingTimer: DispatchSourceTimer?

    // MARK: - 初始化

    init(sensitivity: Double = 0.5, tapGap: Double = 0.8, cooldown: Double = 0.8) {
        self.sensitivity = sensitivity
        self.tapGap = tapGap
        self.cooldown = cooldown
    }

    deinit {
        pendingTimer?.cancel()
    }

    // MARK: - 公开接口

    /// 接收加速度尖峰事件
    /// - Parameters:
    ///   - magnitude: 加速度幅值（原始值，由 AccelerometerReader 提供）
    ///   - timestamp: 事件时间戳（CACurrentMediaTime 或类似单调时钟）
    func receivedSpike(magnitude: Double, timestamp: TimeInterval) {
        serialQueue.async { [weak self] in
            self?.processSpike(magnitude: magnitude, timestamp: timestamp)
        }
    }

    /// 重置所有内部状态
    func reset() {
        serialQueue.async { [weak self] in
            guard let self else { return }
            self.pendingTimer?.cancel()
            self.pendingTimer = nil
            self.tapTimestamps.removeAll()
            self.intensities.removeAll()
            self.lastTriggerTime = 0
        }
    }

    // MARK: - 核心检测逻辑

    private func processSpike(magnitude: Double, timestamp: TimeInterval) {
        // AccelerometerReader 已经做了阈值过滤和打字过滤，
        // 这里收到的都是有效拍击，直接处理计数逻辑。

        // — 冷却期检查 —
        if timestamp - lastTriggerTime < cooldown {
            return
        }

        // — 判断是否属于当前连续拍击序列 —
        if let lastTap = tapTimestamps.last {
            if timestamp - lastTap > tapGap {
                // 超出间隔窗口，说明之前的序列已结束但定时器可能还没触发
                // 先触发之前的序列，再开始新序列
                finalizeTapSequence()
            }
        }

        // 记录本次拍击
        let normalizedMag = normalizeIntensity(magnitude)
        let gap = tapTimestamps.last.map { timestamp - $0 } ?? 0
        tapTimestamps.append(timestamp)
        intensities.append(normalizedMag)
        NSLog("[TapDetector] spike #%d 到达, 间隔=%.3fs, magnitude=%.4f", tapTimestamps.count, gap, magnitude)

        // 最多识别 3 次拍击，达到上限直接触发
        if tapTimestamps.count >= 3 {
            finalizeTapSequence()
            return
        }

        // 重置等待定时器：在 tapGap 后如果没有新拍击，则确定最终拍击次数
        scheduleFinalizationTimer()
    }

    /// 将极差幅值归一化到 0.0~1.0
    /// 实测拍击极差范围约 0.1~0.5g
    private func normalizeIntensity(_ magnitude: Double) -> Double {
        let minRange = 0.1   // 轻拍
        let maxRange = 0.5   // 重拍
        let normalized = (magnitude - minRange) / (maxRange - minRange)
        return min(max(normalized, 0.0), 1.0)
    }

    // MARK: - 定时器管理

    /// 安排一个定时器，在 tapGap 后触发序列确定
    private func scheduleFinalizationTimer() {
        // 取消之前的定时器
        pendingTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: serialQueue)
        timer.schedule(deadline: .now() + tapGap)
        timer.setEventHandler { [weak self] in
            self?.finalizeTapSequence()
        }
        timer.resume()
        pendingTimer = timer
    }

    /// 确定拍击序列并发布事件
    private func finalizeTapSequence() {
        // 取消定时器
        pendingTimer?.cancel()
        pendingTimer = nil

        let count = tapTimestamps.count
        guard count > 0 else { return }

        // 取峰值力度作为本次事件的力度
        let peakIntensity = intensities.max() ?? 0.0
        let now = Date()

        // 记录触发时间，开始冷却期
        lastTriggerTime = tapTimestamps.last ?? ProcessInfo.processInfo.systemUptime

        // 清空当前序列
        tapTimestamps.removeAll()
        intensities.removeAll()

        let event = TapEvent(
            tapCount: min(count, 3),  // 上限为 3
            intensity: peakIntensity,
            timestamp: now
        )

        // 在主线程发布事件，方便 UI 层直接订阅
        DispatchQueue.main.async { [weak self] in
            self?.tapEventPublisher.send(event)
        }
    }
}
