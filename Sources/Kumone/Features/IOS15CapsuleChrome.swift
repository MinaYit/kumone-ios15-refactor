#if os(iOS)
import SwiftUI
import UIKit

/// iOS 15 专用的底部悬浮胶囊标签栏。
///
/// 该实现只使用普通 Button，避免使用横向拖拽手势抢占页面列表的滚动。
struct IOS15CapsuleTabBar: View {
    struct Item: Identifiable {
        let id: Int
        let title: LocalizedStringKey
        let icon: String
    }

    let items: [Item]
    @Binding var selection: Int

    @Environment(\.colorScheme) private var colorScheme

    private let contentHeight: CGFloat = 56
    private let innerInset: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let count = max(items.count, 1)
            let itemWidth = proxy.size.width / CGFloat(count)
            let selectedIndex = items.firstIndex { $0.id == selection }

            ZStack(alignment: .leading) {
                if let selectedIndex {
                    Capsule(style: .continuous)
                        .fill(selectionFill)
                        .frame(width: max(0, itemWidth - innerInset * 2), height: contentHeight)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(selectionRim, lineWidth: 0.7)
                                .overlay(alignment: .top) {
                                    Capsule(style: .continuous)
                                        .strokeBorder(.white.opacity(colorScheme == .dark ? 0.14 : 0.48), lineWidth: 0.5)
                                        .mask(
                                            Rectangle()
                                                .frame(height: contentHeight * 0.42)
                                                .frame(maxHeight: .infinity, alignment: .top)
                                        )
                                }
                        }
                        .shadow(
                            color: Theme.accent.opacity(colorScheme == .dark ? 0.30 : 0.18),
                            radius: colorScheme == .dark ? 8 : 6,
                            y: 3
                        )
                        .offset(x: CGFloat(selectedIndex) * itemWidth + innerInset)
                }

                HStack(spacing: 0) {
                    ForEach(items) { item in
                        Button {
                            select(item.id)
                        } label: {
                            label(for: item)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(IOS15CapsuleButtonStyle())
                        .accessibilityLabel(item.title)
                        .accessibilityIdentifier("ios15Tab-\(item.id)")
                        .accessibilityAddTraits(selection == item.id ? .isSelected : [])
                    }
                }
            }
        }
        .frame(height: contentHeight)
        .padding(innerInset)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .fill(glassTint)
                }
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(containerRim, lineWidth: colorScheme == .dark ? 0.9 : 0.65)
                .overlay(alignment: .top) {
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(colorScheme == .dark ? 0.18 : 0.60), lineWidth: 0.7)
                        .mask(
                            Rectangle()
                                .frame(height: contentHeight * 0.38)
                                .frame(maxHeight: .infinity, alignment: .top)
                        )
                }
                .overlay(alignment: .bottom) {
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(colorScheme == .dark ? 0.05 : 0.22), lineWidth: 0.5)
                        .mask(
                            Rectangle()
                                .frame(height: contentHeight * 0.24)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        )
                }
        }
        .clipShape(Capsule(style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.14), radius: 14, y: 5)
        .shadow(color: .white.opacity(colorScheme == .dark ? 0.05 : 0.20), radius: 2, y: -1)
    }

    private func label(for item: Item) -> some View {
        let isSelected = selection == item.id
        return VStack(spacing: 3) {
            Image(systemName: item.icon)
                .font(.system(size: 20, weight: .bold))
                .symbolVariant(.fill)
            Text(item.title)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(unselectedForeground))
    }

    private func select(_ item: Int) {
        guard selection != item else { return }
        selection = item
    }

    private var selectionFill: LinearGradient {
        LinearGradient(
            colors: [
                Theme.accent.opacity(colorScheme == .dark ? 0.48 : 0.30),
                Theme.accent.opacity(colorScheme == .dark ? 0.25 : 0.13),
                .white.opacity(colorScheme == .dark ? 0.06 : 0.15),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var glassTint: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(colorScheme == .dark ? 0.06 : 0.20),
                Theme.accent.opacity(colorScheme == .dark ? 0.08 : 0.045),
                .clear,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var selectionRim: Color {
        Theme.accent.opacity(colorScheme == .dark ? 0.80 : 0.50)
    }

    private var containerRim: Color {
        .white.opacity(colorScheme == .dark ? 0.28 : 0.52)
    }

    private var unselectedForeground: Color {
        .primary.opacity(colorScheme == .dark ? 0.90 : 0.64)
    }
}

/// 参考液态玻璃导航的独立搜索入口：与主胶囊分离，但共享底部基线和材质层级。
struct IOS15LiquidGlassSearchButton: View {
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let contentSize: CGFloat = 56

    var body: some View {
        ZStack {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 25, weight: .bold))
                .foregroundStyle(isSelected ? Theme.accent : .primary.opacity(colorScheme == .dark ? 0.92 : 0.84))
                .frame(width: contentSize, height: contentSize)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle()
                                .fill(searchTint)
                        }
                }
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(colorScheme == .dark ? 0.22 : 0.58), lineWidth: 0.75)
                        .overlay(alignment: .top) {
                            Circle()
                                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.10 : 0.30), lineWidth: 0.5)
                                .mask(
                                    Rectangle()
                                        .frame(height: contentSize * 0.30)
                                        .frame(maxHeight: .infinity, alignment: .top)
                                )
                        }
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.14), radius: 10, y: 4)
                .shadow(color: .white.opacity(colorScheme == .dark ? 0.04 : 0.22), radius: 2, y: -1)

            // 使用 UIKit 原生 touchUpInside 命中层，而非依赖材质视图的 SwiftUI
            // 命中测试。透明层覆盖完整 72×72pt 范围，单击即可进入搜索。
            IOS15NativeSearchTapControl(action: action, isSelected: isSelected)
                .frame(width: 72, height: 72)
        }
        .frame(width: 72, height: 72)
    }

    private var searchTint: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(colorScheme == .dark ? 0.08 : 0.18),
                Theme.accent.opacity(isSelected ? 0.18 : 0.035),
                .black.opacity(colorScheme == .dark ? 0.10 : 0.025),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// 等宽的胶囊式筛选控件，用于替换 iOS 15 上不可定制的系统分段控件。
struct IOS15CapsuleSegmentedControl: View {
    struct Segment: Identifiable {
        let id: Int
        let title: LocalizedStringKey
        let icon: String?
    }

    let segments: [Segment]
    @Binding var selection: Int

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let height: CGFloat = 42
    private let inset: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            let count = max(segments.count, 1)
            let width = proxy.size.width / CGFloat(count)
            let selectedIndex = segments.firstIndex { $0.id == selection } ?? 0

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Theme.accent.opacity(colorScheme == .dark ? 0.30 : 0.14))
                    .frame(width: max(0, width - inset * 2), height: height)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Theme.accent.opacity(colorScheme == .dark ? 0.72 : 0.40), lineWidth: 0.6)
                    }
                    .shadow(color: Theme.accent.opacity(colorScheme == .dark ? 0.24 : 0.13), radius: 5, y: 2)
                    .offset(x: CGFloat(selectedIndex) * width + inset)
                    .animation(selectionAnimation, value: selection)

                HStack(spacing: 0) {
                    ForEach(segments) { segment in
                        Button {
                            select(segment.id)
                        } label: {
                            HStack(spacing: 5) {
                                if let icon = segment.icon {
                                    Image(systemName: icon)
                                        .font(.system(size: 12, weight: .bold))
                                }
                                Text(segment.title)
                                    .font(.system(size: 14, weight: .bold))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .foregroundStyle(
                                selection == segment.id
                                    ? AnyShapeStyle(Theme.accent)
                                    : AnyShapeStyle(.primary.opacity(colorScheme == .dark ? 0.88 : 0.68))
                            )
                        }
                        .buttonStyle(IOS15CapsuleButtonStyle())
                        .accessibilityAddTraits(selection == segment.id ? .isSelected : [])
                    }
                }
            }
        }
        .frame(height: height)
        .padding(inset)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.24 : 0.55), lineWidth: 0.6)
        }
        .clipShape(Capsule(style: .continuous))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 8, y: 3)
    }

    private func select(_ id: Int) {
        guard selection != id else { return }
        IOS15SelectionFeedback.perform()
        withAnimation(selectionAnimation) {
            selection = id
        }
    }

    private var selectionAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.84)
    }
}

/// 将搜索入口的完整矩形命中范围交给 UIKit 原生 `touchUpInside` 处理。
/// 不使用自定义拖拽或同时手势，避免与底部安全区及相邻胶囊发生竞争。
private struct IOS15NativeSearchTapControl: UIViewRepresentable {
    let action: () -> Void
    let isSelected: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> UIControl {
        let control = UIControl(frame: .zero)
        control.backgroundColor = .clear
        control.isExclusiveTouch = true
        control.isAccessibilityElement = true
        control.accessibilityLabel = "搜索"
        control.accessibilityIdentifier = "ios15LiquidGlassSearchButton"
        control.addTarget(context.coordinator, action: #selector(Coordinator.performAction), for: .touchUpInside)
        return control
    }

    func updateUIView(_ uiView: UIControl, context: Context) {
        context.coordinator.action = action
        uiView.accessibilityTraits = isSelected ? [.button, .selected] : [.button]
        uiView.accessibilityValue = isSelected ? "已选中" : "未选中"
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }
}

private struct IOS15CapsuleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.80 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

enum IOS15SelectionFeedback {
    static func perform() {
        let feedback = UISelectionFeedbackGenerator()
        feedback.prepare()
        feedback.selectionChanged()
    }
}

/// 防止从其他应用返回时过期的键盘帧继续参与 SwiftUI 布局。
final class IOS15KeyboardState: ObservableObject {
    @Published private(set) var overlap: CGFloat = 0

    /// 小于该阈值的变化通常是安全区或候选栏波动，不应影响底部导航显示。
    var isVisible: Bool { overlap > 20 }

    private var observers: [NSObjectProtocol] = []

    init(notificationCenter: NotificationCenter = .default) {
        observers = [
            notificationCenter.addObserver(
                forName: UIResponder.keyboardWillChangeFrameNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.update(from: notification)
            },
            notificationCenter.addObserver(
                forName: UIResponder.keyboardWillHideNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.reset()
            },
            notificationCenter.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.resetForSceneDeactivation()
            },
            notificationCenter.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.resetForSceneActivation()
            }
        ]
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// 失活时立即丢弃当前重叠值，避免其他应用的键盘帧让底部 chrome 保持隐藏。
    func resetForSceneDeactivation() {
        reset()
    }

    /// 应用恢复前台时先清空旧状态。延迟一次主线程检查，覆盖系统在切换应用后
    /// 异步送达的旧键盘帧；本应用文本输入仍会通过本地焦点的通知重新写入。
    func resetForSceneActivation() {
        reset()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.resetUnlessLocallyEditing()
        }
    }

    private func update(from notification: Notification) {
        let isLocalKeyboard = (notification.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? NSNumber)?.boolValue ?? true
        guard isLocalKeyboard,
              UIApplication.shared.applicationState == .active,
              let window = activeWindow,
              hasFirstResponder(in: window),
              let endFrameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
            reset()
            return
        }

        let endFrame = window.convert(endFrameValue.cgRectValue, from: nil)
        let newOverlap = max(0, window.bounds.maxY - endFrame.minY)
        overlap = min(newOverlap, window.bounds.height)
    }

    private func resetUnlessLocallyEditing() {
        guard let window = activeWindow, hasFirstResponder(in: window) else {
            reset()
            return
        }
    }

    private func reset() {
        overlap = 0
    }

    private var activeWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .windows
            .first(where: \.isKeyWindow)
    }

    private func hasFirstResponder(in view: UIView) -> Bool {
        if view.isFirstResponder { return true }
        return view.subviews.contains { hasFirstResponder(in: $0) }
    }
}
#endif
