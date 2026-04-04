import Foundation

// MARK: - 动作分类

/// 动作分类枚举
enum ActionCategory: String, CaseIterable, Codable {
    case efficiency = "efficiency"
    case emotion = "emotion"

    var name: String {
        switch self {
        case .efficiency: return NSLocalizedString("category.efficiency", comment: "")
        case .emotion:    return NSLocalizedString("category.emotion", comment: "")
        }
    }

    var icon: String {
        switch self {
        case .efficiency: return "bolt.fill"
        case .emotion:    return "heart.fill"
        }
    }
}

// MARK: - 动作类型

/// MacBon 支持的动作类型
enum ActionType: String, CaseIterable, Codable, Identifiable {

    // MARK: 效率类

    case lockScreen
    case muteToggle
    case quickMemo

    // MARK: 情感类

    case customAudio
    case randomEncourage
    case customVoiceClock

    // MARK: - Identifiable

    var id: String { rawValue }

    // MARK: - 本地化名称

    var name: String {
        NSLocalizedString("action.\(rawValue).name", comment: "")
    }

    // MARK: - 图标

    var icon: String {
        switch self {
        case .lockScreen:       return "lock.fill"
        case .muteToggle:       return "speaker.slash.fill"
        case .quickMemo:        return "mic.circle.fill"
        case .customAudio:      return "music.note"
        case .randomEncourage:  return "hands.clap.fill"
        case .customVoiceClock: return "waveform.circle.fill"
        }
    }

    // MARK: - 本地化描述

    var actionDescription: String {
        NSLocalizedString("action.\(rawValue).desc", comment: "")
    }

    // MARK: - 分类

    var category: ActionCategory {
        switch self {
        case .lockScreen, .muteToggle, .quickMemo:
            return .efficiency
        case .customAudio, .randomEncourage, .customVoiceClock:
            return .emotion
        }
    }

    // MARK: - 便捷方法

    static func actions(for category: ActionCategory) -> [ActionType] {
        allCases.filter { $0.category == category }
    }
}
