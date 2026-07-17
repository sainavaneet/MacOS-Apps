import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var feed: NotificationFeed

    @FocusState private var searchFocused: Bool
    @State private var query: String = ""
    @State private var filterService: String? = nil

    private var filtered: [InAppNotification] {
        feed.all.filter { n in
            if let f = filterService, n.serviceID != f { return false }
            if !query.isEmpty {
                let q = query.lowercased()
                if !n.title.lowercased().contains(q) && !n.body.lowercased().contains(q) {
                    return false
                }
            }
            return true
        }
    }

    private var perServiceCounts: [String: Int] {
        Dictionary(grouping: feed.all, by: \.serviceID).mapValues { $0.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            chips
            divider

            if filtered.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(filtered, id: \.id) { n in
                            NotificationRow(
                                notification: n,
                                onTap: { appState.selectService(n.serviceID) },
                                onDelete: { feed.remove(n.id) }
                            )
                        }
                    }
                    .padding(.horizontal, Theme.s24)
                    .padding(.vertical, Theme.s12)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .onAppear { feed.markInboxSeen() }
    }

    private var divider: some View {
        LinearGradient(
            colors: [Theme.strokeSubtle.opacity(0), Theme.strokeBright, Theme.strokeSubtle.opacity(0)],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 1)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Inbox")
                    .font(Theme.title(26))
                    .foregroundStyle(Theme.textPrimary)
                Text(feed.all.isEmpty
                     ? "Notifications from all your apps"
                     : "\(feed.all.count) notification\(feed.all.count == 1 ? "" : "s")")
                    .font(Theme.caption(11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            searchField
            if !feed.all.isEmpty {
                Button("Clear") { withAnimation { feed.clearAll() } }
                    .font(Theme.body(12))
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, Theme.s24)
        .padding(.top, Theme.s24)
        .padding(.bottom, Theme.s12)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.body(12))
                .foregroundStyle(Theme.textPrimary)
                .focused($searchFocused)
                .frame(width: 170)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule().strokeBorder(
                searchFocused ? Color.purple.opacity(0.6) : Theme.strokeSubtle,
                lineWidth: searchFocused ? 1.0 : 0.5
            )
        )
        .accentGlow(.purple, radius: searchFocused ? 10 : 0, intensity: searchFocused ? 0.35 : 0)
        .animation(Theme.springQuick, value: searchFocused)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterChip(label: "All",
                           icon: "tray",
                           accent: .gray,
                           count: feed.all.count,
                           selected: filterService == nil) {
                    withAnimation(Theme.springQuick) { filterService = nil }
                }
                ForEach(ServiceCatalog.all) { s in
                    let count = perServiceCounts[s.id] ?? 0
                    if count > 0 {
                        FilterChip(label: s.name,
                                   icon: s.sfSymbol,
                                   accent: s.accent,
                                   count: count,
                                   selected: filterService == s.id) {
                            withAnimation(Theme.springQuick) {
                                filterService = filterService == s.id ? nil : s.id
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.s24)
            .padding(.bottom, Theme.s12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: feed.all.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.textTertiary)
                .symbolEffect(.bounce, options: .nonRepeating)
            Text(feed.all.isEmpty ? "No notifications yet" : "No results")
                .font(Theme.headline(14))
                .foregroundStyle(Theme.textSecondary)
            Text(feed.all.isEmpty
                 ? "Messages from your apps will appear here"
                 : "Try a different search or filter")
                .font(Theme.caption(11))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FilterChip: View {
    let label: String
    let icon: String
    let accent: Color
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(selected ? Color.white.opacity(0.25) : Color.white.opacity(0.10))
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(selected ? accent : Color.white.opacity(0.06))
            )
            .overlay(
                Capsule().strokeBorder(selected ? accent.opacity(0.7) : Theme.strokeSubtle, lineWidth: 0.8)
            )
            .accentGlow(accent, radius: selected ? 10 : 0, intensity: selected ? 0.55 : 0)
            .foregroundStyle(selected ? .white : Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

private struct NotificationRow: View {
    let notification: InAppNotification
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    private var service: Service? { ServiceCatalog.service(id: notification.serviceID) }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                // Accent edge bar
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(service?.accent ?? .gray)
                    .frame(width: 3)
                    .padding(.vertical, 4)

                NotificationAvatar(avatarURL: notification.avatarURL, service: service, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(notification.title)
                            .font(Theme.headline(13))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(timeString(notification.receivedAt))
                            .font(Theme.caption(11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if !notification.body.isEmpty {
                        Text(notification.body)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    if let s = service {
                        HStack(spacing: 4) {
                            Circle().fill(s.accent).frame(width: 4, height: 4)
                            Text(s.name)
                                .font(Theme.caption(10))
                                .foregroundStyle(s.accent)
                        }
                    }
                }
                Spacer(minLength: 0)

                if hovering {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassCard(accent: service?.accent ?? .white,
                       cornerRadius: Theme.r10,
                       accentOpacity: hovering ? 0.10 : 0.04)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.springQuick, value: hovering)
    }

    private func timeString(_ date: Date) -> String {
        let delta = Date().timeIntervalSince(date)
        if delta < 60 { return "now" }
        if delta < 3600 { return "\(Int(delta / 60))m" }
        if delta < 86400 { return "\(Int(delta / 3600))h" }
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .none
        return f.string(from: date)
    }
}
