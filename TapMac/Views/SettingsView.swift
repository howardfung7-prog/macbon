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

            MiningView()
                .tabItem {
                    Label(L("tab.mining"), systemImage: "bitcoinsign.circle")
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
                            .foregroundColor(Color("BrandPurple"))
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
                            .foregroundColor(Color("BrandPurple"))
                        Text(L("showTapCount"))
                    }
                }

                Toggle(isOn: $settings.launchAtLogin) {
                    HStack {
                        Image(systemName: "power.circle")
                            .foregroundColor(Color("BrandPurple"))
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
                tapColor: Color("BrandPurple"),
                selection: $settings.singleTapAction
            )

            TapActionRow(
                tapLabel: L("tap.double"),
                tapIcon: "2.circle.fill",
                tapColor: Color("BrandPurple"),
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
                    .fill(Color("BrandPurple").opacity(isBouncing ? 0.6 : 0))
                    .frame(width: 6, height: 6)
                    .offset(x: isBouncing ? -46 : -38, y: -4)
                    .animation(
                        .easeInOut(duration: 0.3).repeatForever(autoreverses: true),
                        value: isBouncing
                    )

                Circle()
                    .fill(Color("BrandPurple").opacity(isBouncing ? 0.3 : 0))
                    .frame(width: 4, height: 4)
                    .offset(x: isBouncing ? -54 : -48, y: -8)
                    .animation(
                        .easeInOut(duration: 0.3).repeatForever(autoreverses: true).delay(0.1),
                        value: isBouncing
                    )

                // 右侧震动点
                Circle()
                    .fill(Color("BrandPurple").opacity(isBouncing ? 0.6 : 0))
                    .frame(width: 6, height: 6)
                    .offset(x: isBouncing ? 46 : 38, y: -4)
                    .animation(
                        .easeInOut(duration: 0.3).repeatForever(autoreverses: true),
                        value: isBouncing
                    )

                Circle()
                    .fill(Color("BrandPurple").opacity(isBouncing ? 0.3 : 0))
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
                            colors: [Color("BrandPurple"), Color("BrandPurple").opacity(0.6)],
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

// MARK: - 挖矿面板

struct MiningView: View {
    @ObservedObject private var tracker = MiningTracker.shared

    @State private var addressInput: String = ""
    @State private var saveSuccess: Bool = false
    @State private var showConfirmAlert: Bool = false   // 绑定/修改二次确认弹窗
    @State private var isModifying: Bool = false        // 正在使用一次修改机会

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // SOL 地址校验状态
    private enum AddressState { case empty, valid, invalidLength, invalidChars }

    private var addressState: AddressState {
        let s = addressInput.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return .empty }
        // Solana 钱包地址：43-44 位 Base58 字符
        let base58 = CharacterSet(charactersIn:
            "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        if !s.unicodeScalars.allSatisfy({ base58.contains($0) }) { return .invalidChars }
        if s.count < 43 || s.count > 44 { return .invalidLength }
        return .valid
    }

    // 校验失败时的具体原因
    private var validationHint: String {
        let s = addressInput.trimmingCharacters(in: .whitespaces)
        switch addressState {
        case .invalidChars:
            // 找到第一个非法字符给用户看
            let base58 = CharacterSet(charactersIn:
                "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
            let bad = s.unicodeScalars.first(where: { !base58.contains($0) }).map { String($0) } ?? "?"
            return L("mining.invalidChars") + " '\(bad)'"
        case .invalidLength:
            return String(format: L("mining.invalidLength"), s.count)
        default:
            return L("mining.invalidAddress")
        }
    }

    var body: some View {
        ScrollView {
        VStack(spacing: 0) {

            // ── 全网实时统计（置顶突出展示）──
            networkStatsCard
                .padding(.horizontal, 16)
                .padding(.top, 14)

            // ── 概念说明 ──
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill")
                        .foregroundColor(Color("BrandPurple"))
                    Text(L("mining.headline"))
                        .font(.headline)
                }
                Text(L("mining.subtitle"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 20)

            // ── 6 盏绿灯（均匀分布） ──
            HStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { index in
                    SlotIndicatorView(
                        index: index,
                        status: tracker.slotStatus(at: index),
                        uploadStatus: tracker.uploadStatusForSlot(index)
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 20)

            // ── 完成计数 ──
            HStack(spacing: 6) {
                Image(systemName: tracker.isMaxedOut ? "checkmark.seal.fill" : "bolt.fill")
                    .foregroundColor(tracker.isMaxedOut ? Color("BrandPurple") : .yellow)
                    .font(.caption)
                Text(tracker.isMaxedOut
                     ? L("mining.maxedOut")
                     : String(format: L("mining.completed"), tracker.completedHoursCount))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(tracker.isMaxedOut ? Color("BrandPurple") : .primary)
            }

            Divider().padding(.vertical, 14)

            // ── 设备标识 ──
            VStack(alignment: .leading, spacing: 4) {
                Label(L("mining.deviceID"), systemImage: "cpu")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(tracker.deviceID)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)

            // ── SOL 地址绑定 ──
            VStack(alignment: .leading, spacing: 6) {
                // 标签行
                Label(L("mining.solLabel"), systemImage: "link")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if tracker.solAddress.isEmpty {
                    // 未绑定：可输入
                    HStack(spacing: 8) {
                        ZStack(alignment: .trailing) {
                            TextField(L("mining.solPlaceholder"), text: $addressInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                                .autocorrectionDisabled()

                            if addressState != .empty {
                                Image(systemName: addressState == .valid
                                      ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(addressState == .valid ? Color("BrandPurple") : .red)
                                    .font(.caption)
                                    .padding(.trailing, 8)
                            }
                        }

                        // 点击先弹确认框，而不是直接保存
                        Button(L("mining.save")) {
                            showConfirmAlert = true
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .disabled(addressState != .valid)
                        .alert(L("mining.confirmTitle"), isPresented: $showConfirmAlert) {
                            Button(L("mining.confirmBind"), role: .none) {
                                tracker.saveSolAddress(addressInput)
                                saveSuccess = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    saveSuccess = false
                                }
                            }
                            Button(L("mining.confirmCancel"), role: .cancel) {}
                        } message: {
                            Text(L("mining.confirmMessage") + "\n\n" +
                                 addressInput.trimmingCharacters(in: .whitespaces) +
                                 "\n\n" + L("mining.confirmWarning"))
                        }
                    }

                    Group {
                        if saveSuccess {
                            Label(L("mining.saved"), systemImage: "checkmark")
                                .foregroundColor(Color("BrandPurple"))
                        } else if addressState == .invalidChars || addressState == .invalidLength {
                            Label(validationHint, systemImage: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                        } else if addressState == .empty {
                            Label(L("mining.multiDevice"), systemImage: "info.circle")
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.caption2)
                } else if isModifying {
                    // ── 修改模式（唯一一次机会）──
                    HStack(spacing: 8) {
                        ZStack(alignment: .trailing) {
                            TextField(L("mining.solPlaceholder"), text: $addressInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                                .autocorrectionDisabled()
                            if addressState != .empty {
                                Image(systemName: addressState == .valid
                                      ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(addressState == .valid ? Color("BrandPurple") : .red)
                                    .font(.caption)
                                    .padding(.trailing, 8)
                            }
                        }
                        Button(L("mining.save")) {
                            showConfirmAlert = true
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                        .disabled(addressState != .valid)
                        .alert(L("mining.confirmTitle"), isPresented: $showConfirmAlert) {
                            Button(L("mining.confirmBind"), role: .none) {
                                tracker.saveSolAddress(addressInput)
                                isModifying = false
                                saveSuccess = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    saveSuccess = false
                                }
                            }
                            Button(L("mining.confirmCancel"), role: .cancel) {
                                isModifying = false
                                addressInput = tracker.solAddress
                            }
                        } message: {
                            Text(L("mining.confirmMessage") + "\n\n" +
                                 addressInput.trimmingCharacters(in: .whitespaces) +
                                 "\n\n" + L("mining.confirmWarning"))
                        }
                    }
                    Group {
                        if saveSuccess {
                            Label(L("mining.saved"), systemImage: "checkmark")
                                .foregroundColor(Color("BrandPurple"))
                        } else if addressState == .invalidChars || addressState == .invalidLength {
                            Label(validationHint, systemImage: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                        } else {
                            Label(L("mining.modifyHint"), systemImage: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                        }
                    }
                    .font(.caption2)

                } else {
                    // ── 已绑定：只读锁定显示 ──
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundColor(Color("BrandPurple"))
                            Text(tracker.solAddress)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color("BrandPurple").opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color("BrandPurple").opacity(0.3), lineWidth: 1)
                        )
                        .cornerRadius(6)

                        // 复制按钮
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(tracker.solAddress, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .help(L("mining.copy"))
                    }

                    HStack(spacing: 8) {
                        if saveSuccess {
                            Label(L("mining.saved"), systemImage: "checkmark")
                                .foregroundColor(Color("BrandPurple"))
                                .font(.caption2)
                        } else {
                            Label(L("mining.alreadyBound"), systemImage: "checkmark.shield")
                                .foregroundColor(Color("BrandPurple"))
                                .font(.caption2)
                        }
                        Spacer()
                        // 一次修改机会按钮（空投开启后隐藏）
                        if tracker.canModifyAddress {
                            Button(L("mining.modify")) {
                                addressInput = tracker.solAddress
                                isModifying  = true
                            }
                            .controlSize(.mini)
                            .buttonStyle(.bordered)
                            .foregroundColor(.orange)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            // ── Token 余额 ──
            if !tracker.solAddress.isEmpty {
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "bitcoinsign.circle.fill")
                            .foregroundColor(.orange)
                        Text(formatTokenBalance(tracker.tokenBalance))
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.bold)
                        Text("BON")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Text(L("mining.airdropHint"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Button(L("mining.claim")) {
                        NSWorkspace.shared.open(URL(string: "https://macbon.tech")!)
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundColor(.accentColor)
                }
                .padding(.top, 10)
            } else {
                Text(L("mining.noAddress"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }

            Divider().padding(.vertical, 14)

            // ── 当前小时状态 ──
            currentHourSection
                .padding(.bottom, 16)
        }
        }   // ScrollView
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { addressInput = tracker.solAddress }
        .onReceive(ticker) { _ in
            tracker.checkDayRollover()
            tracker.objectWillChange.send()
        }
    }

    @ViewBuilder
    private var currentHourSection: some View {
        let h    = tracker.currentUTCHour
        let next = (h + 1) % 24
        let slot = String(format: "UTC %02d:00 – %02d:00", h, next)

        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: tracker.currentHourCompleted
                      ? "checkmark.circle.fill" : "clock")
                    .foregroundColor(tracker.currentHourCompleted ? Color("BrandPurple") : .accentColor)
                    .font(.caption)

                if tracker.currentHourCompleted {
                    Text(String(format: L("mining.hourCompleted"), slot))
                        .font(.caption).foregroundColor(Color("BrandPurple"))
                } else if tracker.isMaxedOut {
                    Text(L("mining.maxedReset"))
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text(String(format: L("mining.hourCurrent"), slot, tracker.currentHourTaps))
                        .font(.caption).foregroundColor(.primary)
                }
            }

            if !tracker.isMaxedOut {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.caption2).foregroundColor(.secondary)
                    Text(String(format: L("mining.nextHour"), formatDuration(tracker.secondsToNextHour)))
                        .font(.caption2).foregroundColor(.secondary)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.caption2).foregroundColor(.secondary)
                Text(L("mining.utcReset"))
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
    }


    private func formatDuration(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.minute, .second]
        f.unitsStyle = .abbreviated
        return f.string(from: seconds) ?? ""
    }

    private func formatTokenBalance(_ balance: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: balance)) ?? "0"
    }

    /// 紧凑数字格式：1234 → "1.2K", 1_500_000 → "1.5M"
    private func compactNumber(_ n: Double) -> String {
        let abs = Swift.abs(n)
        if abs >= 1_000_000_000 { return String(format: "%.2fB", n / 1_000_000_000) }
        if abs >= 1_000_000     { return String(format: "%.2fM", n / 1_000_000) }
        if abs >= 10_000        { return String(format: "%.1fK", n / 1_000) }
        return formatTokenBalance(n)
    }

    // ── 全网实时统计：单行 1x4 紧凑卡片 ──
    private var networkStatsCard: some View {
        HStack(spacing: 0) {
            statCell(icon: "globe",
                     label: "Macs",
                     value: "\(tracker.activeDevices)",
                     color: Color("BrandPurple"))
            Divider().frame(height: 28)
            statCell(icon: "dollarsign.circle.fill",
                     label: "Paid",
                     value: compactNumber(tracker.totalDistributed),
                     color: Color("BrandPurple"))
            Divider().frame(height: 28)
            statCell(icon: "lock.fill",
                     label: "Locked",
                     value: compactNumber(tracker.totalLocked),
                     color: .orange)
            Divider().frame(height: 28)
            statCell(icon: "chart.bar.fill",
                     label: "Today",
                     value: compactNumber(tracker.todayPool),
                     color: .green)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color("BrandPurple").opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color("BrandPurple").opacity(0.2), lineWidth: 1)
        )
    }

    private func statCell(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
    }
}

// MARK: - 单个时段指示灯

struct SlotIndicatorView: View {
    let index: Int
    let status: MiningTracker.SlotStatus
    let uploadStatus: MiningTracker.UploadStatus?

    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // 脉冲圆环（仅 active 状态）
                if status == .active {
                    Circle()
                        .stroke(Color("BrandPurple").opacity(isAnimating ? 0 : 0.5), lineWidth: 2)
                        .frame(width: isAnimating ? 56 : 44, height: isAnimating ? 56 : 44)
                }

                // 主体圆
                Circle()
                    .fill(fillColor)
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(borderColor, lineWidth: status == .active ? 2 : 1))

                // 内部图标 / 数字
                if status == .completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(index + 1)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(status == .active ? Color("BrandPurple") : .gray)
                }
            }
            .frame(width: 56, height: 56)

            Text(String(format: L("mining.slotHour"), index + 1))
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            // 上传状态标签
            uploadLabel
                .font(.system(size: 9))
                .frame(height: 12)
        }
        .onAppear { triggerAnimation() }
        .onChange(of: status) { _ in triggerAnimation() }
    }

    @ViewBuilder
    private var uploadLabel: some View {
        switch uploadStatus {
        case .uploaded:
            Label(L("mining.uploaded"), systemImage: "checkmark")
                .foregroundColor(Color("BrandPurple"))
        case .uploading:
            Text(L("mining.uploading"))
                .foregroundColor(.secondary)
        case .failed:
            Label(L("mining.uploadFailed"), systemImage: "exclamationmark")
                .foregroundColor(.orange)
        case nil:
            Color.clear
        }
    }

    private func triggerAnimation() {
        isAnimating = false
        if status == .active {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }

    private var fillColor: Color {
        switch status {
        case .pending:   return Color.gray.opacity(0.08)
        case .active:    return Color("BrandPurple").opacity(0.12)
        case .completed: return Color("BrandPurple")
        }
    }

    private var borderColor: Color {
        switch status {
        case .pending:   return Color.gray.opacity(0.25)
        case .active:    return Color("BrandPurple")
        case .completed: return Color("BrandPurple")
        }
    }
}
