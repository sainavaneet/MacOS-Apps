import Foundation

enum OperationMode: String, CaseIterable {
    case permissions = "permissions"
    case plan = "plan"
    case autoApprove = "auto"

    var displayName: String {
        switch self {
        case .permissions:
            return "Permissions"
        case .plan:
            return "Plan"
        case .autoApprove:
            return "Auto-Approve"
        }
    }

    var description: String {
        switch self {
        case .permissions:
            return "Ask for permission before each change"
        case .plan:
            return "Show plan, approve once to execute all"
        case .autoApprove:
            return "Automatically apply all changes"
        }
    }

    var icon: String {
        switch self {
        case .permissions:
            return "checkmark.square"
        case .plan:
            return "list.bullet.clipboard"
        case .autoApprove:
            return "bolt.fill"
        }
    }
}
