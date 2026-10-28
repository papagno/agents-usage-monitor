import Combine
import Sparkle
import SwiftUI

/// Owns Sparkle's updater. Sparkle reads the feed URL and the key that signs updates from
/// Info.plist (see bundle.sh), and release.sh publishes the feed.
@MainActor
final class Updates: NSObject, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                  userDriverDelegate: self)
    }

    var updater: SPUUpdater { controller.updater }

    func checkForUpdates() {
        // A menu bar app isn't active, so bring Sparkle's window to the front.
        NSApp.activate(ignoringOtherApps: true)
        updater.checkForUpdates()
    }

    // Menu bar apps have no Dock icon, so scheduled update alerts are shown gently instead of
    // stealing focus; Sparkle warns if a background app doesn't opt in.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}

/// "Check for Updates…" in the gear menu.
struct CheckForUpdatesButton: View {
    let updates: Updates
    @StateObject private var model: Model

    init(updates: Updates) {
        self.updates = updates
        _model = StateObject(wrappedValue: Model(updater: updates.updater))
    }

    var body: some View {
        Button("Check for Updates…") { updates.checkForUpdates() }
            .disabled(!model.canCheckForUpdates)
    }

    /// Mirrors the updater's KVO property, which is false while a check is already running.
    @MainActor
    final class Model: ObservableObject {
        @Published var canCheckForUpdates = false

        init(updater: SPUUpdater) {
            updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        }
    }
}
