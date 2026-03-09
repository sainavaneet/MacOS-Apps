import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var chatManager: ChatManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Settings")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Form {
                Section("API Configuration") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Key")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        SecureField("sk-...", text: $chatManager.apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }

                    Picker("Model", selection: $chatManager.model) {
                        ForEach(ChatManager.availableModels, id: \.id) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                }

                Section("File Editing") {
                    Toggle("Enable File Editing", isOn: $chatManager.fileEditingEnabled)

                    if chatManager.fileEditingEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Operation Mode")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)

                            Picker("Mode", selection: $chatManager.operationMode) {
                                ForEach(OperationMode.allCases, id: \.rawValue) { mode in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mode.displayName)
                                        Text(mode.description)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                    .tag(mode.rawValue)
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Project Root Path")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                TextField("Path", text: $chatManager.projectRootPath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))

                                HStack {
                                    Image(systemName: "info.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.blue)
                                    Text("Claude can edit files within this directory")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Meeting Assistant") {
                    Toggle("Auto-Answer", isOn: $chatManager.autoAnswer)
                    Toggle("Auto-Connect MCP", isOn: $chatManager.autoConnectMCP)
                }

                Section("MCP Configuration") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server Path")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("Path", text: $chatManager.mcpServerPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Python Path")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("Path", text: $chatManager.mcpPythonPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }
                }
            }
            .scrollContentBackground(.hidden)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.textBackgroundColor))
    }
}

#Preview {
    SettingsView()
        .environmentObject(ChatManager())
}
