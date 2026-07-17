import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var feed: NotificationFeed

    private var totalUnread: Int {
        appState.unread.values.reduce(0, +)
    }

    private var todaysCount: Int {
        let cal = Calendar.current
        return feed.all.filter { cal.isDateInToday($0.receivedAt) }.count
    }

    private var lastActivity: Date? {
        feed.all.first?.receivedAt
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s24) {
                header
                statsRow
                bentoGrid
                ActivityTimelineView(notifications: feed.all) { n in
                    appState.selectService(n.serviceID)
                }
            }
            .padding(.horizontal, Theme.s32)
            .padding(.top, Theme.s32)
            .padding(.bottom, Theme.s24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    // MARK: - Header

    private var header: some View {
        TimelineView(.everyMinute) { ctx in
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting(for: ctx.date))
                    .font(Theme.title(32))
                    .foregroundStyle(Theme.textPrimary)
                Text(dateString(for: ctx.date))
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func greeting(for date: Date) -> String {
        let h = Calendar.current.component(.hour, from: date)
        switch h {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Working late?"
        }
    }

    private func dateString(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: date)
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: Theme.s12) {
            StatCard(icon: "envelope.fill",
                     label: "Unread",
                     value: "\(totalUnread)",
                     accent: .pink)
            StatCard(icon: "bell.badge.fill",
                     label: "Today",
                     value: "\(todaysCount)",
                     accent: .cyan)
            StatCard(icon: "clock.fill",
                     label: "Last activity",
                     value: lastActivity.map(Self.relative) ?? "—",
                     accent: .green)
        }
    }

    static func relative(_ date: Date) -> String {
        let d = Date().timeIntervalSince(date)
        if d < 60 { return "now" }
        if d < 3600 { return "\(Int(d / 60))m ago" }
        if d < 86400 { return "\(Int(d / 3600))h ago" }
        return "\(Int(d / 86400))d ago"
    }

    // MARK: - Bento

    private var bentoGrid: some View {
        let cols = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: Theme.s12, alignment: .top)]
        return LazyVGrid(columns: cols, spacing: Theme.s12) {
            ForEach(ServiceCatalog.all) { service in
                AppBentoCard(
                    service: service,
                    unread: appState.unread[service.id] ?? 0,
                    latest: feed.all.first(where: { $0.serviceID == service.id }),
                    onOpen: { appState.selectService(service.id) }
                )
            }
        }
    }
}

private struct StatCard: View {
    let icon: String
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        HStack(spacing: Theme.s12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: Theme.r10, style: .continuous)
                        .fill(accent.gradient)
                )
                .accentGlow(accent, radius: 8, intensity: 0.35)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(Theme.caption(11))
                    .foregroundStyle(Theme.textTertiary)
                Text(value)
                    .font(Theme.headline(20))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
        }
        .padding(Theme.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(accent: accent, cornerRadius: Theme.r10, accentOpacity: 0.08)
    }
}
