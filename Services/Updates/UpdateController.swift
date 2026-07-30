import Combine
import Sparkle

@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var canCheckForUpdates: Bool

    private let updaterController: SPUStandardUpdaterController
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller
        controller.updater.automaticallyChecksForUpdates = true
        controller.updater.automaticallyDownloadsUpdates = false
        canCheckForUpdates = controller.updater.canCheckForUpdates

        controller.updater.checkForUpdatesInBackground()

        controller.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canCheckForUpdates in
                self?.canCheckForUpdates = canCheckForUpdates
            }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
