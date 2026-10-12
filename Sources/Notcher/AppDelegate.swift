import AppKit
// import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: NotchModel!
    private var windowController: NotchWindowController!
    // private var statusItem: NSStatusItem!
    private var sigtermSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = NotchModel(audio: AudioController(), nowPlaying: NowPlayingController())
        windowController = NotchWindowController(model: model)
        model.nowPlaying.start()
        // setUpStatusItem()
        quitCleanlyOnSIGTERM()
    }

    /// `kill`/`pkill` would otherwise skip applicationWillTerminate and orphan the adapter process.
    private func quitCleanlyOnSIGTERM() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        sigtermSource = source
    }

    /// Every quit path (the gear menu, SIGTERM, logout) comes through here. Hold the quit
    /// until the notch has shrunk away.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard windowController.isShown, !model.isClosing else { return .terminateNow }
        model.close {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        // In case the animation's completion never fires; a second reply is ignored.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.nowPlaying.stop()
    }

    // // MARK: - Menu bar icon

    // private func setUpStatusItem() {
    //     statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    //     statusItem.button?.image = NSImage(systemSymbolName: "macbook", accessibilityDescription: "Notcher")

    //     let menu = NSMenu()
    //     let title = NSMenuItem(title: "Notcher", action: nil, keyEquivalent: "")
    //     title.isEnabled = false
    //     menu.addItem(title)
    //     menu.addItem(.separator())

    //     let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
    //     login.target = self
    //     menu.addItem(login)
    //     menu.addItem(.separator())

    //     let quit = NSMenuItem(title: "Quit Notcher", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    //     menu.addItem(quit)

    //     menu.delegate = self
    //     statusItem.menu = menu
    // }

    // @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
    //     let service = SMAppService.mainApp
    //     do {
    //         if service.status == .enabled {
    //             try service.unregister()
    //         } else {
    //             try service.register()
    //         }
    //     } catch {
    //         let alert = NSAlert()
    //         alert.messageText = "Couldn't change Launch at Login"
    //         alert.informativeText = error.localizedDescription
    //         alert.runModal()
    //     }
    // }
}

// extension AppDelegate: NSMenuDelegate {
//     func menuNeedsUpdate(_ menu: NSMenu) {
//         let enabled = SMAppService.mainApp.status == .enabled
//         menu.items.first { $0.action == #selector(toggleLaunchAtLogin(_:)) }?.state = enabled ? .on : .off
//     }
// }
