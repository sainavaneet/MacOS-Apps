import SwiftUI

struct FileOperationBubble: View {
    let operation: FileOperation
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerView
            contentView
            statusView
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var headerView: some View {
        HStack {
            Image(systemName: operationIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(operationColor))

            VStack(alignment: .leading, spacing: 2) {
                Text(operationTitle)
                    .font(.system(size: 12, weight: .semibold))
                Text(operation.filePath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if operation.isDangerous {
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
    private var contentView: some View {
        if let content = operation.content, !content.isEmpty {
            if operation.type == .write, let original = operation.originalContent {
                changeDiffView(original: original, new: content)
            } else {
                contentPreviewView(content: content)
            }
        }
    }

    private func changeDiffView(original: String, new: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Changes:")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                if !original.isEmpty {
                    Text("- " + (original.split(separator: "\n").first.map(String.init) ?? ""))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.red)
                }
                Text("+ " + (new.split(separator: "\n").first.map(String.init) ?? ""))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.green)
            }
            .padding(6)
            .background(Color.black.opacity(0.05))
            .cornerRadius(4)
        }
    }

    private func contentPreviewView(content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.count > 200 ? String(content.prefix(200)) + "..." : content)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(5)
                .padding(6)
                .background(Color.black.opacity(0.05))
                .cornerRadius(4)
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
                        Text("Approve")
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
                        Text("Reject")
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
        } else if isApproved {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text("Approved")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                Spacer()
            }
            .padding(6)
            .background(Color.green.opacity(0.1))
            .cornerRadius(4)
        } else if isRejected {
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                Text("Rejected")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red)
                Spacer()
            }
            .padding(6)
            .background(Color.red.opacity(0.1))
            .cornerRadius(4)
        } else if isCompleted {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text("Completed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                Spacer()
            }
            .padding(6)
            .background(Color.green.opacity(0.1))
            .cornerRadius(4)
        } else if isFailed {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                    Text("Failed")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red)
                    Spacer()
                }
                if case .failed(let error) = operation.status {
                    Text(error)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(6)
            .background(Color.red.opacity(0.1))
            .cornerRadius(4)
        }
    }

    private var operationIcon: String {
        switch operation.type {
        case .read:
            return "doc.text"
        case .write:
            return "pencil"
        case .create:
            return "plus.square"
        case .delete:
            return "trash"
        }
    }

    private var operationColor: Color {
        switch operation.type {
        case .read:
            return .blue
        case .write:
            return .orange
        case .create:
            return .green
        case .delete:
            return .red
        }
    }

    private var operationTitle: String {
        switch operation.type {
        case .read:
            return "Read File"
        case .write:
            return "Write File"
        case .create:
            return "Create File"
        case .delete:
            return "Delete File"
        }
    }

    private var isPending: Bool {
        if case .pending = operation.status {
            return true
        }
        return false
    }

    private var isApproved: Bool {
        if case .approved = operation.status {
            return true
        }
        return false
    }

    private var isRejected: Bool {
        if case .rejected = operation.status {
            return true
        }
        return false
    }

    private var isCompleted: Bool {
        if case .completed = operation.status {
            return true
        }
        return false
    }

    private var isFailed: Bool {
        if case .failed = operation.status {
            return true
        }
        return false
    }
}

#Preview {
    VStack(spacing: 12) {
        FileOperationBubble(
            operation: FileOperation(
                type: .write,
                filePath: "/Users/user/file.swift",
                content: "print(\"Hello\")",
                originalContent: "print(\"World\")"
            ),
            onApprove: {},
            onReject: {}
        )
    }
    .padding()
}
