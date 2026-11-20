// usi-ctl: register the input method and choose symbol sets from the terminal.
//
//   usi-ctl status                     classes, their sets, and which is active
//   usi-ctl use <class> <set|none>     choose a class's set (one per class), e.g. `use prover agda`
//   usi-ctl register <app>             register and enable an installed input method bundle
//   usi-ctl select                     make Unicode Symbols the current input source
//   usi-ctl unregister                 disable the input source (before deleting the bundle)
import Carbon
import Foundation

let bundleID = "org.100proof.inputmethod.UnicodeSymbolsInput"
let installed = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Input Methods/UnicodeSymbolsInput.app")

func fail(_ message: String) -> Never {
    fputs("usi-ctl: \(message)\n", stderr)
    exit(1)
}

/// The catalog of the installed input method, or of the repo this tool was built from.
func loadCatalog() -> Catalog {
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let candidates = [
        installed.appendingPathComponent("Contents/Resources/Sets"),
        exe.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sets"),
    ]
    for dir in candidates {
        if let catalog = try? Catalog.load(from: dir) { return catalog }
    }
    fail("no symbol set catalog found (install the input method first)")
}

let defaults = UserDefaults(suiteName: bundleID)!
var choices: [String: String] {
    defaults.dictionary(forKey: "ActiveSets") as? [String: String] ?? [:]
}

func inputSource() -> TISInputSource? {
    let filter = [kTISPropertyInputSourceID as String: bundleID] as CFDictionary
    let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
    return list?.first
}

func check(_ status: OSStatus, _ what: String) {
    if status != noErr { fail("\(what) failed (OSStatus \(status))") }
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "status"?, nil:
    let catalog = loadCatalog()
    let active = Dictionary(uniqueKeysWithValues: catalog.activeSets(choices: choices).map { ($0.0.id, $0.1.id) })
    for cls in catalog.classes {
        print("\(cls.name) (\(cls.id)):")
        for set in cls.sets {
            print("  \(active[cls.id] == set.id ? "*" : " ") \(set.id.padding(toLength: 8, withPad: " ", startingAt: 0)) \(set.name)")
        }
        print("  \(active[cls.id] == nil ? "*" : " ") none")
    }
    print(inputSource() == nil ? "\nInput source: not registered" : "\nInput source: registered")

case "use"?:
    guard args.count == 3 else { fail("usage: usi-ctl use <class> <set|none>") }
    let catalog = loadCatalog()
    guard let cls = catalog.setClass(id: args[1]) else {
        fail("unknown class \"\(args[1])\"; classes: \(catalog.classes.map(\.id).joined(separator: ", "))")
    }
    guard args[2] == Catalog.none || cls.set(id: args[2]) != nil else {
        fail("unknown \(cls.id) set \"\(args[2])\"; sets: \((cls.sets.map(\.id) + [Catalog.none]).joined(separator: ", "))")
    }
    var next = choices
    next[cls.id] = args[2]
    defaults.set(next, forKey: "ActiveSets")
    defaults.synchronize()
    print("\(cls.name): \(cls.set(id: args[2])?.name ?? "none") (applies from the next text field you click into)")

case "register"?:
    let app = args.count > 1 ? URL(fileURLWithPath: args[1]) : installed
    check(TISRegisterInputSource(app as CFURL), "registering \(app.path)")
    guard let source = inputSource() else { fail("registered, but the input source isn't visible yet; log out and in") }
    check(TISEnableInputSource(source), "enabling the input source")
    print("Registered and enabled \(app.path)")

case "select"?:
    guard let source = inputSource() else { fail("not registered; run usi-ctl register first") }
    check(TISSelectInputSource(source), "selecting the input source")

case "unregister"?:
    if let source = inputSource() { check(TISDisableInputSource(source), "disabling the input source") }
    print("Disabled \(bundleID)")

default:
    fail("unknown command \"\(args[0])\"; commands: status, use, register, select, unregister")
}
