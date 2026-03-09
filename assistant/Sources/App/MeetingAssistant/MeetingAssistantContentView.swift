import SwiftUI
import AppKit

struct MeetingAssistantContentView: View {
    @EnvironmentObject private var microphoneManager: MicrophoneManager
    @EnvironmentObject private var speechEngine: SpeechEngine
    @EnvironmentObject private var chatManager: ChatManager
    @EnvironmentObject private var sessionManager: SessionManager

    private let autoSaveTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            SidebarView(
                onNewChat: newChat,
                onLoadSession: loadSession
            )
                .environmentObject(sessionManager)
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            ChatView(onNewChat: newChat)
                .environmentObject(microphoneManager)
                .environmentObject(speechEngine)
                .environmentObject(chatManager)
        }
        .onChange(of: microphoneManager.selectedMicrophoneID) { _, newValue in
            speechEngine.reconnect(microphoneID: newValue)
            UserDefaults.standard.set(newValue, forKey: "default_microphone_id")
        }
        .task {
            if chatManager.autoConnectMCP && !chatManager.mcpConnected {
                await chatManager.connectMCP()
            }
        }
        .onChange(of: speechEngine.transcript) { _, newValue in
            chatManager.checkForQuestions(transcript: newValue)
        }
        .onChange(of: chatManager.messages.count) { _, _ in
            saveCurrentSession()
        }
        .onReceive(autoSaveTimer) { _ in
            saveCurrentSession()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appWillTerminate)) { _ in
            saveCurrentSession()
        }
    }

    // MARK: - Session Orchestration

    private func saveCurrentSession() {
        guard !chatManager.messages.isEmpty else { return }

        if let sessionID = sessionManager.currentSessionID,
           var session = sessionManager.load(id: sessionID) {
            session.messages = chatManager.messages
            session.transcript = speechEngine.transcript
            session.lastProcessedTranscriptLength = chatManager.lastProcessedTranscriptLength
            sessionManager.save(session: session)
        } else if sessionManager.currentSessionID == nil {
            let title = generateTitle(from: chatManager.messages)
            let session = ChatSession(
                title: title,
                messages: chatManager.messages,
                transcript: speechEngine.transcript,
                lastProcessedTranscriptLength: chatManager.lastProcessedTranscriptLength
            )
            sessionManager.save(session: session)
            sessionManager.currentSessionID = session.id
        }
    }

    private func newChat() {
        saveCurrentSession()
        chatManager.clearChat()
        speechEngine.clearTranscript()
        sessionManager.currentSessionID = nil
    }

    private func loadSession(id: UUID) {
        saveCurrentSession()
        guard let session = sessionManager.load(id: id) else { return }
        chatManager.loadSession(
            messages: session.messages,
            lastProcessedTranscriptLength: session.lastProcessedTranscriptLength
        )
        speechEngine.loadTranscript(session.transcript)
        sessionManager.currentSessionID = id
    }

    private func generateTitle(from messages: [ChatMessage]) -> String {
        if let firstUser = messages.first(where: { $0.role == .user }) {
            let content = firstUser.content
            let truncated = String(content.prefix(50))
            return truncated.count < content.count ? truncated + "..." : truncated
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return "Session \(formatter.string(from: Date()))"
    }
}

// MARK: - Sidebar (Sessions Only)

private struct SidebarView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @EnvironmentObject private var chatManager: ChatManager

    let onNewChat: () -> Void
    let onLoadSession: (UUID) -> Void

    @State private var renamingSessionID: UUID?
    @State private var renameText: String = ""
    @State private var showCreateFolder = false
    @State private var newFolderName = ""
    @State private var expandedFolders: Set<UUID> = []

    // Clipboard state for copy/move operations
    @State private var clipboardSessionId: UUID?
    @State private var clipboardMode: ClipboardMode = .none

    enum ClipboardMode {
        case none
        case copy
        case move
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 28, height: 28)
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text("Chats")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button(action: onNewChat) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("New Chat")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Divider()

            // Sessions list with folders
            if sessionManager.sessions.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 24))
                        .foregroundStyle(.quaternary)
                    Text("No conversations yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2, pinnedViews: [.sectionHeaders]) {
                        // New Chats section
                        let newChats = sessionManager.sessions.filter { session in
                            chatManager.folderManager.getFolder(for: session.id) == nil
                        }

                        if !newChats.isEmpty {
                            Section(header: newChatsHeader()) {
                                ForEach(newChats) { summary in
                                    sessionRowWithContextMenu(summary: summary)
                                }
                            }
                        }

                        // Folders
                        ForEach(chatManager.folderManager.folders) { folder in
                            let folderChats = sessionManager.sessions.filter { folder.sessionIds.contains($0.id) }
                            let isExpanded = expandedFolders.contains(folder.id)

                            Section(header: folderHeader(name: folder.name, isExpanded: isExpanded, onToggle: {
                                if expandedFolders.contains(folder.id) {
                                    expandedFolders.remove(folder.id)
                                } else {
                                    expandedFolders.insert(folder.id)
                                }
                            }, folder: folder)) {
                                if isExpanded {
                                    if folderChats.isEmpty {
                                        Text("No chats yet")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.tertiary)
                                            .padding(.vertical, 8)
                                    } else {
                                        ForEach(folderChats) { summary in
                                            sessionRowWithContextMenu(summary: summary)
                                        }
                                    }
                                }
                            }
                        }

                    }
                    .padding(0)
                }
            }
        }
        .background(Color(.windowBackgroundColor))
        .contextMenu {
            Button(action: onNewChat) {
                Label("New Chat", systemImage: "square.and.pencil")
            }

            Button(action: { showCreateFolder = true }) {
                Label("Create Folder", systemImage: "folder.badge.plus")
            }
        }
        .sheet(isPresented: $showCreateFolder) {
            VStack(spacing: 12) {
                Text("Create New Folder")
                    .font(.system(size: 14, weight: .semibold))

                TextField("Folder name", text: $newFolderName)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Cancel") { showCreateFolder = false }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Create") {
                        if !newFolderName.trimmingCharacters(in: .whitespaces).isEmpty {
                            chatManager.folderManager.createFolder(name: newFolderName)
                            // Auto-expand the newly created folder
                            if let newFolder = chatManager.folderManager.folders.last {
                                expandedFolders.insert(newFolder.id)
                            }
                            newFolderName = ""
                            showCreateFolder = false
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .frame(minWidth: 300)
        }
    }

    private func newChatsHeader() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 11))
                .foregroundStyle(.blue)

            Text("New Chats")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            // Paste button for New Chats section
            if clipboardSessionId != nil && clipboardMode != .none {
                Menu {
                    Button(action: {
                        if let sessionId = clipboardSessionId {
                            if clipboardMode == .move {
                                chatManager.folderManager.removeSessionFromAllFolders(sessionId: sessionId)
                            }
                            clipboardSessionId = nil
                            clipboardMode = .none
                        }
                    }) {
                        Label("Paste", systemImage: "clipboard")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .menuStyle(.borderlessButton)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }

    private func sessionRowWithContextMenu(summary: ChatSessionSummary) -> some View {
        SessionRow(
            summary: summary,
            isActive: summary.id == sessionManager.currentSessionID,
            isRenaming: renamingSessionID == summary.id,
            renameText: $renameText,
            onSelect: { onLoadSession(summary.id) },
            onDelete: { sessionManager.delete(id: summary.id) },
            onRenameStart: {
                renamingSessionID = summary.id
                renameText = summary.title
            },
            onRenameCommit: {
                sessionManager.rename(id: summary.id, to: renameText)
                renamingSessionID = nil
            }
        )
        .contextMenu {
            Button(action: {
                clipboardSessionId = summary.id
                clipboardMode = .copy
            }) {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Button(action: {
                clipboardSessionId = summary.id
                clipboardMode = .move
            }) {
                Label("Move", systemImage: "arrow.right.doc.on.clipboard")
            }
        }
    }

    private func folderHeader(name: String, isExpanded: Bool, onToggle: (() -> Void)? = nil, folder: ChatFolder? = nil) -> some View {
        HStack(spacing: 8) {
            if let onToggle = onToggle {
                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)

            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer()

            if let folder = folder {
                Menu {
                    // Paste option
                    if clipboardSessionId != nil && clipboardMode != .none {
                        Button(action: {
                            if let sessionId = clipboardSessionId {
                                if clipboardMode == .move {
                                    chatManager.folderManager.removeSessionFromAllFolders(sessionId: sessionId)
                                }
                                chatManager.folderManager.addSessionToFolder(sessionId: sessionId, folderId: folder.id)
                                clipboardSessionId = nil
                                clipboardMode = .none
                            }
                        }) {
                            Label("Paste", systemImage: "clipboard")
                        }

                        Divider()
                    }

                    Button("Delete", role: .destructive) {
                        chatManager.folderManager.deleteFolder(id: folder.id)
                        expandedFolders.remove(folder.id)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .menuStyle(.borderlessButton)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }
}

// MARK: - Chat View

private struct ChatView: View {
    @EnvironmentObject private var microphoneManager: MicrophoneManager
    @EnvironmentObject private var speechEngine: SpeechEngine
    @EnvironmentObject private var chatManager: ChatManager

    let onNewChat: () -> Void

    @State private var inputText = ""
    @State private var showSettings = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if chatManager.messages.isEmpty {
                            emptyState
                        }

                        ForEach(chatManager.messages.filter { $0.role != .toolResult }) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        // Pending file operations
                        ForEach(chatManager.fileOperationManager.pendingOperations) { operation in
                            FileOperationBubble(
                                operation: operation,
                                onApprove: {
                                    Task {
                                        await chatManager.fileOperationManager.approveOperation(operation)
                                    }
                                },
                                onReject: {
                                    chatManager.fileOperationManager.rejectOperation(operation)
                                }
                            )
                            .id("file_\(operation.id)")
                        }

                        // Pending commands
                        ForEach(chatManager.commandExecutor.pendingCommands) { command in
                            CommandOutputBubble(
                                command: command,
                                onApprove: {
                                    Task {
                                        await chatManager.commandExecutor.approveCommand(command)
                                    }
                                },
                                onReject: {
                                    chatManager.commandExecutor.rejectCommand(command)
                                }
                            )
                            .id("cmd_\(command.id)")
                        }

                        if chatManager.isLoading {
                            TypingIndicator()
                                .id("loading")
                        }
                    }
                    .padding(24)
                }
                .onChange(of: chatManager.messages.count) { _, _ in
                    if let last = chatManager.messages.last(where: { $0.role != .toolResult }) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: chatManager.isLoading) { _, loading in
                    if loading {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("loading", anchor: .bottom)
                        }
                    }
                }
            }

            // Compact transcript (when recording, has partial, or has pending manual transcript)
            if speechEngine.isListening || !speechEngine.partialTranscript.isEmpty || (!chatManager.autoAnswer && hasPendingTranscript) {
                compactTranscript
            }

            Divider()

            // Input bar with mic button
            inputBar
        }
        .background(Color(.textBackgroundColor))
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // Model picker
                Menu {
                    ForEach(ChatManager.availableModels, id: \.id) { model in
                        Button(action: { chatManager.model = model.id }) {
                            HStack {
                                Text(model.name)
                                if chatManager.model == model.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 11))
                        Text(currentModelName)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Select Claude model")

                Divider()

                // Mic toggle
                Button(action: toggleListening) {
                    Image(systemName: speechEngine.isListening ? "mic.fill" : "mic.slash")
                        .font(.system(size: 13))
                        .foregroundStyle(speechEngine.isListening ? .red : .secondary)
                }
                .help(speechEngine.isListening ? "Stop Recording" : "Start Recording")

                // Recording time
                if speechEngine.isListening {
                    Text(formattedTime(speechEngine.elapsedTime))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.red)
                }

                Divider()

                // Auto-answer toggle
                Button(action: { chatManager.autoAnswer.toggle() }) {
                    Image(systemName: chatManager.autoAnswer ? "sparkles" : "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(chatManager.autoAnswer ? .purple : .secondary)
                }
                .help(chatManager.autoAnswer ? "Auto-answer: ON" : "Auto-answer: OFF")

                // MCP toggle
                Button(action: {
                    Task {
                        if chatManager.mcpConnected {
                            chatManager.disconnectMCP()
                        } else {
                            await chatManager.connectMCP()
                        }
                    }
                }) {
                    Image(systemName: chatManager.mcpConnected ? "bolt.fill" : "bolt.slash")
                        .font(.system(size: 12))
                        .foregroundStyle(chatManager.mcpConnected ? .green : .secondary)
                }
                .help(chatManager.mcpConnected ? "MCP Connected" : "Connect MCP")

                Divider()

                // File editing mode toggle
                if chatManager.fileEditingEnabled {
                    Menu {
                        ForEach(OperationMode.allCases, id: \.rawValue) { mode in
                            Button(action: { chatManager.operationMode = mode.rawValue }) {
                                HStack {
                                    Image(systemName: mode.icon)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.displayName)
                                            .font(.system(size: 11, weight: .semibold))
                                        Text(mode.description)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                    if chatManager.operationMode == mode.rawValue {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: currentModeIcon)
                                .font(.system(size: 11))
                            Text(currentModeName)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Operation Mode: \(currentModeName)")

                    Divider()
                }

                // Selected mic name
                HStack(spacing: 3) {
                    Image(systemName: "mic.badge.plus")
                        .font(.system(size: 10))
                    Text(microphoneManager.selectedMicrophoneName)
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                .help("Selected microphone")

                Divider()

                // Settings
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                }
                .help("Settings")
                .sheet(isPresented: $showSettings) {
                    SettingsSheet()
                        .environmentObject(chatManager)
                        .environmentObject(microphoneManager)
                        .environmentObject(speechEngine)
                }

                // Clear chat
                Button(action: onNewChat) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                }
                .help("Clear chat")
                .disabled(chatManager.messages.isEmpty)
            }
        }
    }

    // MARK: - Compact Transcript

    private var compactTranscript: some View {
        HStack(spacing: 8) {
            // Waveform mini bars
            HStack(spacing: 1.5) {
                ForEach(0..<12, id: \.self) { i in
                    MiniWaveformBar(
                        index: i,
                        audioLevel: speechEngine.audioLevel,
                        isListening: speechEngine.isListening
                    )
                }
            }
            .frame(width: 36, height: 18)

            // Live text / pending transcript info
            if !speechEngine.partialTranscript.isEmpty {
                Text(speechEngine.partialTranscript)
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
                    .italic()
                    .lineLimit(2)
            } else if !chatManager.autoAnswer && hasPendingTranscript {
                let pendingText = String(speechEngine.transcript.dropFirst(chatManager.lastProcessedTranscriptLength))
                let lineCount = pendingText.components(separatedBy: "\n").filter { !$0.isEmpty }.count
                Text("\(lineCount) line\(lineCount == 1 ? "" : "s") queued")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.purple)
            } else if let lastLine = recentTranscriptLines.last {
                Text(stripTimestamp(lastLine))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !speechEngine.transcript.isEmpty {
                Button(action: copyTranscript) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy transcript")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(.windowBackgroundColor).opacity(0.6))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.2), value: speechEngine.isListening)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // Mic button
            Button(action: toggleListening) {
                ZStack {
                    Circle()
                        .fill(speechEngine.isListening ? Color.red.opacity(0.15) : Color(.controlBackgroundColor).opacity(0.5))
                        .frame(width: 34, height: 34)

                    Image(systemName: speechEngine.isListening ? "mic.fill" : "mic")
                        .font(.system(size: 14))
                        .foregroundStyle(speechEngine.isListening ? .red : .secondary)
                }
            }
            .buttonStyle(.plain)
            .help(speechEngine.isListening ? "Stop" : "Record")
            .padding(.bottom, 1)

            TextField("Ask a question...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...8)
                .focused($inputFocused)
                .onSubmit {
                    sendMessage()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.controlBackgroundColor).opacity(0.5))
                )

            // Send button — sends typed text, or pending transcript if input is empty
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        canSend
                            ? AnyShapeStyle(LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom))
                            : AnyShapeStyle(Color(.separatorColor))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend || chatManager.isLoading)
            .padding(.bottom, 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.windowBackgroundColor).opacity(0.8))
        .background(.ultraThinMaterial)
    }

    // Settings popover removed — now using SettingsSheet

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue.opacity(0.1), .purple.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)

                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }

            VStack(spacing: 6) {
                Text("Start a conversation")
                    .font(.system(size: 16, weight: .semibold))

                Text("Type below or tap the mic to record")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Helpers

    private var recentTranscriptLines: [String] {
        speechEngine.transcript.components(separatedBy: "\n").filter { !$0.isEmpty }.suffix(3).map { String($0) }
    }

    private func stripTimestamp(_ line: String) -> String {
        if let bracket = line.range(of: "] "), line.hasPrefix("[") {
            return String(line[bracket.upperBound...])
        }
        return line
    }

    private var hasPendingTranscript: Bool {
        speechEngine.transcript.count > chatManager.lastProcessedTranscriptLength
    }

    private func sendPendingTranscript() {
        Task {
            await chatManager.sendPendingTranscript(transcript: speechEngine.transcript)
        }
    }

    private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(speechEngine.transcript, forType: .string)
    }

    private func toggleListening() {
        speechEngine.toggleListening(microphoneID: microphoneManager.selectedMicrophoneID)
    }

    private func formattedTime(_ interval: TimeInterval) -> String {
        let m = Int(interval) / 60
        let s = Int(interval) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var currentModelName: String {
        ChatManager.availableModels.first(where: { $0.id == chatManager.model })?.name ?? "Haiku 4.5"
    }

    private var currentModeName: String {
        if let mode = OperationMode(rawValue: chatManager.operationMode) {
            return mode.displayName
        }
        return "Permissions"
    }

    private var currentModeIcon: String {
        if let mode = OperationMode(rawValue: chatManager.operationMode) {
            return mode.icon
        }
        return "checkmark.square"
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty || (!chatManager.autoAnswer && hasPendingTranscript)
    }

    private func sendMessage() {
        let hasTypedText = !inputText.trimmingCharacters(in: .whitespaces).isEmpty

        if hasTypedText {
            let text = inputText
            inputText = ""
            Task {
                await chatManager.send(text, transcript: speechEngine.transcript)
            }
        } else if !chatManager.autoAnswer && hasPendingTranscript {
            sendPendingTranscript()
        }
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            // Role label with source icon
            HStack(spacing: 5) {
                if message.role == .user {
                    Image(systemName: message.source == .speech ? "mic.fill" : "keyboard")
                        .font(.system(size: 8))
                        .foregroundStyle(message.source == .speech ? .red.opacity(0.6) : .blue.opacity(0.6))
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                        .foregroundStyle(.purple)
                }

                Text(message.role == .user ? "You" : "Claude")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(timeString(message.timestamp))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            // Content
            if !message.content.isEmpty {
                if message.role == .user {
                    Text(message.content)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue, Color.blue.opacity(0.85)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .frame(maxWidth: 420, alignment: .trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contextMenu {
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(message.content, forType: .string)
                            }
                        }
                } else {
                    MarkdownText(message.content)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.controlBackgroundColor))
                                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contextMenu {
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(message.content, forType: .string)
                            }
                        }
                }
            }

            // Tool calls
            if !message.toolCalls.isEmpty {
                VStack(spacing: 6) {
                    ForEach(message.toolCalls) { tool in
                        ToolCallView(tool: tool)
                    }
                }
            }
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Tool Call View

private struct ToolCallView: View {
    let tool: ToolCall
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.spring(response: 0.25)) { expanded.toggle() } }) {
                HStack(spacing: 7) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 20, height: 20)

                        Image(systemName: tool.isLoading ? "arrow.triangle.2.circlepath" : "wrench.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.orange)
                            .rotationEffect(tool.isLoading ? .degrees(360) : .zero)
                            .animation(
                                tool.isLoading
                                    ? .linear(duration: 1).repeatForever(autoreverses: false)
                                    : .default,
                                value: tool.isLoading
                            )
                    }

                    Text(tool.name)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)

                    if tool.isLoading {
                        Text("running...")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if expanded, let result = tool.result {
                Divider()
                    .padding(.horizontal, 10)

                ScrollView {
                    Text(result)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 150)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 9))
                .foregroundStyle(.purple.opacity(0.5))

            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(
                        LinearGradient(colors: [.blue.opacity(0.5), .purple.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 6, height: 6)
                    .offset(y: sin(phase + Double(i) * 0.8) * 3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.controlBackgroundColor))
                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        )
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

// MARK: - Session Row

private struct SessionRow: View {
    let summary: ChatSessionSummary
    let isActive: Bool
    let isRenaming: Bool
    @Binding var renameText: String
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onRenameStart: () -> Void
    let onRenameCommit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if isRenaming {
                TextField("Session name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit { onRenameCommit() }
            } else {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(isActive ? .blue : .secondary.opacity(0.5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title)
                        .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                        .lineLimit(1)
                        .foregroundStyle(isActive ? .primary : .secondary)

                    HStack(spacing: 4) {
                        Text(relativeDate(summary.lastModifiedAt))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)

                        Text("\(summary.messageCount) msgs")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.blue.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .contextMenu {
            Button("Rename") { onRenameStart() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Mini Waveform Bar

private struct MiniWaveformBar: View {
    let index: Int
    let audioLevel: Float
    let isListening: Bool

    @State private var idlePhase: Double = 0

    var body: some View {
        let variance = sin(Double(index) * 0.9 + idlePhase * 3) * 0.3 + 0.7
        let activeHeight = max(0.1, CGFloat(audioLevel) * CGFloat(variance))
        let heightFraction = isListening ? activeHeight : 0.08

        RoundedRectangle(cornerRadius: 1)
            .fill(isListening ? Color.blue.opacity(0.6) : Color.blue.opacity(0.15))
            .frame(height: max(2, heightFraction * 16))
            .animation(.spring(response: 0.1, dampingFraction: 0.6), value: audioLevel)
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: true)) {
                    idlePhase = 1
                }
            }
    }
}

// MARK: - Pulsing Dot

private struct PulsingDot: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.3))
                .frame(width: 12, height: 12)
                .scaleEffect(pulsing ? 1.3 : 0.8)

            Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}

// MARK: - Markdown Text

/// Renders markdown content with headers, bold, italic, bullet lists, code blocks, and inline code.
private struct MarkdownText: View {
    let source: String

    init(_ source: String) {
        self.source = source
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            let blocks = parseBlocks(source)
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }

    private enum Block {
        case paragraph(String)
        case heading(Int, String)
        case bullet(String)
        case codeBlock(String)
        case blank
    }

    private func parseBlocks(_ text: String) -> [Block] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [Block] = []
        var inCodeBlock = false
        var codeLines: [String] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            let joined = paragraphLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                blocks.append(.paragraph(joined))
            }
            paragraphLines.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    inCodeBlock = false
                } else {
                    flushParagraph()
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(heading)
                continue
            }

            if let bullet = parseBullet(trimmed) {
                flushParagraph()
                blocks.append(bullet)
                continue
            }

            paragraphLines.append(line)
        }

        if inCodeBlock && !codeLines.isEmpty {
            blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
        }
        flushParagraph()

        return blocks
    }

    private func parseHeading(_ line: String) -> Block? {
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1 && level <= 4 else { return nil }
        let rest = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        return .heading(level, rest)
    }

    private func parseBullet(_ line: String) -> Block? {
        if (line.hasPrefix("- ") || line.hasPrefix("* ")) && line.count > 2 {
            return .bullet(String(line.dropFirst(2)))
        }
        if let dotIndex = line.firstIndex(of: "."),
           dotIndex > line.startIndex,
           line[line.startIndex..<dotIndex].allSatisfy(\.isNumber) {
            let afterDot = line.index(after: dotIndex)
            if afterDot < line.endIndex && line[afterDot] == " " {
                let rest = String(line[line.index(after: afterDot)...])
                if !rest.isEmpty { return .bullet(rest) }
            }
        }
        return nil
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)
                .padding(.top, level == 1 ? 8 : 4)
                .padding(.bottom, 2)

        case .paragraph(let text):
            inlineMarkdown(text)
                .padding(.vertical, 2)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\u{2022}")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                inlineMarkdown(text)
            }
            .padding(.leading, 8)
            .padding(.vertical, 1)

        case .codeBlock(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.85))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.04))
            )
            .padding(.vertical, 4)

        case .blank:
            Spacer().frame(height: 4)
        }
    }

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        let fontSize: CGFloat = level == 1 ? 16 : level == 2 ? 14 : 13
        let weight: Font.Weight = level <= 2 ? .bold : .semibold
        inlineMarkdown(text, fontSize: fontSize, fontWeight: weight)
    }

    @ViewBuilder
    private func inlineMarkdown(_ text: String, fontSize: CGFloat = 13, fontWeight: Font.Weight = .regular) -> some View {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
                .font(.system(size: fontSize, weight: fontWeight))
                .lineSpacing(4)
                .tint(.blue)
                .textSelection(.enabled)
        } else {
            Text(text)
                .font(.system(size: fontSize, weight: fontWeight))
                .lineSpacing(4)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Settings Sheet

private struct SettingsSheet: View {
    @EnvironmentObject private var chatManager: ChatManager
    @EnvironmentObject private var microphoneManager: MicrophoneManager
    @EnvironmentObject private var speechEngine: SpeechEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // MARK: API Configuration
                    settingsSection("API Configuration", icon: "key.fill", color: .orange) {
                        settingsRow("Anthropic API Key") {
                            SecureField("sk-ant-...", text: $chatManager.apiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                        }

                        settingsRow("Claude Model") {
                            Picker("", selection: $chatManager.model) {
                                ForEach(ChatManager.availableModels, id: \.id) { model in
                                    Text(model.name).tag(model.id)
                                }
                            }
                            .labelsHidden()
                        }
                    }

                    // MARK: MCP Configuration
                    settingsSection("MCP Server", icon: "bolt.fill", color: .green) {
                        settingsRow("Server Path") {
                            TextField("Path to MCP server", text: $chatManager.mcpServerPath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                        }

                        settingsRow("Python Path") {
                            TextField("Path to Python", text: $chatManager.mcpPythonPath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                        }

                        Toggle(isOn: $chatManager.autoConnectMCP) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-connect MCP")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Automatically connect to MCP server when window opens")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(chatManager.mcpConnected ? .green : .red.opacity(0.5))
                                .frame(width: 8, height: 8)
                            Text(chatManager.mcpConnected ? "Connected" : "Disconnected")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(chatManager.mcpConnected ? "Disconnect" : "Connect Now") {
                                Task {
                                    if chatManager.mcpConnected {
                                        chatManager.disconnectMCP()
                                    } else {
                                        await chatManager.connectMCP()
                                    }
                                }
                            }
                            .controlSize(.small)
                        }
                    }

                    // MARK: Microphone
                    settingsSection("Microphone", icon: "mic.fill", color: .blue) {
                        if microphoneManager.hasPermission {
                            settingsRow("Default Microphone") {
                                Picker("", selection: $microphoneManager.selectedMicrophoneID) {
                                    ForEach(microphoneManager.microphones) { mic in
                                        Text(mic.name).tag(mic.id)
                                    }
                                }
                                .labelsHidden()
                            }
                        } else {
                            HStack {
                                Text("Microphone access required")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Allow Access") {
                                    microphoneManager.requestPermissionAndRefresh()
                                }
                                .controlSize(.small)
                            }
                        }
                    }

                    // MARK: Behavior
                    settingsSection("Behavior", icon: "sparkles", color: .purple) {
                        Toggle(isOn: $chatManager.autoAnswer) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-answer")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Automatically send transcribed speech to Claude for answers")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)

                        Divider()

                        Toggle(isOn: $chatManager.firstPersonAnswers) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("First-Person Answers")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Claude answers as if you're speaking in the meeting")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }

                    // MARK: File Editing
                    settingsSection("File Editing", icon: "filemenu.and.cursorarrow", color: .blue) {
                        Toggle(isOn: $chatManager.fileEditingEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable File Editing")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Allow Claude to read, write, and create files")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)

                        if chatManager.fileEditingEnabled {
                            Divider()

                            settingsRow("Operation Mode") {
                                Picker("", selection: $chatManager.operationMode) {
                                    Text("Permissions").tag(OperationMode.permissions.rawValue)
                                    Text("Plan").tag(OperationMode.plan.rawValue)
                                    Text("Auto-Approve").tag(OperationMode.autoApprove.rawValue)
                                }
                                .labelsHidden()
                            }

                            settingsRow("Project Root") {
                                TextField("Path", text: $chatManager.projectRootPath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                        }
                    }

                    // MARK: Errors
                    if chatManager.errorMessage != nil || speechEngine.errorMessage != nil {
                        settingsSection("Status", icon: "exclamationmark.triangle.fill", color: .orange) {
                            if let error = chatManager.errorMessage {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                                    .lineLimit(3)
                            }
                            if let error = speechEngine.errorMessage {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 420, height: 520)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(.controlBackgroundColor))
            )
        }
    }

    @ViewBuilder
    private func settingsRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            content()
        }
    }
}
