import AppKit
import IOKit.pwr_mgt
import ServiceManagement
import Sparkle

// MARK: - Preferences

private enum DefaultsKey {
    static let keepDisplayOn = "keepDisplayOn"
    static let activateOnLaunch = "activateOnLaunch"
}

// MARK: - Session length

/// A menu-selectable session length. `seconds == nil` means "no time limit".
private struct SessionLength {
    let seconds: TimeInterval?
    /// Shown when idle, e.g. "For 1 hour" — the verb is "start".
    let idleTitle: String
    /// Shown when already awake, e.g. "Reset to 1 hour" — the verb is "replace".
    let activeTitle: String

    static let all: [SessionLength] = [
        SessionLength(seconds: nil, idleTitle: "Indefinitely", activeTitle: "Remove Time Limit"),
        .timed(minutes: 15, label: "15 minutes"),
        .timed(minutes: 30, label: "30 minutes"),
        .timed(minutes: 60, label: "1 hour"),
        .timed(minutes: 120, label: "2 hours"),
        .timed(minutes: 300, label: "5 hours"),
    ]

    private static func timed(minutes: Int, label: String) -> SessionLength {
        SessionLength(seconds: TimeInterval(minutes) * 60,
                      idleTitle: "For \(label)",
                      activeTitle: "Reset to \(label)")
    }

    func title(isActive: Bool) -> String { isActive ? activeTitle : idleTitle }
}

// MARK: - Power assertion

/// Wraps a single IOKit power assertion. The kernel holds the flag, so an active
/// assertion costs no CPU — there is nothing to poll and nothing to keep alive.
private final class Caffeine {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isActive = false

    /// `true` keeps the display on. `false` lets the display sleep while still
    /// preventing the machine itself from sleeping — useful for long downloads.
    var keepDisplayOn = true

    func start(reason: String) -> Bool {
        guard !isActive else { return true }
        let type = keepDisplayOn
            ? kIOPMAssertionTypePreventUserIdleDisplaySleep
            : kIOPMAssertionTypePreventUserIdleSystemSleep
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        guard result == kIOReturnSuccess else { return false }
        assertionID = id
        isActive = true
        return true
    }

    func stop() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let caffeine = Caffeine()

    /// Sparkle drives update checks itself on a background schedule; the feed URL,
    /// public key, and check interval all come from Info.plist. Lazy so `self` is
    /// available as the user-driver delegate — started in `applicationDidFinishLaunching`.
    private lazy var updater = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: self
    )

    /// Non-nil only while a timed session is running, so an idle app has no
    /// scheduled work of any kind.
    private var expiry: (timer: Timer, date: Date)?

    private var defaults: UserDefaults { .standard }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        caffeine.keepDisplayOn = defaults.object(forKey: DefaultsKey.keepDisplayOn) as? Bool ?? true

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshStatusItem()

        if defaults.bool(forKey: DefaultsKey.activateOnLaunch) {
            activate(for: nil)
        }

        updater.startUpdater()
    }

    func applicationWillTerminate(_ notification: Notification) {
        deactivate()
    }

    // MARK: State

    private func activate(for duration: TimeInterval?) {
        cancelExpiry()

        guard caffeine.start(reason: "KeepAwake: user requested") else {
            presentAssertionFailure()
            return
        }

        if let duration {
            let date = Date().addingTimeInterval(duration)
            let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
                self?.deactivate()
            }
            // Tolerance lets macOS coalesce this wake-up with other scheduled work.
            timer.tolerance = 30
            RunLoop.main.add(timer, forMode: .common)
            expiry = (timer, date)
        }
        refreshStatusItem()
    }

    private func deactivate() {
        cancelExpiry()
        caffeine.stop()
        refreshStatusItem()
    }

    private func cancelExpiry() {
        expiry?.timer.invalidate()
        expiry = nil
    }

    private var timeRemaining: TimeInterval? {
        expiry.map { max(0, $0.date.timeIntervalSinceNow) }
    }

    private func refreshStatusItem() {
        let isOn = caffeine.isActive
        let label = isOn ? "KeepAwake — on" : "KeepAwake — off"
        let image = NSImage(
            systemSymbolName: isOn ? "cup.and.saucer.fill" : "cup.and.saucer",
            accessibilityDescription: label
        )
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = label
    }

    private func presentAssertionFailure() {
        let alert = NSAlert()
        alert.messageText = "Couldn't keep the Mac awake"
        alert.informativeText = "macOS refused the power assertion. Try again, "
            + "or restart KeepAwake if it keeps happening."
        alert.runModal()
    }

    // MARK: Menu
    //
    // Rebuilt only when opened, so nothing here runs in the background.

    func menuNeedsUpdate(_ menu: NSMenu) {
        let isActive = caffeine.isActive
        menu.removeAllItems()

        menu.addItem(header(isActive: isActive))
        menu.addItem(.separator())

        if isActive {
            menu.addItem(item("Turn Off", #selector(turnOff), key: "s"))
            menu.addItem(.separator())
        }

        for (index, length) in SessionLength.all.enumerated() {
            let entry = item(length.title(isActive: isActive),
                             #selector(selectLength(_:)),
                             key: index == 0 ? "a" : "")
            entry.tag = index
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        menu.addItem(toggle("Keep Display On", #selector(toggleDisplayMode), on: caffeine.keepDisplayOn,
                            tip: "Off: the screen may sleep, but the Mac won't."))
        menu.addItem(toggle("Start on Login", #selector(toggleLoginItem),
                            on: SMAppService.mainApp.status == .enabled))
        menu.addItem(toggle("Activate on Launch", #selector(toggleActivateOnLaunch),
                            on: defaults.bool(forKey: DefaultsKey.activateOnLaunch)))

        menu.addItem(.separator())
        menu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        menu.addItem(toggle("Update Automatically", #selector(toggleAutomaticUpdates),
                            on: updater.updater.automaticallyDownloadsUpdates,
                            tip: "Download and install new versions in the background."))

        menu.addItem(.separator())
        menu.addItem(item("Quit KeepAwake", #selector(quit), key: "q"))
    }

    private func header(isActive: Bool) -> NSMenuItem {
        let title: String
        switch (isActive, timeRemaining) {
        case (false, _): title = "Sleep allowed"
        case (true, let remaining?): title = "Awake — \(format(remaining)) left"
        case (true, nil): title = "Awake — no time limit"
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func toggle(_ title: String, _ action: Selector, on: Bool, tip: String? = nil) -> NSMenuItem {
        let item = item(title, action)
        item.state = on ? .on : .off
        item.toolTip = tip
        return item
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let (hours, minutes) = (total / 3600, (total % 3600) / 60)
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }

    // MARK: Actions

    @objc private func turnOff() {
        deactivate()
    }

    @objc private func selectLength(_ sender: NSMenuItem) {
        activate(for: SessionLength.all[sender.tag].seconds)
    }

    @objc private func toggleDisplayMode() {
        caffeine.keepDisplayOn.toggle()
        defaults.set(caffeine.keepDisplayOn, forKey: DefaultsKey.keepDisplayOn)

        // The assertion type is fixed at creation, so an active session has to be
        // retaken under the new type. Preserve whatever time was left on it.
        guard caffeine.isActive else { return }
        let remaining = timeRemaining.map { max(1, $0) }
        caffeine.stop()
        activate(for: remaining)
    }

    @objc private func toggleActivateOnLaunch() {
        defaults.set(!defaults.bool(forKey: DefaultsKey.activateOnLaunch),
                     forKey: DefaultsKey.activateOnLaunch)
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change the login item"
            alert.informativeText = "\(error.localizedDescription)\n\n"
                + "You can also set this in System Settings › General › Login Items."
            alert.runModal()
        }
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates(nil)
    }

    @objc private func toggleAutomaticUpdates() {
        updater.updater.automaticallyDownloadsUpdates.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Sparkle presentation
//
// KeepAwake is an accessory app with no Dock icon, so Sparkle's windows would
// otherwise open behind whatever the user is working in. Pull the app forward
// whenever Sparkle needs attention, and drop back afterwards.

extension AppDelegate: SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func standardUserDriverWillShowModalAlert() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func standardUserDriverDidFinishUpdateCycle() {
        NSApp.setActivationPolicy(.accessory)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
