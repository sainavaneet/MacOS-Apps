import SwiftUI
import AppKit

struct HubView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var selectedAppID: String?

    var body: some View {
        NavigationSplitView {
            // Sidebar - Apps list
            VStack(spacing: 0) {
                HStack {
                    Text("Apps")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                Divider()

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(SubApp.all) { app in
                            SubAppRow(
                                app: app,
                                isSelected: selectedAppID == app.id,
                                onOpen: {
                                    selectedAppID = app.id
                                    openOrFocusWindow(id: app.windowID)
                                }
                            )
                        }
                    }
                    .padding(8)
                }

                Spacer()
            }
            .frame(minWidth: 200)
            .background(Color(.controlBackgroundColor).opacity(0.3))
        } detail: {
            VStack {
                Text("Select an app from the sidebar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.textBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func openOrFocusWindow(id: String) {
        let windowTitle = SubApp.all.first(where: { $0.windowID == id })?.name ?? id
        for window in NSApplication.shared.windows {
            if window.title == windowTitle {
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
        openWindow(id: id)
    }
}

private struct SubAppRow: View {
    let app: SubApp
    let isSelected: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(app.color.gradient)
                        .frame(width: 32, height: 32)
                    Image(systemName: app.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 12, weight: .medium))
                    Text(app.description)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                } else {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.1) : Color.primary.opacity(0.04))
        )
    }
}

#Preview {
    HubView()
}
