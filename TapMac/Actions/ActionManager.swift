import Foundation
import AppKit
import AVFoundation

/// Action execution manager
/// Handles all local actions and manages audio playback
class ActionManager: ObservableObject {

    // MARK: - Published Properties

    @Published var lastMessage: String?

    var volume: Float = 0.8

    // MARK: - Private Properties

    private var audioPlayer: AVAudioPlayer?
    private let speechSynthesizer = AVSpeechSynthesizer()

    /// 自定义音频顺序播放索引
    private var currentAudioIndex: Int = 0

    /// 根据系统语言读取本地化鼓励语句列表（分号分隔）
    private var encouragements: [String] {
        let raw = NSLocalizedString("encouragements", comment: "")
        return raw.split(separator: ";").map(String.init).filter { !$0.isEmpty }
    }

    // MARK: - Custom Audio Directory

    var customAudioFolder: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folder = home.appendingPathComponent("MacBon/Sounds", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        return folder
    }

    // MARK: - Action Entry Point

    func execute(action: ActionType, completion: ((Bool) -> Void)? = nil) {
        print("[MacBon] Execute: \(action.rawValue)")

        switch action {
        case .lockScreen:
            lockScreen(completion: completion)
        case .muteToggle:
            toggleMute(completion: completion)
        case .quickMemo:
            toggleQuickMemo(completion: completion)
        case .customAudio:
            playCustomAudio(completion: completion)
        case .randomEncourage:
            playRandomEncouragement(completion: completion)
        case .customVoiceClock:
            customVoiceClock(completion: completion)
        }
    }

    // MARK: - Lock Screen

    private func lockScreen(completion: ((Bool) -> Void)? = nil) {
        // Cmd+Ctrl+Q 是 macOS 官方"锁定屏幕"快捷键，立即锁定并要求密码
        // pmset displaysleepnow 仅让屏幕休眠，不保证锁定，作为备用
        let lockScript = """
        tell application "System Events" to keystroke "q" using {command down, control down}
        """

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let script = NSAppleScript(source: lockScript)
            script?.executeAndReturnError(&error)

            if error == nil {
                DispatchQueue.main.async {
                    self.lastMessage = NSLocalizedString("msg.screen.locked", comment: "")
                    completion?(true)
                }
            } else {
                // 备用：pmset 让屏幕休眠
                print("[MacBon] AppleScript lock failed, trying pmset")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
                process.arguments = ["displaysleepnow"]
                try? process.run()
                process.waitUntilExit()
                DispatchQueue.main.async {
                    self.lastMessage = NSLocalizedString("msg.screen.locked", comment: "")
                    completion?(true)
                }
            }
        }
    }

    // MARK: - Mute Toggle

    private func toggleMute(completion: ((Bool) -> Void)? = nil) {
        let script = """
        set currentVolume to output muted of (get volume settings)
        if currentVolume then
            set volume without output muted
        else
            set volume with output muted
        end if
        """
        runAppleScript(script, actionName: ActionType.muteToggle.name, completion: completion)
    }

    // MARK: - Quick Memo（弹出文字输入窗，回车保存到 ~/MacBon/Memos/）

    private func toggleQuickMemo(completion: ((Bool) -> Void)? = nil) {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Notes.app"))
        DispatchQueue.main.async {
            self.lastMessage = String(format: NSLocalizedString("msg.action.success", comment: ""), ActionType.quickMemo.name)
            completion?(true)
        }
    }

    // MARK: - Custom Audio（顺序轮播）

    private func playCustomAudio(completion: ((Bool) -> Void)? = nil) {
        let files = getAudioFiles()
        guard !files.isEmpty else {
            print("[MacBon] No audio files found")
            DispatchQueue.main.async {
                self.lastMessage = NSLocalizedString("msg.audio.notFound", comment: "")
                completion?(false)
            }
            return
        }
        // 顺序轮播：每次触发播放下一首
        currentAudioIndex = currentAudioIndex % files.count
        let audioFile = files[currentAudioIndex]
        currentAudioIndex = (currentAudioIndex + 1) % files.count
        playAudioFile(at: audioFile, completion: completion)
    }

    // MARK: - Random Encouragement

    private func playRandomEncouragement(completion: ((Bool) -> Void)? = nil) {
        let audioFiles = getAudioFiles()

        if !audioFiles.isEmpty {
            let randomFile = audioFiles.randomElement()!
            playAudioFile(at: randomFile, completion: completion)
        } else {
            // 使用系统语言朗读本地化鼓励语句
            let list = encouragements
            let message = list.randomElement() ?? "Keep going!"
            speak(message)   // 不指定 language，跟随系统语言
            DispatchQueue.main.async {
                self.lastMessage = message
                completion?(true)
            }
        }
    }

    // MARK: - Custom Voice Clock

    private func customVoiceClock(completion: ((Bool) -> Void)? = nil) {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        // DateFormatter 已根据系统语言返回本地化时间字符串，直接朗读即可
        let timeString = formatter.string(from: Date())

        let audioFiles = getAudioFiles()

        if let chimeFile = audioFiles.first(where: { $0.lastPathComponent.lowercased().contains("chime") })
            ?? audioFiles.first {
            playAudioFile(at: chimeFile) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.speak(timeString)
                    self?.lastMessage = String(format: NSLocalizedString("msg.voiceClock", comment: ""), timeString)
                    completion?(true)
                }
            }
        } else {
            speak(timeString)
            DispatchQueue.main.async {
                self.lastMessage = String(format: NSLocalizedString("msg.voiceClock", comment: ""), timeString)
                completion?(true)
            }
        }
    }

    // MARK: - Utility Methods

    private func runAppleScript(
        _ source: String,
        actionName: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            let script = NSAppleScript(source: source)
            script?.executeAndReturnError(&error)

            DispatchQueue.main.async {
                if let error = error {
                    let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "unknown"
                    print("[MacBon] \(actionName) failed: \(errorMessage)")
                    self.lastMessage = String(format: NSLocalizedString("msg.action.failed", comment: ""), actionName)
                    completion?(false)
                } else {
                    print("[MacBon] \(actionName) succeeded")
                    self.lastMessage = String(format: NSLocalizedString("msg.action.success", comment: ""), actionName)
                    completion?(true)
                }
            }
        }
    }

    private func getAudioFiles() -> [URL] {
        let supportedExtensions = ["mp3", "wav", "m4a", "aac", "aiff", "caf"]

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: customAudioFolder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            return files.filter { url in
                supportedExtensions.contains(url.pathExtension.lowercased())
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch {
            print("[MacBon] Audio directory read failed: \(error.localizedDescription)")
            return []
        }
    }

    private func playAudioFile(at url: URL, completion: ((Bool) -> Void)? = nil) {
        do {
            audioPlayer?.stop()
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.volume = volume
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            let fileName = url.lastPathComponent
            print("[MacBon] Playing: \(fileName)")
            DispatchQueue.main.async {
                self.lastMessage = String(format: NSLocalizedString("msg.audio.playing", comment: ""), fileName)
                completion?(true)
            }
        } catch {
            print("[MacBon] Audio playback failed: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.lastMessage = NSLocalizedString("msg.audio.failed", comment: "")
                completion?(false)
            }
        }
    }

    private func speak(_ text: String, language: String? = nil) {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        let supportedLanguages: Set<String> = ["en", "zh", "ja", "de", "fr"]
        let utterance = AVSpeechUtterance(string: text)
        let systemLang = Locale.current.language.languageCode?.identifier ?? "en"
        let lang = language ?? (supportedLanguages.contains(systemLang) ? systemLang : "en")
        utterance.voice = AVSpeechSynthesisVoice(language: lang)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speechSynthesizer.speak(utterance)
        print("[MacBon] Speech (\(lang)): \(text)")
    }

    // MARK: - Stop All

    func stopAll() {
        audioPlayer?.stop()
        audioPlayer = nil

        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        print("[MacBon] All playback stopped")
    }
}
