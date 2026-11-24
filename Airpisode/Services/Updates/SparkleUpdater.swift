import Combine
import Sparkle

/// The app's one update checker.
///
/// Sparkle's standard user driver owns the whole update experience — the available
/// version, release notes, download progress, install and relaunch prompts — so this
/// type is only the seam SwiftUI needs: start the controller when the build has a feed,
/// expose a manual check, and explain why updates are off when it does not.
@MainActor
final class SparkleUpdater: ObservableObject {
    enum Status: Equatable {
        case configured
        /// The build has no usable `SUFeedURL`/`SUPublicEDKey`; the reason is user-facing.
        case unconfigured(String)
    }

    let status: Status

    /// `nil` in a build that was not compiled with a feed, which keeps Sparkle from
    /// logging a failed fetch on every launch of a development build.
    private let controller: SPUStandardUpdaterController?

    init(configuration: Result<UpdateConfiguration, UpdateConfiguration.Problem> = UpdateConfiguration.load()) {
        switch configuration {
        case .success:
            // `startingUpdater: true` starts Sparkle's scheduler, which honours
            // `SUEnableAutomaticChecks` and `SUScheduledCheckInterval` from Info.plist.
            self.controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            self.status = .configured

        case .failure(let problem):
            self.controller = nil
            self.status = .unconfigured(problem.message)
        }
    }

    var canCheckForUpdates: Bool { controller != nil }

    /// Whether Sparkle checks on its own schedule. Sparkle persists the user's choice,
    /// so this is the app's only source of truth for the toggle in Settings.
    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    /// Opens Sparkle's standard update UI. The controller hops to the main thread itself;
    /// calling it while a check is already running is a no-op.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
