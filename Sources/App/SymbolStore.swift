import Foundation
import os

/// Process-wide state: the catalog, the user's set choices and the merged table.
///
/// Choices live in this input method's own preferences domain under
/// `ActiveSets` (`[classID: setID or "none"]`), written by the input menu and
/// by `usi-ctl use`. They are re-read whenever a text field gains focus, so a
/// change made with `usi-ctl` applies from the next field you click into.
final class SymbolStore {
    static let shared = SymbolStore()
    static let choicesKey = "ActiveSets"

    let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "UnicodeSymbolsInput", category: "sets")
    let catalog: Catalog?
    private(set) var table = SymbolTable([:])
    private(set) var choices: [String: String] = [:]
    /// Bumped whenever `table` is replaced, so controllers know to pick it up.
    private(set) var generation = 0

    private init() {
        let dir = Bundle.main.resourceURL!.appendingPathComponent("Sets")
        do {
            catalog = try Catalog.load(from: dir)
        } catch {
            catalog = nil
            log.error("Cannot load the set catalog at \(dir.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
        reloadIfChanged()
    }

    private var stored: [String: String] {
        UserDefaults.standard.dictionary(forKey: Self.choicesKey) as? [String: String] ?? [:]
    }

    func reloadIfChanged() {
        let now = stored
        guard now != choices || generation == 0 else { return }
        choices = now
        guard let catalog else { return }
        do {
            let (entries, skipped) = try catalog.table(choices: now)
            if !skipped.isEmpty {
                // Can't happen with a catalog that passed the tests; keep the first class's command.
                log.fault("Cross-class conflicts (first class wins): \(skipped.joined(separator: " "), privacy: .public)")
            }
            table = SymbolTable(entries)
            generation += 1
            let active = catalog.activeSets(choices: now).map { "\($0.0.id)/\($0.1.id)" }.joined(separator: ", ")
            log.info("Loaded \(entries.count) commands from \(active, privacy: .public)")
        } catch {
            log.error("Cannot load symbol sets: \(String(describing: error), privacy: .public)")
        }
    }

    /// The active set id for a class, or "none".
    func active(in cls: Catalog.SetClass) -> String {
        catalog?.activeSets(choices: choices).first { $0.0.id == cls.id }?.1.id ?? Catalog.none
    }

    func choose(_ setID: String, in classID: String) {
        var next = stored
        next[classID] = setID
        UserDefaults.standard.set(next, forKey: Self.choicesKey)
        reloadIfChanged()
    }
}
