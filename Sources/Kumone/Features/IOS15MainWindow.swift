#if os(iOS)
import SwiftUI
import UIKit

/// iOS 15 回退根容器。避免 NavigationStack、NavigationPath 与新式 Tab API，
/// 同时让播放器和胶囊导航共用稳定的底部安全区。
public struct IOS15MainWindow: View {
    @StateObject private var player = PlayerService.shared
    @StateObject private var account = AccountStore.shared
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var toasts = ToastCenter.shared
    @StateObject private var updater = IOSUpdater.shared
    @StateObject private var keyboard = IOS15KeyboardState()
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab = 0
    /// 搜索是独立玻璃入口；递增该值可以在重复点击时回到干净的搜索根视图，
    /// 避免旧 NavigationView 栈将用户留在歌单详情页。
    @State private var searchRouteGeneration = 0
    @State private var showLogin = false
    @State private var showSettings = false

    public init() {}

    public var body: some View {
        tabContent
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomChrome
            }
            // 仅使用当前 App 实际收到的键盘帧，避免从其他 App 返回后保留旧布局。
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .environmentObject(player)
            .environmentObject(account)
            .environmentObject(settings)
            .environmentObject(toasts)
            .tint(Theme.accent)
            .preferredColorScheme(settings.appearance.colorScheme)
            .environment(\.openLogin, { showLogin = true })
            .task {
                player.loadUITestDemoTrackIfNeeded()
                if isUITestingImmersiveNowPlaying {
                    settings.nowPlayingMode = .immersive
                } else if isUITestingClassicNowPlaying {
                    settings.nowPlayingMode = .classic
                }
                if isUITestingNowPlaying {
                    player.showNowPlaying = true
                }
                await account.bootstrap()
                IOSUpdater.shared.check(interactive: false)
            }
            .onChange(of: scenePhase) { phase in
                switch phase {
                case .active:
                    keyboard.resetForSceneActivation()
                    DispatchQueue.main.async {
                        IOS15KeyboardDismissal.dismiss()
                        keyboard.resetForSceneActivation()
                    }
                case .inactive, .background:
                    // 其他应用打开键盘时，本应用不会拥有输入焦点；提前清空状态，
                    // 防止返回前台后底部标签栏和迷你播放器继续被旧帧隐藏。
                    keyboard.resetForSceneDeactivation()
                @unknown default:
                    keyboard.resetForSceneDeactivation()
                }
            }
            .onChange(of: player.showNowPlaying) { isPresented in
                if isPresented {
                    IOS15KeyboardDismissal.dismiss()
                    keyboard.resetForSceneActivation()
                }
            }
            // 统一通过系统 sheet 呈现播放页。iOS 15 会采用 UIKit 自身的
            // interactive page-sheet 转场；较新的系统继续由 SwiftUI 管理手势、
            // 速度曲线和安全区，从而避免各机型上的自定义拖拽差异。
            .sheet(isPresented: $player.showNowPlaying, onDismiss: dismissKeyboardAndResetLayout) {
                IOSNowPlayingPresentation(
                    isPresented: $player.showNowPlaying,
                    mode: settings.nowPlayingMode
                ) {
                    NowPlayingView()
                        .environmentObject(player)
                        .environmentObject(account)
                        .environmentObject(settings)
                }
            }
            .sheet(isPresented: $updater.showSheet, onDismiss: dismissKeyboardAndResetLayout) {
                IOSUpdaterSheet()
            }
            .sheet(isPresented: $showLogin, onDismiss: dismissKeyboardAndResetLayout) {
                LoginSheet()
                    .environmentObject(account)
                    .environmentObject(toasts)
            }
            .sheet(isPresented: $showSettings, onDismiss: dismissKeyboardAndResetLayout) {
                NavigationView {
                    SettingsView()
                        // iOS 15 的独立 sheet 不依赖环境对象的隐式继承。
                        // 显式注入可避免 SettingsView 首次绘制时触发 SwiftUI 陷阱。
                        .environmentObject(settings)
                        .environmentObject(account)
                        .navigationTitle("设置")
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("完成") { showSettings = false }
                            }
                        }
                }
                .navigationViewStyle(StackNavigationViewStyle())
            }
            .overlay(alignment: .top) {
                if let toast = toasts.current {
                    ToastView(toast: toast)
                        .padding(.top, 8)
                }
            }
    }

    /// 不使用 TabView，避免系统底栏和自定义胶囊标签重复叠加。
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0:
            legacyNavigation { HomeView() }
        case 1:
            legacyNavigation { IOS15ExploreView() }
        case 2:
            legacyNavigation { FMView() }
        case 3:
            // 保持 v0.3.7 搜索结构；其目的地式 NavigationLink 可在 iOS 15 使用。
            legacyNavigation { SearchView(query: "").id(searchRouteGeneration) }
        default:
            legacyNavigation { IOS15CardLibraryView(showLogin: $showLogin, showSettings: $showSettings) }
        }
    }

    @ViewBuilder
    private var bottomChrome: some View {
        // 搜索或其他文本输入激活键盘时，不将播放器和标签栏顶至键盘上方。
        // 键盘收起后由同一安全区恢复原有底部 chrome，避免出现双层导航。
        if !keyboard.isVisible {
            VStack(spacing: 8) {
                if player.hasCurrentTrack {
                    IOS15MiniPlayerBar()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                HStack(spacing: 10) {
                    IOS15CapsuleTabBar(items: Self.primaryTabItems, selection: $selectedTab)
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1)

                    IOS15LiquidGlassSearchButton(isSelected: selectedTab == 3) {
                        selectTab(3)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var isUITestingDemoPlayer: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestingDemoTrack")
    }

    private var isUITestingNowPlaying: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestingNowPlaying")
    }

    private var isUITestingImmersiveNowPlaying: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestingImmersiveNowPlaying")
    }

    private var isUITestingClassicNowPlaying: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestingClassicNowPlaying")
    }

    private func dismissKeyboardAndResetLayout() {
        IOS15KeyboardDismissal.dismiss()
        keyboard.resetForSceneActivation()
    }

    @ViewBuilder
    private func legacyNavigation<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationView {
            content()
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func selectTab(_ tab: Int) {
        if tab == 3 {
            // 独立搜索入口无论当前是否已选中，都应回到搜索根页，
            // 不能复用此前页面可能保留的详情导航状态。
            searchRouteGeneration &+= 1
        }
        selectedTab = tab
    }

    /// 搜索在参考图中是主胶囊右侧的独立玻璃入口，因此不参与主标签的等宽分区。
    private static let primaryTabItems: [IOS15CapsuleTabBar.Item] = [
        .init(id: 0, title: "推荐", icon: "house"),
        .init(id: 1, title: "精选", icon: "square.grid.2x2"),
        .init(id: 2, title: "漫游", icon: "dot.radiowaves.left.and.right"),
        .init(id: 4, title: "我的", icon: "person.crop.circle"),
    ]
}

/// 手机宽度将常用控件压缩为一行，宽屏在同一安全区内展示完整的横向控制分区。
private struct IOS15MiniPlayerBar: View {
    @EnvironmentObject private var player: PlayerService

    var body: some View {
        GeometryReader { proxy in
            Group {
                if proxy.size.width >= 620 {
                    wideContent
                } else {
                    compactContent
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: 86)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .accessibilityIdentifier("ios15MiniPlayer")
    }

    private var compactContent: some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                trackSummary
                playbackRateButton
                playPauseButton
                nextButton
                moreMenu
            }
            IOS15MiniPlayerProgress()
                .padding(.leading, 48)
                .padding(.trailing, 8)
        }
    }

    private var wideContent: some View {
        HStack(spacing: 14) {
            trackSummary
                .frame(maxWidth: 250)
            IOS15MiniPlayerProgress()
                .frame(maxWidth: .infinity)
            HStack(spacing: 2) {
                playbackRateButton
                previousButton
                playPauseButton
                nextButton
                moreMenu
            }
        }
    }

    private var trackSummary: some View {
        Button {
            player.showNowPlaying = true
        } label: {
            HStack(spacing: 9) {
                CachedAsyncImage(url: player.currentTrack?.album.picUrl?.resizedImageURL(96), animated: false)
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTrack?.name ?? "")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(player.currentTrack?.artistNames ?? "")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开正在播放")
        .accessibilityIdentifier("miniPlayerTrackSummary")
    }

    private var playbackRateButton: some View {
        Button(action: player.cyclePlaybackRate) {
            Text(player.playbackRate.displayName)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
                .frame(minWidth: 44, minHeight: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("倍速播放")
        .accessibilityValue(player.playbackRate.displayName)
        .accessibilityIdentifier("miniPlayerPlaybackRateButton")
    }

    private var previousButton: some View {
        Button(action: player.previous) {
            Image(systemName: "backward.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(player.isFMMode ? Color.secondary.opacity(0.35) : Color.secondary)
                .frame(width: 38, height: 42)
        }
        .buttonStyle(.pressable)
        .disabled(player.isFMMode)
        .accessibilityLabel("上一首")
        .accessibilityIdentifier("miniPlayerPreviousButton")
    }

    private var playPauseButton: some View {
        Button(action: player.togglePlayPause) {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(player.isPlaying ? "暂停" : "播放")
        .accessibilityIdentifier("miniPlayerPlayPauseButton")
    }

    private var nextButton: some View {
        Button(action: player.next) {
            Image(systemName: "forward.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 38, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("下一首")
        .accessibilityIdentifier("miniPlayerNextButton")
    }

    private var moreMenu: some View {
        Menu {
            Button(action: player.previous) {
                Label("上一首", systemImage: "backward.fill")
            }
            .disabled(player.isFMMode)

            Menu {
                Button {
                    if player.shuffleEnabled { player.toggleShuffle() }
                    player.repeatMode = .off
                } label: {
                    Label("顺序播放", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                Button {
                    if !player.shuffleEnabled { player.toggleShuffle() }
                    player.repeatMode = .off
                } label: {
                    Label("随机播放", systemImage: "shuffle")
                }
                Button {
                    if player.shuffleEnabled { player.toggleShuffle() }
                    player.repeatMode = .all
                } label: {
                    Label("列表循环", systemImage: "repeat")
                }
                Button {
                    if player.shuffleEnabled { player.toggleShuffle() }
                    player.repeatMode = .one
                } label: {
                    Label("单曲循环", systemImage: "repeat.1")
                }
            } label: {
                Label("播放模式", systemImage: player.repeatMode == .one ? "repeat.1" : "repeat")
            }

            Button {
                player.presentNowPlaying(startingWith: .lyrics)
            } label: {
                Label("歌词", systemImage: "quote.bubble")
            }

            Button {
                player.presentNowPlaying(startingWith: .queue)
            } label: {
                Label("播放队列", systemImage: "list.bullet")
            }

            Button(action: player.toggleMute) {
                Label(player.isMuted ? "取消静音" : "静音", systemImage: player.isMuted ? "speaker.slash" : "speaker.wave.2")
            }

            Divider()

            Button(role: .destructive, action: player.closeCurrentTrack) {
                Label("关闭播放器", systemImage: "xmark.circle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 38, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("更多控制")
        .accessibilityIdentifier("miniPlayerMoreMenu")
    }
}

private struct IOS15MiniPlayerProgress: View {
    @EnvironmentObject private var player: PlayerService
    /// `PlayerService.progress` proxies this separate ObservableObject. Observe it
    /// directly so the mini-player redraws for AVPlayer time ticks without needing
    /// a navigation change or slider interaction to invalidate the parent view.
    @ObservedObject private var clock = PlayerService.shared.clock

    var body: some View {
        VStack(spacing: 0) {
            Slider(
                value: Binding(
                    get: { min(max(clock.progress, 0), max(player.duration, 1)) },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(player.duration, 1)
            )
            .tint(Theme.accent)
            .controlSize(.small)
            .accessibilityLabel("播放进度")
            .accessibilityValue("\(timeText(clock.progress)) / \(timeText(player.duration))")
            .accessibilityIdentifier("miniPlayerProgress")

            HStack {
                Text(timeText(clock.progress))
                Spacer(minLength: 8)
                Text(timeText(player.duration))
            }
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }

    private func timeText(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private enum IOS15KeyboardDismissal {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
#endif
