import SwiftUI

private struct NotchShape: Shape, Animatable {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let maxY = rect.maxY
        let tR = topCornerRadius
        let bR = bottomCornerRadius

        path.move(to: CGPoint(x: minX, y: minY))
        path.addQuadCurve(
            to: CGPoint(x: minX + tR, y: minY + tR),
            control: CGPoint(x: minX + tR, y: minY)
        )
        path.addLine(to: CGPoint(x: minX + tR, y: maxY - bR))
        path.addQuadCurve(
            to: CGPoint(x: minX + tR + bR, y: maxY),
            control: CGPoint(x: minX + tR, y: maxY)
        )
        path.addLine(to: CGPoint(x: maxX - tR - bR, y: maxY))
        path.addQuadCurve(
            to: CGPoint(x: maxX - tR, y: maxY - bR),
            control: CGPoint(x: maxX - tR, y: maxY)
        )
        path.addLine(to: CGPoint(x: maxX - tR, y: minY + tR))
        path.addQuadCurve(
            to: CGPoint(x: maxX, y: minY),
            control: CGPoint(x: maxX - tR, y: minY)
        )
        path.closeSubpath()
        return path
    }
}

enum IslandLayout {
    static let collapsedWidth: CGFloat = 185
    static let collapsedHeight: CGFloat = 32

    static let hintWidth: CGFloat = 270
    static let hintHeight: CGFloat = 50

    static let expandedWidth: CGFloat = 430
    static let expandedHeight: CGFloat = 132

    static let panelWidth: CGFloat = expandedWidth + 24
    static let panelHeight: CGFloat = expandedHeight + 16
}

struct IslandView: View {
    @ObservedObject var store: IslandStateStore

    private static let islandSpring: Animation =
        .spring(response: 0.45, dampingFraction: 0.78, blendDuration: 0)

    private var width: CGFloat {
        switch store.displayState {
        case .collapsed: return IslandLayout.collapsedWidth
        case .hint: return IslandLayout.hintWidth
        case .expanded: return IslandLayout.expandedWidth
        }
    }

    private var height: CGFloat {
        switch store.displayState {
        case .collapsed: return IslandLayout.collapsedHeight
        case .hint: return IslandLayout.hintHeight
        case .expanded: return IslandLayout.expandedHeight
        }
    }

    private var topR: CGFloat {
        switch store.displayState {
        case .collapsed: return 6
        case .hint: return 8
        case .expanded: return 14
        }
    }

    private var bottomR: CGFloat {
        switch store.displayState {
        case .collapsed: return 12
        case .hint: return 16
        case .expanded: return 22
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                NotchShape(topCornerRadius: topR, bottomCornerRadius: bottomR)
                    .fill(Color.black)

                NotchShape(topCornerRadius: topR, bottomCornerRadius: bottomR)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.18),
                                .white.opacity(0.04),
                                .white.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.6
                    )
                    .opacity(store.isHovering ? 1 : 0)

                contentLayer
                    .frame(width: width, height: height, alignment: .top)
                    .clipShape(NotchShape(topCornerRadius: topR, bottomCornerRadius: bottomR))
            }
            .frame(width: width, height: height)
            .contentShape(NotchShape(topCornerRadius: topR, bottomCornerRadius: bottomR))
            .onHover { store.setHovering($0) }
            .onTapGesture {
                if !store.isExpanded {
                    store.expand()
                }
            }
            .contextMenu {
                Button(store.animationsEnabled ? "关闭动画" : "开启动画") {
                    store.toggleAnimations()
                }
                Divider()
                Button("开机启动（即将支持）") {}
                    .disabled(true)
                Button("显示屏选择（即将支持）") {}
                    .disabled(true)
            }
            .compositingGroup()
        }
        .frame(width: IslandLayout.panelWidth, height: IslandLayout.panelHeight, alignment: .top)
        .animation(store.animationsEnabled ? Self.islandSpring : nil, value: store.displayState)
        .animation(store.animationsEnabled ? .easeOut(duration: 0.18) : nil, value: store.isHovering)
        .accessibilityLabel("Dynamic Island")
        .accessibilityAddTraits(.isButton)
    }

    private var contentLayer: some View {
        ZStack {
            collapsedContent
                .opacity(store.isExpanded ? 0 : 1)
                .animation(store.animationsEnabled ? .easeOut(duration: store.isExpanded ? 0.10 : 0.20) : nil,
                           value: store.isExpanded)

            expandedContent
                .opacity(store.isExpanded ? 1 : 0)
                .animation(store.animationsEnabled ? .easeOut(duration: store.isExpanded ? 0.28 : 0.10)
                    .delay(store.isExpanded ? 0.08 : 0) : nil,
                           value: store.isExpanded)
        }
    }

    private var collapsedContent: some View {
        HStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(Color(white: 0.20))
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(white: 0.55, opacity: 0.55), .clear],
                            center: UnitPoint(x: 0.35, y: 0.3),
                            startRadius: 0,
                            endRadius: 5
                        )
                    )
                Circle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 3, height: 3)
                    .offset(x: -1.5, y: -1.5)
            }
            .frame(width: 10, height: 10)
            Spacer().frame(width: 18)
        }
        .frame(height: IslandLayout.collapsedHeight)
        .allowsHitTesting(false)
    }

    private var expandedContent: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.9)
            )
            .overlay {
                VStack(alignment: .leading, spacing: 0) {
                    Text("首页")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 10)
            }
            .overlay {
                Text("首页功能区域（占位）")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 6)
            .padding(.horizontal, 20)
            .padding(.top, 40)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

#Preview("Collapsed") {
    IslandView(store: {
        let s = IslandStateStore()
        s.collapse()
        return s
    }())
    .padding(40)
    .background(
        LinearGradient(
            colors: [Color(red: 0.35, green: 0.52, blue: 0.70),
                     Color(red: 0.20, green: 0.36, blue: 0.56)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}

#Preview("Expanded") {
    IslandView(store: {
        let s = IslandStateStore()
        s.expand()
        return s
    }())
    .padding(40)
    .background(
        LinearGradient(
            colors: [Color(red: 0.35, green: 0.52, blue: 0.70),
                     Color(red: 0.20, green: 0.36, blue: 0.56)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}
