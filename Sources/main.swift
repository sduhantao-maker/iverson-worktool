import Cocoa

// launchd starts this same executable to check the KeepGoing auto-off rules.
if CommandLine.arguments.contains(KeepGoingGuard.launchArgument) {
    exit(KeepGoingGuard.runFromLaunchd())
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.regular)
app.run()
