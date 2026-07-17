import SwiftUI

/// Toolbar button that opens the AI rewrite popover. Only meaningful on
/// chat-capable services (services where there's an input to rewrite).
struct AIComposerButton: View {
    let service: Service
    @State private var showing = false

    private static let supported: Set<String> = [
        "whatsapp", "messenger", "telegram", "instagram", "tinder", "snapchat"
    ]
    private var supported: Bool { Self.supported.contains(service.id) }

    var body: some View {
        if supported {
            Button {
                showing.toggle()
            } label: {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(LinearGradient(colors: [.purple, .pink],
                                                 startPoint: .topLeading,
                                                 endPoint: .bottomTrailing))
                    )
                    .accentGlow(.purple, radius: 6, intensity: 0.4)
            }
            .buttonStyle(.plain)
            .help("Rewrite my draft with AI")
            .popover(isPresented: $showing, arrowEdge: .top) {
                AIComposerPanel(serviceID: service.id)
            }
        }
    }
}
