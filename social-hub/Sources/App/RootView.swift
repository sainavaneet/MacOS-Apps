import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    private var showingService: Bool {
        if case .service = appState.selection { return true }
        return false
    }

    var body: some View {
        ZStack {
            AuroraBackground(accent: appState.currentAccent())

            NavigationSplitView {
                SidebarView()
            } detail: {
                ZStack {
                    if showingService {
                        WebHostView()
                    } else if case .home = appState.selection {
                        HomeView()
                    } else if case .inbox = appState.selection {
                        InboxView()
                    }
                }
                .frame(minWidth: 720, minHeight: 480)
                .background(Color.clear)
            }
            .navigationSplitViewStyle(.balanced)
            .scrollContentBackground(.hidden)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    MemoryStatView()
                }
                ToolbarItem(placement: .primaryAction) {
                    ZoomControlsToolbarView()
                }
                ToolbarItem(placement: .primaryAction) {
                    InboxAccessButton()
                }
            }
        }
    }
}
