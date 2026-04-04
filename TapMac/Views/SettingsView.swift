import SwiftUI

// MARK: - 设置主界面

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label(L("tab.general"), systemImage: "gearshape")
                }

            ActionBindingView()
                .tabItem {
                    Label(L("tab.actions"), systemImage: "hand.tap")
                }

            AudioSettingsView()
                .tabItem {
                    Label(L("tab.audio"), systemImage: "speaker.wave.2")
                }

            AboutView()
                .tabItem {
                    Label(L("tab.about"), systemImage: "info.circle")
                }
        }
        .frame(width: 520, height: 480)
    }
}

// MARK: - 便捷本地化函数

/// 简写的 NSLocalizedString 调用
private func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

// MARK: - 通用设置

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    private var thresholdDescription: String {
        let threshold = 0.50 - (settings.sensitivity * 0.30)
        if settings.sensitivity < 0.3 {
            return String(format: L("sensitivity.heavy"), threshold)
        } else if settings.sensitivity < 0.7 {
            return String(format: L("sensitivity.medium"), threshold)
        } else {
            return String(format: L("sensitivity.light"), threshold)
        }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "hand.tap")
                            .foregroundColor(.accentColor)
                        Text(L("sensitivity.title"))
                            .font(.headline)
                    }

                    HStack {
                        Image(systemName: "tortoise")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: $settings.sensitivity, in: 0.05...0.95, step: 0.05)
                        Image(systemName: "hare")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(thresholdDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "timer")
                            .foregroundColor(.orange)
                        Text(L("tapGap.title"))
                            .font(.headline)
                        Spacer()
                        Text("\(String(format: "%.1f", settings.tapGap))s")
                            .monospacedDigit()
                            .foregroundColor(.accentColor)
                            .fontWeight(.medium)
                    }

                    Slider(value: $settings.tapGap, in: 0.5...1.5, step: 0.1)

                    Text(L("tapGap.desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "snowflake")
                            .foregroundColor(.blue)
                        Text(L("cooldown.title"))
                            .font(.headline)
                        Spacer()
                        Text("\(String(format: "%.1f", settings.cooldown))s")
                            .monospacedDigit()
                            .foregroundColor(.accentColor)
                            .fontWeight(.medium)
                    }

                    Slider(value: $settings.cooldown, in: 0.3...2.0, step: 0.1)

                    Text(L("cooldown.desc"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Toggle(isOn: $settings.showTapCount) {
                    HStack {
                        Image(systemName: "number.circle")
                            .foregroundColor(.green)
                        Text(L("showTapCount"))
                    }
                }

                Toggle(isOn: $settings.launchAtLogin) {
                    HStack {
                        Image(systemName: "power.circle")
                            .foregroundColor(.purple)
                        Text(L("launchAtLogin"))
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - 动作绑定

struct ActionBindingView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Text(L("actions.hint"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            TapActionRow(
                tapLabel: L("tap.single"),
                tapIcon: "1.circle.fill",
                tapColor: .blue,
                selection: $settings.singleTapAction
            )

            TapActionRow(
                tapLabel: L("tap.double"),
                tapIcon: "2.circle.fill",
                tapColor: .green,
                selection: $settings.doubleTapAction
            )

            TapActionRow(
                tapLabel: L("tap.triple"),
                tapIcon: "3.circle.fill",
                tapColor: .orange,
                selection: $settings.tripleTapAction
            )

            Section {
                Button(action: { settings.resetToDefaults() }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text(L("actions.reset"))
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .padding()
    }
}

/// 单行拍击动作配置
struct TapActionRow: View {
    let tapLabel: String
    let tapIcon: String
    let tapColor: Color
    @Binding var selection: ActionType

    var body: some View {
        Section {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: tapIcon)
                        .font(.title2)
                        .foregroundColor(tapColor)
                    Text(tapLabel)
                        .font(.headline)
                }
                .frame(width: 100, alignment: .leading)

                Picker("", selection: $selection) {
                    ForEach(ActionCategory.allCases, id: \.self) { category in
                        Section(header: Text(category.name)) {
                            ForEach(ActionType.allCases.filter { $0.category == category }) { action in
                                HStack {
                                    Image(systemName: action.icon)
                                    Text(action.name)
                                }
                                .tag(action)
                            }
                        }
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 8) {
                Image(systemName: selection.icon)
                    .foregroundColor(tapColor.opacity(0.8))
                    .frame(width: 20)
                Text(selection.actionDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }
}

// MARK: - 音频设置

struct AudioSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var audioFiles: [URL] = []

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundColor(.accentColor)
                        Text(L("audio.volume"))
                            .font(.headline)
                    }

                    HStack {
                        Image(systemName: "speaker.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: $settings.volume, in: 0...1, step: 0.05)
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(Int(settings.volume * 100))%")
                            .monospacedDigit()
                            .frame(width: 40)
                            .foregroundColor(.accentColor)
                    }

                    Toggle(L("audio.dynamic"), isOn: $settings.dynamicVolume)
                        .font(.subheadline)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.yellow)
                        Text(L("audio.customFiles"))
                            .font(.headline)
                    }

                    HStack {
                        Text(settings.customAudioFolderURL.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button(L("audio.openFolder")) {
                            NSWorkspace.shared.open(settings.customAudioFolderURL)
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section {
                if audioFiles.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "music.note.list")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text(L("audio.empty"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(L("audio.formats"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 12)
                        Spacer()
                    }
                } else {
                    ForEach(audioFiles, id: \.self) { url in
                        HStack {
                            Image(systemName: "music.note")
                                .foregroundColor(.accentColor)
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                            Spacer()
                            Text(fileSizeString(url))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Button(action: { importAudioFile() }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text(L("audio.add"))
                    }
                }
            }
        }
        .padding()
        .onAppear { loadAudioFiles() }
    }

    private func loadAudioFiles() {
        let url = settings.customAudioFolderURL
        let extensions = ["mp3", "m4a", "wav", "aiff", "aac"]
        audioFiles = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil))?.filter {
            extensions.contains($0.pathExtension.lowercased())
        }.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) ?? []
    }

    private func importAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mp3, .wav, .aiff]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            for url in panel.urls {
                let dest = settings.customAudioFolderURL.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.copyItem(at: url, to: dest)
            }
            loadAudioFiles()
        }
    }

    private func fileSizeString(_ url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

// MARK: - 关于

struct AboutView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var isBouncing = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                // 阴影
                Ellipse()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: isBouncing ? 40 : 56, height: 8)
                    .blur(radius: 2)
                    .offset(y: 38)
                    .animation(
                        .easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                        value: isBouncing
                    )

                // 左侧震动点
                Circle()
                    .fill(Color.blue.opacity(isBouncing ? 0.6 : 0))
                    .frame(width: 6, height: 6)
                    .offset(x: isBouncing ? -46 : -38, y: -4)
                    .animation(
                        .easeInOut(duration: 0.3).repeatForever(autoreverses: true),
                        value: isBouncing
                    )

                Circle()
                    .fill(Color.blue.opacity(isBouncing ? 0.3 : 0))
                    .frame(width: 4, height: 4)
                    .offset(x: isBouncing ? -54 : -48, y: -8)
                    .animation(
                        .easeInOut(duration: 0.3).repeatForever(autoreverses: true).delay(0.1),
                        value: isBouncing
                    )

                // 右侧震动点
                Circle()
                    .fill(Color.purple.opacity(isBouncing ? 0.6 : 0))
                    .frame(width: 6, height: 6)
                    .offset(x: isBouncing ? 46 : 38, y: -4)
                    .animation(
                        .easeInOut(duration: 0.3).repeatForever(autoreverses: true),
                        value: isBouncing
                    )

                Circle()
                    .fill(Color.purple.opacity(isBouncing ? 0.3 : 0))
                    .frame(width: 4, height: 4)
                    .offset(x: isBouncing ? 54 : 48, y: -8)
                    .animation(
                        .easeInOut(duration: 0.3).repeatForever(autoreverses: true).delay(0.1),
                        value: isBouncing
                    )

                // Mac 电脑
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .offset(y: isBouncing ? -12 : 0)
                    .rotationEffect(.degrees(isBouncing ? -3 : 3))
                    .animation(
                        .easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                        value: isBouncing
                    )
            }
            .frame(height: 80)
            .onAppear { isBouncing = true }

            Text("MacBon")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(L("about.subtitle"))
                .font(.title3)
                .foregroundColor(.secondary)

            Text("v1.0.0")
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

            Divider()
                .frame(width: 200)

            VStack(spacing: 6) {
                Text(L("about.slogan"))
                    .font(.subheadline)

                HStack(spacing: 4) {
                    Image(systemName: "laptopcomputer")
                        .font(.caption)
                    Text(L("about.totalTaps"))
                        .font(.caption)
                    Text("\(settings.totalTapCount)")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                }
            }

            Spacer()

            Text("Made with ♥ for Mac")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
