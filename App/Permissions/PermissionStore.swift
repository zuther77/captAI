import AppKit
import Observation

/// Opens a URL in the user's default handler. Injected so tests do not launch System Settings.
@MainActor
protocol URLOpening {
    func open(_ url: URL)
}

@MainActor
struct WorkspaceURLOpener: URLOpening {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

/// Observable permission state for the UI. Reading state never prompts.
@MainActor
@Observable
final class PermissionStore {
    private(set) var statuses: [PermissionKind: PermissionStatus]
    /// Kinds with a request currently in flight, to disable repeat clicks.
    private(set) var requestsInFlight: Set<PermissionKind> = []

    @ObservationIgnored private let provider: any PermissionProviding
    @ObservationIgnored private let opener: any URLOpening
    @ObservationIgnored private let diagnostics: Diagnostics

    init(provider: any PermissionProviding, opener: any URLOpening, diagnostics: Diagnostics) {
        self.provider = provider
        self.opener = opener
        self.diagnostics = diagnostics
        statuses = Dictionary(uniqueKeysWithValues: PermissionKind.allCases.map {
            ($0, provider.currentStatus(for: $0))
        })
    }

    func status(for kind: PermissionKind) -> PermissionStatus {
        statuses[kind] ?? .notDetermined
    }

    /// Re-reads every status without prompting. Call when the Settings window appears or the app becomes active.
    func refresh() {
        for kind in PermissionKind.allCases {
            statuses[kind] = provider.currentStatus(for: kind)
        }
    }

    /// Prompts for access. Only call in direct response to a user action.
    func request(_ kind: PermissionKind) async {
        guard !requestsInFlight.contains(kind) else { return }
        // Asking again after a denial does nothing; send the user to System Settings instead.
        guard status(for: kind) == .notDetermined else {
            openSystemSettings(for: kind)
            return
        }
        requestsInFlight.insert(kind)
        diagnostics.info(.permissions, "Permission request started", ["kind": kind.rawValue])
        let result = await provider.request(kind)
        statuses[kind] = result
        requestsInFlight.remove(kind)
        diagnostics.info(.permissions, "Permission request finished", ["kind": kind.rawValue, "status": result.rawValue])
    }

    func openSystemSettings(for kind: PermissionKind) {
        opener.open(kind.systemSettingsURL)
    }
}
