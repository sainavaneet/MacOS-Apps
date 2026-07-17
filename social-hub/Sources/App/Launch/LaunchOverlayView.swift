import SwiftUI

struct LaunchOverlayView: View {
    @EnvironmentObject private var loader: LaunchLoader

    var body: some View {
        ZStack {
            AuroraBackground(accent: .purple)
                .ignoresSafeArea()

            VStack(spacing: Theme.s32) {
                Spacer()

                VStack(spacing: 6) {
                    Text("Social Hub")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)

                    Text("Getting your apps ready…")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                }

                HStack(spacing: 18) {
                    ForEach(ServiceCatalog.all) { service in
                        ServiceLoadTile(
                            service: service,
                            progress: loader.progress[service.id] ?? 0,
                            ready: loader.ready.contains(service.id)
                        )
                    }
                }

                ProgressTrack(progress: loader.overallProgress)
                    .frame(width: 320)

                Text("\(loader.readyCount) of \(loader.totalCount) apps ready")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)

                Spacer()
                Spacer()
            }
            .padding(.horizontal, Theme.s32)
        }
    }
}

private struct ServiceLoadTile: View {
    let service: Service
    let progress: Double
    let ready: Bool

    var body: some View {
        VStack(spacing: 10) {
            ServiceIcon(service: service, size: 56)
                .saturation(ready ? 1 : 0.5)
                .opacity(ready ? 1 : 0.7)

            ProgressTrack(progress: progress, accent: service.accent)
                .frame(width: 60)

            Text(service.name)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(ready ? Theme.textPrimary : Theme.textSecondary)
        }
    }
}

private struct ProgressTrack: View {
    var progress: Double
    var accent: Color = .purple
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(accent)
                    .frame(width: max(2, geo.size.width * progress))
            }
        }
        .frame(height: height)
    }
}
