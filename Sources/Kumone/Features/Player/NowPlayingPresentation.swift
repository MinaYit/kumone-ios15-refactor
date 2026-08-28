import SwiftUI

#if os(iOS)
/// 共享播放页布局常量。关闭手势与速度曲线不在此处重写，完全交由系统呈现控制器处理。
enum NowPlayingPresentationMetrics {
    /// 紧凑布局从安全区边缘开始；额外一点间距使胶囊与灵动岛下缘保持稳定留白。
    static let dynamicIslandSafeAreaClearance: CGFloat = 12
    static let indicatorTopSpacing: CGFloat = 1
    static let indicatorToHeaderSpacing: CGFloat = 13
    static let indicatorWidth: CGFloat = 44
    static let indicatorHeight: CGFloat = 5
    static let indicatorHitWidth: CGFloat = 180
    static let indicatorHitHeight: CGFloat = 82
    static let controlsRevealHitHeight: CGFloat = 132
    static let controlsTransitionOffset: CGFloat = 30
    static let controlsTransitionScale: CGFloat = 0.97

    static let controlsLayoutAnimation = Animation.timingCurve(
        0.16, 1, 0.3, 1,
        duration: 0.38
    )
    static let controlsRevealMotionAnimation = Animation.spring(
        response: 0.44,
        dampingFraction: 0.82,
        blendDuration: 0.08
    )
    static let controlsDismissMotionAnimation = Animation.timingCurve(
        0.16, 1, 0.3, 1,
        duration: 0.28
    )
    static let controlsFadeInAnimation = Animation.timingCurve(
        0.16, 1, 0.3, 1,
        duration: 0.24
    )
    static let controlsFadeOutAnimation = Animation.timingCurve(
        0.16, 1, 0.3, 1,
        duration: 0.18
    )

    static let miniPlayerExpandDistance: CGFloat = 28
    static let miniPlayerExpandPrediction: CGFloat = 72

    static var immersiveHeaderTopInset: CGFloat {
        indicatorTopSpacing + indicatorHeight + indicatorToHeaderSpacing
    }

    static var dynamicIslandToIndicatorSpacing: CGFloat {
        dynamicIslandSafeAreaClearance + indicatorTopSpacing
    }

    static func shouldExpandFromMiniPlayer(
        translation: CGFloat,
        predictedTranslation: CGFloat
    ) -> Bool {
        translation < -miniPlayerExpandDistance
            || predictedTranslation < -miniPlayerExpandPrediction
    }

    /// 系统在扩展与内联播放器之间重新托管视图时可能短暂返回 nil；此时保持紧凑布局。
    static func shouldUseInlineMiniPlayerLayout(
        placementIsInline: Bool?
    ) -> Bool {
        placementIsInline ?? true
    }
}

private struct DismissNowPlayingActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    var dismissNowPlayingAction: (() -> Void)? {
        get { self[DismissNowPlayingActionKey.self] }
        set { self[DismissNowPlayingActionKey.self] = newValue }
    }
}

/// 播放页只负责内容和可访问性的关闭入口。它不实现 DragGesture、offset 或手动弹簧，
/// 因此 iOS 15 及更高版本均由系统 sheet 的交互式转场保持原生流畅度。
struct IOSNowPlayingPresentation<Content: View>: View {
    private let mode: NowPlayingMode
    private let content: Content

    @Binding private var isPresented: Bool

    init(
        isPresented: Binding<Bool>,
        mode: NowPlayingMode,
        @ViewBuilder content: () -> Content
    ) {
        _isPresented = isPresented
        self.mode = mode
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                content
                    .environment(\.dismissNowPlayingAction, dismiss)

                if proxy.size.width < 720, mode != .classic {
                    dragIndicator
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var dragIndicator: some View {
        ZStack(alignment: .top) {
            Color.clear

            Capsule()
                .fill(.white.opacity(0.38))
                .frame(
                    width: NowPlayingPresentationMetrics.indicatorWidth,
                    height: NowPlayingPresentationMetrics.indicatorHeight
                )
                .padding(.top, NowPlayingPresentationMetrics.indicatorTopSpacing)
        }
        .frame(
            width: NowPlayingPresentationMetrics.indicatorHitWidth,
            height: NowPlayingPresentationMetrics.indicatorHitHeight
        )
        .accessibilityIdentifier("nowPlayingDismissIndicator")
        .accessibilityLabel("下拉关闭播放页")
        .accessibilityAction(named: Text("关闭播放页"), dismiss)
    }

    private func dismiss() {
        isPresented = false
    }
}
#endif
