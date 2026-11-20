import Cocoa
import InputMethodKit

// macOS launches this background app when the input source is first selected.
// The IMKServer listens on the connection named in Info.plist and creates one
// InputController per text field (client) the user types into.
guard let connection = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String else {
    fatalError("Info.plist has no InputMethodConnectionName")
}
let server = IMKServer(name: connection, bundleIdentifier: Bundle.main.bundleIdentifier)
withExtendedLifetime(server) {
    NSApplication.shared.run()
}
