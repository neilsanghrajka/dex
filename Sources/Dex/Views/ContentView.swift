import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 22) {
            if let logo = BrandAssets.logoImage() {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                Image(systemName: "rectangle.split.3x1")
                    .font(.system(size: 64, weight: .semibold))
            }

            VStack(spacing: 8) {
                Text("Dex")
                    .font(.largeTitle.weight(.semibold))
                Text("Arrange your current desktop into passive left, main center, and passive right.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            PermissionPanel()

            HStack(spacing: 12) {
                Button {
                    Task { await model.showArrangeBoard() }
                } label: {
                    Label("Arrange Board", systemImage: "rectangle.3.group")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await model.arrangeNow() }
                } label: {
                    Label("Arrange Now", systemImage: "sparkles")
                }
            }

            Toggle("Arrange all displays", isOn: $model.arrangeAllDisplays)
                .toggleStyle(.switch)
                .frame(width: 220)
        }
        .padding(34)
        .overlay(alignment: .bottom) {
            if let hudText = model.hudText {
                Text(hudText)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.72), in: Capsule())
                    .padding(.bottom, 20)
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }
}
