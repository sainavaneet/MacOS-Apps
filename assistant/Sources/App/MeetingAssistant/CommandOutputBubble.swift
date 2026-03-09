import SwiftUI

struct CommandOutputBubble: View {
    let command: Command
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerView
            outputView
            statusView
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var headerView: some View {
        HStack {
            Image(systemName: "terminal.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.blue))

            VStack(alignment: .leading, spacing: 2) {
                Text(command.displayCommand)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(command.workingDirectory)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if command.isDangerous {
                Text("⚠️ DANGEROUS")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.red)
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(6)
    }

    @ViewBuilder
    private var outputView: some View {
        if !command.output.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Output:")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(command.output)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(4)
                }
                .frame(maxHeight: 120)
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if isPending {
            HStack(spacing: 8) {
                Button(action: onApprove) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                        Text("Execute")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(6)
                    .background(Color.green.opacity(0.8))
                    .foregroundStyle(.white)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Button(action: onReject) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                        Text("Cancel")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(6)
                    .background(Color.red.opacity(0.8))
                    .foregroundStyle(.white)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var isPending: Bool {
        if case .pending = command.status {
            return true
        }
        return false
    }
}

#Preview {
    VStack(spacing: 12) {
        CommandOutputBubble(
            command: Command(
                type: .shell,
                command: "swift build -c release",
                workingDirectory: "/Users/user/project",
                output: "Building for production...\nBuild complete!"
            ),
            onApprove: {},
            onReject: {}
        )
    }
    .padding()
}
