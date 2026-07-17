import SwiftUI
import AppKit

/// Popover panel for the ✨ wand button. Rewrite-only — reply suggestions
/// live in the inline `ReplyChipsInline` next to the wand in the toolbar.
struct AIComposerPanel: View {
    let serviceID: String
    @EnvironmentObject private var ai: AIState
    @EnvironmentObject private var store: WebControllerStore
    @Environment(\.dismiss) private var dismiss

    @State private var showingSettings = false
    @State private var feedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s12) {
            header
            draftSection
            styleSection
            if ai.isWorking || !ai.result.isEmpty || ai.lastError != nil {
                resultSection
            }
            if showingSettings {
                Divider()
                settings
            }
        }
        .padding(Theme.s16)
        .frame(width: 360)
        .task { await refreshDraft() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars").foregroundStyle(.purple)
            Text("Rewrite").font(Theme.headline(15))
            Spacer()
            if let fb = feedback {
                Text(fb).font(Theme.caption(10)).foregroundStyle(.green).transition(.opacity)
            }
            Button { showingSettings.toggle() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Configure endpoint")
        }
    }

    private var draftSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("YOUR DRAFT")
            Text(ai.draft.isEmpty ? "Type a message in the chat first, then click a style." : ai.draft)
                .font(Theme.body(12))
                .foregroundStyle(ai.draft.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .glassCard(accent: .white, cornerRadius: 8, accentOpacity: 0.04)
        }
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("STYLE")
            let cols = [GridItem(.adaptive(minimum: 90, maximum: 130), spacing: 6)]
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(RewriteStyle.allCases) { style in
                    StyleChip(label: style.label, icon: style.icon,
                              selected: ai.lastStyle == style,
                              enabled: !ai.draft.isEmpty && !ai.isWorking) {
                        Task { await rewrite(with: style) }
                    }
                }
            }
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("RESULT")
            if let err = ai.lastError {
                Text(err)
                    .font(Theme.caption(11)).foregroundStyle(.red).lineLimit(4)
                    .padding(8)
                    .glassCard(accent: .red, cornerRadius: 8, accentOpacity: 0.08)
            } else if ai.isWorking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Thinking…").font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(accent: .purple, cornerRadius: 8, accentOpacity: 0.06)
            } else {
                Text(ai.result)
                    .font(Theme.body(12)).foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .glassCard(accent: .purple, cornerRadius: 8, accentOpacity: 0.10)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    Button { Task { await applyAndDismiss(text: ai.result) } } label: {
                        Label("Use & Close", systemImage: "arrow.down.to.line")
                            .font(Theme.body(12).weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.purple.gradient))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    Button { copy(ai.result) } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(Theme.body(12))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.strokeBright, lineWidth: 0.5))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button {
                        if let s = ai.lastStyle { Task { await rewrite(with: s) } }
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("ENDPOINT")
            TextField("http://host:8000/v1", text: $ai.endpoint).textFieldStyle(.roundedBorder).font(Theme.mono(11))
            sectionLabel("MODEL")
            TextField("Qwen/Qwen3.6-35B-A3B-FP8", text: $ai.model).textFieldStyle(.roundedBorder).font(Theme.mono(11))
            sectionLabel("API KEY (optional)")
            TextField("not-needed", text: $ai.apiKey).textFieldStyle(.roundedBorder).font(Theme.mono(11))
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
            .tracking(0.6)
    }

    // MARK: - Logic

    private func refreshDraft() async {
        guard let controller = store.existingController(for: serviceID) else { return }
        ai.draft = await controller.readActiveInputText()
    }

    private func rewrite(with style: RewriteStyle) async {
        await refreshDraft()
        let draft = ai.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return }
        ai.lastStyle = style
        ai.isWorking = true
        ai.lastError = nil
        ai.result = ""
        do {
            ai.result = try await AIClient.rewrite(
                endpoint: ai.endpoint, model: ai.model, apiKey: ai.apiKey,
                systemPrompt: style.systemPrompt, userDraft: draft
            )
        } catch {
            ai.lastError = error.localizedDescription
        }
        ai.isWorking = false
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flashFeedback("Copied")
    }

    private func applyAndDismiss(text: String) async {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        dismiss()
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard let controller = store.existingController(for: serviceID) else { return }
        _ = await controller.writeActiveInputText(text)
    }

    private func flashFeedback(_ text: String) {
        withAnimation { feedback = text }
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            withAnimation { feedback = nil }
        }
    }
}

private struct StyleChip: View {
    let label: String
    let icon: String
    let selected: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.purple.opacity(0.9) : Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(selected ? Color.purple.opacity(0.7) : Theme.strokeSubtle, lineWidth: 0.5)
            )
            .foregroundStyle(selected ? .white : Theme.textPrimary)
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
