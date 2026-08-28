import SwiftUI

#if os(iOS)

/// iOS 15+ 设置页：使用系统滚动、导航和开关控件，视觉上采用与“我的”页一致的分组卡片层级。
struct SettingsView: View {
    var body: some View {
        IOSSettingsPage()
    }
}

private struct IOSSettingsPage: View {
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var account: AccountStore
    @ObservedObject private var player = PlayerService.shared
    @State private var cacheSize = String(localized: "计算中…")
    @State private var activePicker: PickerRoute?

    private enum PickerRoute: String, Identifiable {
        case quality, appearance, nowPlayingMode

        var id: String { rawValue }

        var title: String {
            switch self {
            case .quality: return String(localized: "音质")
            case .appearance: return String(localized: "主题")
            case .nowPlayingMode: return String(localized: "播放页模式")
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                playbackSection
                appearanceSection
                storageSection
                accountSection
                updateSection
                aboutSection
            }
            .padding(.horizontal, Theme.Layout.contentInset)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $activePicker) { route in
            pickerSheet(for: route)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        .task { updateCacheSize() }
    }

    private var playbackSection: some View {
        IOSSettingsGroup("播放") {
            IOSSettingsDisclosureRow(
                title: "音质",
                detail: settings.audioQuality.displayName
            ) {
                activePicker = .quality
            }
            IOSSettingsDivider()
            IOSSettingsDescription("无损与 Hi-Res 需要黑胶 VIP，未开通时自动回落到可用音质")
            IOSSettingsDivider()
            IOSSettingsDisclosureRow(
                title: "倍速播放",
                detail: player.playbackRate.displayName,
                titleColor: .blue,
                detailColor: Theme.accent
            ) {
                player.cyclePlaybackRate()
            }
            IOSSettingsDivider()
            IOSSettingsToggleRow("灰色歌曲解锁", isOn: $settings.enableUnblock)
            IOSSettingsDivider()
            IOSSettingsDescription("无版权 / 下架歌曲自动从第三方音源（酷我、酷狗等）匹配播放")
        }
    }

    private var appearanceSection: some View {
        IOSSettingsGroup("外观") {
            IOSSettingsDisclosureRow(
                title: "主题",
                detail: settings.appearance.displayName
            ) {
                activePicker = .appearance
            }
            IOSSettingsDivider()
            IOSSettingsDisclosureRow(
                title: "播放页模式",
                detail: settings.nowPlayingMode.displayName
            ) {
                activePicker = .nowPlayingMode
            }
            IOSSettingsDivider()
            IOSSettingsToggleRow("显示歌词翻译", isOn: $settings.showLyricsTranslation)
            IOSSettingsDivider()
            IOSSettingsToggleRow("逐字歌词（卡拉 OK）", isOn: $settings.verbatimLyrics)
            IOSSettingsDivider()
            IOSSettingsToggleRow("显示日文歌词罗马音", isOn: $settings.showLyricsRomaji)
            IOSSettingsDivider()
            IOSSettingsDescription("日文歌词上方显示罗马音，缺少官方罗马音时自动生成读音")
        }
    }

    private var storageSection: some View {
        IOSSettingsGroup("存储") {
            IOSSettingsValueRow(title: "图片缓存", value: cacheSize)
            IOSSettingsDivider()
            Button {
                clearCache()
            } label: {
                IOSSettingsActionRow(title: "清除缓存", tint: .blue)
            }
            .buttonStyle(IOSSettingsRowButtonStyle())
            .accessibilityHint("清除已缓存的封面图片")
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        IOSSettingsGroup("账号") {
            if let profile = account.profile {
                IOSSettingsValueRow(title: "当前账号", value: profile.nickname)
                IOSSettingsDivider()
                Button(role: .destructive) {
                    Task { await AccountStore.shared.logout() }
                } label: {
                    IOSSettingsActionRow(title: "退出登录", tint: Theme.accent)
                }
                .buttonStyle(IOSSettingsRowButtonStyle())
            } else {
                IOSSettingsValueRow(title: "当前账号", value: "未登录")
            }
        }
    }

    private var updateSection: some View {
        IOSSettingsGroup("更新") {
            if #available(iOS 16.0, *) {
                IOSSettingsToggleRow("启动时自动检查更新", isOn: $settings.autoCheckUpdates)
                IOSSettingsDivider()
                IOSSettingsDescription("关闭后启动不再自动弹出更新提示，仍可随时手动检查更新")
            } else {
                Button {
                    settings.suppressUpdatePrompts.toggle()
                } label: {
                    IOSSettingsIconActionRow(
                        title: settings.suppressUpdatePrompts ? "已屏蔽自动更新" : "屏蔽自动更新",
                        icon: settings.suppressUpdatePrompts ? "bell.slash.fill" : "bell.slash",
                        tint: .blue
                    )
                }
                .buttonStyle(IOSSettingsRowButtonStyle())
                IOSSettingsDivider()
                IOSSettingsDescription(
                    settings.suppressUpdatePrompts
                        ? "启动时不会显示新版本提醒，仍可随时手动检查。"
                        : "关闭启动时的新版本提醒，不影响手动检查。"
                )
            }
        }
    }

    private var aboutSection: some View {
        IOSSettingsGroup("关于") {
            IOSSettingsValueRow(title: "Kumone", value: appVersion)
            IOSSettingsDivider()
            Button {
                IOSUpdater.shared.check(interactive: true)
            } label: {
                IOSSettingsIconActionRow(
                    title: "检查更新",
                    icon: "arrow.triangle.2.circlepath",
                    tint: .blue
                )
            }
            .buttonStyle(IOSSettingsRowButtonStyle())
            IOSSettingsDivider()
            IOSSettingsDescription("装有 TrollStore（巨魔）可在应用内一键自动安装；否则可下载 IPA 用侧载工具重装（登录状态与设置保留）")
        }
    }

    @ViewBuilder
    private func pickerSheet(for route: PickerRoute) -> some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    switch route {
                    case .quality:
                        ForEach(AudioQuality.allCases) { quality in
                            IOSSettingsChoiceRow(
                                title: quality.displayName,
                                isSelected: settings.audioQuality == quality
                            ) {
                                settings.audioQuality = quality
                                activePicker = nil
                            }
                            IOSSettingsDivider()
                        }
                    case .appearance:
                        ForEach(AppAppearance.allCases) { appearance in
                            IOSSettingsChoiceRow(
                                title: appearance.displayName,
                                isSelected: settings.appearance == appearance
                            ) {
                                settings.appearance = appearance
                                activePicker = nil
                            }
                            IOSSettingsDivider()
                        }
                    case .nowPlayingMode:
                        ForEach(NowPlayingMode.allCases) { mode in
                            IOSSettingsChoiceRow(
                                title: mode.displayName,
                                isSelected: settings.nowPlayingMode == mode
                            ) {
                                settings.nowPlayingMode = mode
                                activePicker = nil
                            }
                            IOSSettingsDivider()
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
                }
                .padding(Theme.Layout.contentInset)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(route.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { activePicker = nil }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return "\(version)-iOS15"
    }

    private var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("im.missuo.Kumone/images", isDirectory: true)
    }

    private func updateCacheSize() {
        let directory = cacheDirectory
        DispatchQueue.global(qos: .utility).async {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey]
            )) ?? []
            let bytes = files.reduce(0) { sum, url in
                sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            let formatted = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            DispatchQueue.main.async { cacheSize = formatted }
        }
    }

    private func clearCache() {
        let directory = cacheDirectory
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            DispatchQueue.main.async {
                cacheSize = String(localized: "0 字节")
                ToastCenter.shared.show(String(localized: "缓存已清除"))
            }
        }
    }
}

private struct IOSSettingsGroup<Content: View>: View {
    let title: LocalizedStringKey
    let content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)

            VStack(spacing: 0) {
                content
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.6)
            }
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        }
    }
}

private struct IOSSettingsDisclosureRow: View {
    let title: String
    let detail: String
    var titleColor: Color = .primary
    var detailColor: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(titleColor)
                Spacer(minLength: 10)
                Text(detail)
                    .foregroundStyle(detailColor)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 17, weight: .regular))
            .frame(minHeight: 58)
            .padding(.horizontal, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(IOSSettingsRowButtonStyle())
    }
}

private struct IOSSettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.primary)
        }
        .tint(.green)
        .frame(minHeight: 58)
        .padding(.horizontal, 18)
    }
}

private struct IOSSettingsValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 10)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 17, weight: .regular))
        .frame(minHeight: 58)
        .padding(.horizontal, 18)
    }
}

private struct IOSSettingsActionRow: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(.horizontal, 18)
            .contentShape(Rectangle())
    }
}

private struct IOSSettingsIconActionRow: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
        }
        .font(.system(size: 17, weight: .regular))
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(.horizontal, 18)
        .contentShape(Rectangle())
    }
}

private struct IOSSettingsDescription: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
    }
}

private struct IOSSettingsChoiceRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.blue)
                }
            }
            .frame(minHeight: 58)
            .padding(.horizontal, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(IOSSettingsRowButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct IOSSettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.primary.opacity(0.08))
            .padding(.leading, 18)
    }
}

private struct IOSSettingsRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.07) : Color.clear)
            .opacity(configuration.isPressed ? 0.76 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#else

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var account: AccountStore
    @ObservedObject private var player = PlayerService.shared
    @State private var cacheSize: String = String(localized: "计算中…")

    var body: some View {
        Form {
            Section("播放") {
                Picker("音质", selection: $settings.audioQuality) {
                    ForEach(AudioQuality.allCases) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }
                Text("无损与 Hi-Res 需要黑胶 VIP，未开通时自动回落到可用音质")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("灰色歌曲解锁", isOn: $settings.enableUnblock)
                Text("无版权 / 下架歌曲自动从第三方音源（酷我、酷狗等）匹配播放")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("外观") {
                Picker("主题", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.displayName).tag(appearance)
                    }
                }
                Toggle("显示歌词翻译", isOn: $settings.showLyricsTranslation)
                Toggle("逐字歌词（卡拉OK）", isOn: $settings.verbatimLyrics)
                Toggle("显示日文歌词罗马音", isOn: $settings.showLyricsRomaji)
                Toggle("桌面歌词", isOn: $settings.showDesktopLyrics)
            }

            Section("存储") {
                HStack {
                    Text("图片缓存")
                    Spacer()
                    Text(cacheSize).foregroundStyle(.secondary)
                }
                Button("清除缓存") { clearCache() }
            }

            Section("账号") {
                if let profile = account.profile {
                    HStack {
                        Text("当前账号")
                        Spacer()
                        Text(profile.nickname).foregroundStyle(.secondary)
                    }
                    Button("退出登录", role: .destructive) {
                        Task { await AccountStore.shared.logout() }
                    }
                } else {
                    Text("未登录").foregroundStyle(.secondary)
                }
            }

            Section("更新") {
                Toggle("启动时自动检查更新", isOn: $settings.autoCheckUpdates)
                Text("关闭后启动不再自动弹出更新提示，仍可手动检查更新")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("关于") {
                HStack {
                    Text("Kumone")
                    Spacer()
                    Text(appVersion).foregroundStyle(.secondary)
                }
                Text("网易云音乐第三方客户端 · 数据来自网易云音乐")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 480)
        .task { updateCacheSize() }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    private var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("im.missuo.Kumone/images", isDirectory: true)
    }

    private func updateCacheSize() {
        let directory = cacheDirectory
        DispatchQueue.global(qos: .utility).async {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey]
            )) ?? []
            let bytes = files.reduce(0) { sum, url in
                sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            let formatted = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            DispatchQueue.main.async { cacheSize = formatted }
        }
    }

    private func clearCache() {
        let directory = cacheDirectory
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            DispatchQueue.main.async {
                cacheSize = String(localized: "0 字节")
                ToastCenter.shared.show(String(localized: "缓存已清除"))
            }
        }
    }
}

#endif
