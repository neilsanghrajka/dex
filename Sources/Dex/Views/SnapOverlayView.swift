import SwiftUI

struct SnapOverlayView: View {
    @EnvironmentObject private var model: AppModel
    let display: DisplayInfo

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.12))
                .ignoresSafeArea()

            let grid = model.grid(for: display)
            ForEach(grid.roles) { role in
                let localRect = display.localRect(for: grid.rect(for: role))
                let highlighted = model.hoveredSnapRole == role

                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.white.opacity(highlighted ? 0.20 : 0.07))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(
                                    .white.opacity(highlighted ? 0.86 : 0.34),
                                    style: StrokeStyle(lineWidth: highlighted ? 3 : 1.5, dash: [8, 7])
                                )
                        }

                    VStack(spacing: 10) {
                        Image(systemName: iconName(for: role))
                            .font(.system(size: 24, weight: .semibold))
                        Text(highlighted ? "Release to snap \(role.title.lowercased())" : role.title)
                            .font(.headline)
                    }
                    .foregroundStyle(.white.opacity(highlighted ? 0.96 : 0.72))
                }
                .frame(width: localRect.width, height: localRect.height)
                .position(x: localRect.midX, y: localRect.midY)
            }
        }
        .allowsHitTesting(false)
    }

    private func iconName(for role: ColumnRole) -> String {
        switch role {
        case .left: "sidebar.left"
        case .center: "rectangle"
        case .right: "sidebar.right"
        case .topLeft, .topRight: "rectangle.topthird.inset.filled"
        case .bottomLeft, .bottomRight: "rectangle.bottomthird.inset.filled"
        }
    }
}
