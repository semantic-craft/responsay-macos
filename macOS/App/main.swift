import AppKit

// #578 — pure AppKit lifecycle. Crash 9 (1.4.21) fired with the app IDLE: no insert, no panel
// activity — the last SwiftUI scene (the empty `Settings`) still kept eight framework-owned
// full-width hosting strips alive, and macOS 26's display-cycle loop breaker aborts whichever
// SwiftUI window it catches oscillating. With no scenes at all, the only SwiftUI left in this
// process is our own pinned panel content (guarded since #569) and Apple's in-process input
// method window (TUINSWindow) — the irreducible remainder for the Apple Feedback.
//
// MainActor.assumeIsolated: main.swift top-level code is the process entry on the main thread;
// NSApplicationMain never returns.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let bootstrap = AppBootstrap()
    let delegate = MacAppDelegate()
    delegate.captureController = bootstrap.controller
    delegate.captureControllerStartAction = bootstrap.startAction
    app.delegate = delegate
    app.mainMenu = MainMenuBuilder.build()

    // Keep strong references for the process lifetime (globals below never deallocate).
    objc_setAssociatedObject(app, &bootstrapKey, bootstrap, .OBJC_ASSOCIATION_RETAIN)
    objc_setAssociatedObject(app, &delegateKey, delegate, .OBJC_ASSOCIATION_RETAIN)

    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
}

nonisolated(unsafe) private var bootstrapKey: UInt8 = 0
nonisolated(unsafe) private var delegateKey: UInt8 = 0
