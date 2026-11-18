import AppKit

/// Presents one dimmed overlay per display and runs the selection gesture through `SelectionStateMachine`.
///
/// At most one selection runs at a time. `runSelection` suspends until the user commits, cancels, or the
/// display arrangement changes; the windows then stay up until `dismiss()` so the caller can capture with
/// them excluded and tear everything down in one place, including on error paths.
@MainActor
final class SelectionOverlayController: SelectionOverlayPresenting {
    private var panels: [DisplayID: SelectionOverlayPanel] = [:]
    private var views: [DisplayID: SelectionOverlayView] = [:]
    private var machine: SelectionStateMachine?
    private var continuation: CheckedContinuation<SelectionOutcome, Never>?
    private var screenObserver: (any NSObjectProtocol)?
    private var hintResetTask: Task<Void, Never>?
    private var previousApplication: NSRunningApplication?

    var overlayWindowIDs: [CGWindowID] {
        panels.values.map { CGWindowID($0.windowNumber) }
    }

    func runSelection(layout: DisplayLayout, dimOpacity: Double) async -> SelectionOutcome {
        // A second request while one is running would stack overlays; the coordinator prevents it, this guards it.
        guard continuation == nil else { return .cancelled }
        dismiss()

        let machine = SelectionStateMachine(layout: layout)
        self.machine = machine
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            present(layout: layout, dimOpacity: dimOpacity)
        }
    }

    func dismiss() {
        // Never leave a suspended caller behind.
        finish(.cancelled)
        hintResetTask?.cancel()
        hintResetTask = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        for panel in panels.values {
            panel.orderOut(nil)
            panel.close()
        }
        panels = [:]
        views = [:]
        machine = nil
        if let previous = previousApplication, !previous.isTerminated {
            _ = previous.activate(from: NSRunningApplication.current)
        }
        previousApplication = nil
    }

    // MARK: Presenting

    private func present(layout: DisplayLayout, dimOpacity: Double) {
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApplication = (frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier) ? nil : frontmost

        for display in layout.displays {
            guard let screen = NSScreen.screens.first(where: { $0.captAIDisplayID == display.id }) else { continue }
            let panel = SelectionOverlayPanel(
                contentRect: display.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.animationBehavior = .none
            panel.isMovable = false
            // Also ask the window server to keep this window out of other apps' captures. The capture
            // additionally excludes it explicitly, because this alone is not honoured everywhere.
            panel.sharingType = .none
            panel.setFrame(display.frame, display: false)

            let view = SelectionOverlayView(frame: CGRect(origin: .zero, size: display.frame.size))
            view.controller = self
            view.displayFrame = display.frame
            view.dimOpacity = dimOpacity
            view.hint = SelectionOverlayView.defaultHint
            panel.contentView = view

            panels[display.id] = panel
            views[display.id] = view
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(.interrupted) }
        }

        // The app is a menu-bar agent, so it must activate itself for the overlay to receive Esc.
        NSApp.activate()
        for panel in panels.values { panel.orderFrontRegardless() }
        let mouse = NSEvent.mouseLocation
        let keyDisplay = layout.display(containing: mouse)?.id ?? layout.primary?.id
        if let keyDisplay, let panel = panels[keyDisplay] {
            panel.makeKey()
            panel.makeFirstResponder(views[keyDisplay])
        }
    }

    // MARK: Events from the views

    func mouseDown(at point: CGPoint) {
        guard machine != nil else { return }
        machine?.mouseDown(at: point)
        for view in views.values { view.hint = nil }
        refresh()
    }

    func mouseDragged(to point: CGPoint) {
        machine?.mouseDragged(to: point)
        refresh()
    }

    func mouseUp(at point: CGPoint) {
        guard let outcome = machine?.mouseUp(at: point) else { return }
        switch outcome {
        case .committed(let region):
            refresh()
            finish(.committed(region))
        case .rejectedTooSmall:
            showHint("Selection too small · drag a larger area")
            refresh()
        case .none, .cancelled:
            break
        }
    }

    func cancel() {
        guard let outcome = machine?.cancel(), outcome == .cancelled else { return }
        finish(.cancelled)
    }

    // MARK: Helpers

    /// Pushes the current selection to the views. Only the display the drag started on draws it.
    private func refresh() {
        guard let machine else { return }
        var selected: (display: DisplayID, rect: CGRect)?
        switch machine.phase {
        case .selecting:
            selected = machine.activeSelection
        case .committed(let region):
            selected = (region.displayID, region.appKitRect)
        case .idle, .cancelled:
            selected = nil
        }
        for (id, view) in views {
            view.selection = (selected?.display == id) ? selected?.rect : nil
        }
    }

    private func showHint(_ text: String) {
        for view in views.values { view.hint = text }
        hintResetTask?.cancel()
        hintResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            guard let self, self.machine?.activeSelection == nil else { return }
            for view in self.views.values { view.hint = SelectionOverlayView.defaultHint }
        }
    }

    private func finish(_ outcome: SelectionOutcome) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: outcome)
    }
}
