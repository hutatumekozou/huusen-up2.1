import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = OverlaySettings()
    private lazy var overlayController = OverlayWindowController(settings: settings)
    private lazy var webAdminServer = WebAdminServer(
        settings: settings,
        showNow: { [weak self] in
            guard let self, self.settings.hasEnabledBalloons else { return }
            self.overlayController.show()
        },
        settingsChanged: { [weak self] in self?.settingsChanged() },
        pauseChanged: { [weak self] in self?.pauseChanged() }
    )
    private var statusItem: NSStatusItem?
    private var pauseMenuItem: NSMenuItem?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        startTimer()
        webAdminServer.start()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "🎈"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "今すぐ表示", action: #selector(showNow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "管理画面を開く", action: #selector(openAdminPage), keyEquivalent: ""))
        let pauseItem = NSMenuItem(title: pauseTitle, action: #selector(togglePause(_:)), keyEquivalent: "")
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "終了", action: #selector(quit), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
        pauseMenuItem = pauseItem
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: settings.displayInterval, repeats: true) { [weak self] _ in
            guard let self, !self.settings.isPaused, self.settings.hasEnabledBalloons else { return }
            self.settings.activateNextEnabledBalloon()
            self.overlayController.show()
        }
    }

    private var pauseTitle: String {
        settings.isPaused ? "再開" : "一時停止"
    }

    private func settingsChanged() {
        startTimer()
    }

    private func pauseChanged() {
        pauseMenuItem?.title = pauseTitle
    }

    @objc private func showNow() {
        guard settings.hasEnabledBalloons else { return }
        settings.activateNextEnabledBalloon()
        overlayController.show()
    }

    @objc private func openAdminPage() {
        NSWorkspace.shared.open(webAdminServer.adminURL)
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        settings.setPaused(!settings.isPaused)
        pauseChanged()
    }

    @objc private func quit() {
        timer?.invalidate()
        webAdminServer.stop()
        NSApp.terminate(nil)
    }
}
