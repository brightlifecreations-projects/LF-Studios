import Foundation

enum ShotStyleMenuRole: String {
    case normal
    case primary
    case destructive
}

struct ShotStyleMenuAction: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let symbolName: String
    let shortcut: String?
    let isEnabled: Bool
    let role: ShotStyleMenuRole
    let handler: () -> Void

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        symbolName: String,
        shortcut: String? = nil,
        isEnabled: Bool = true,
        role: ShotStyleMenuRole = .normal,
        handler: @escaping () -> Void = {}
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.role = role
        self.handler = handler
    }
}

struct ShotStyleMenuSection: Identifiable {
    let id: String
    let title: String
    let actions: [ShotStyleMenuAction]

    init(id: String, title: String, actions: [ShotStyleMenuAction]) {
        self.id = id
        self.title = title
        self.actions = actions
    }
}
