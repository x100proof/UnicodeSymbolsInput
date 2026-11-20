import Foundation

/// The symbol set catalog (`Sets/catalog.json`): classes of symbol sets.
///
/// Rules (see ARCHITECTURE.md):
/// - At most one set per class is active at a time.
/// - Sets in the same class may share command names (only one is ever active).
/// - Sets in different classes must never share a command name. `crossClassConflicts`
///   finds violations; the test suite fails on any, so a conflicting catalog never ships.
public struct Catalog: Decodable {
    public struct SetInfo: Decodable, Equatable {
        public let id: String
        public let name: String
        public let file: String
    }

    public struct SetClass: Decodable {
        public let id: String
        public let name: String
        /// The set used when the user hasn't chosen one for this class.
        public let `default`: String
        public let sets: [SetInfo]

        public func set(id: String) -> SetInfo? { sets.first { $0.id == id } }
    }

    public let classes: [SetClass]

    /// The directory holding `catalog.json` and the set files it names.
    public private(set) var directory = URL(fileURLWithPath: "/")

    private enum CodingKeys: String, CodingKey { case classes }

    public static func load(from directory: URL) throws -> Catalog {
        let data = try Data(contentsOf: directory.appendingPathComponent("catalog.json"))
        var catalog = try JSONDecoder().decode(Catalog.self, from: data)
        catalog.directory = directory
        return catalog
    }

    public func setClass(id: String) -> SetClass? { classes.first { $0.id == id } }

    /// The commands of one set, without their leading backslash.
    public func entries(of set: SetInfo) throws -> [String: String] {
        let data = try Data(contentsOf: directory.appendingPathComponent(set.file))
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    // MARK: Selection

    /// The value stored for a class whose sets are all switched off.
    public static let none = "none"

    /// The active set for each class, given the user's stored choices
    /// (`[classID: setID or "none"]`). A missing or unknown choice falls back
    /// to the class default.
    public func activeSets(choices: [String: String]) -> [(SetClass, SetInfo)] {
        classes.compactMap { cls in
            let choice = choices[cls.id] ?? cls.default
            if choice == Catalog.none { return nil }
            guard let set = cls.set(id: choice) ?? cls.set(id: cls.default) else { return nil }
            return (cls, set)
        }
    }

    /// Merges the active sets into one table. Classes are applied in catalog
    /// order and the first claim on a command wins; with a valid catalog no
    /// command is ever claimed twice. Returns the duplicates it skipped.
    public func table(choices: [String: String]) throws -> (entries: [String: String], skipped: [String]) {
        var merged: [String: String] = [:]
        var skipped: [String] = []
        for (_, set) in activeSets(choices: choices) {
            for (command, symbol) in try entries(of: set) {
                if merged[command] == nil { merged[command] = symbol } else { skipped.append(command) }
            }
        }
        return (merged, skipped.sorted())
    }

    // MARK: Validation

    public struct Conflict: CustomStringConvertible {
        public let command: String
        public let first: (setClass: String, set: String)
        public let second: (setClass: String, set: String)
        public var description: String {
            "\\\(command): \(first.setClass)/\(first.set) and \(second.setClass)/\(second.set)"
        }
    }

    /// Every command name that appears in sets of two different classes.
    public func crossClassConflicts() throws -> [Conflict] {
        var owner: [String: (setClass: String, set: String)] = [:]
        var conflicts: [Conflict] = []
        for cls in classes {
            var thisClass: [String: (setClass: String, set: String)] = [:]
            for set in cls.sets {
                for command in try entries(of: set).keys {
                    if let other = owner[command] {
                        conflicts.append(Conflict(command: command, first: other, second: (cls.id, set.id)))
                    }
                    thisClass[command] = thisClass[command] ?? (cls.id, set.id)
                }
            }
            owner.merge(thisClass) { old, _ in old }
        }
        return conflicts.sorted { $0.command < $1.command }
    }

    /// Structural problems: duplicate ids, missing defaults, empty classes.
    public func structuralProblems() -> [String] {
        var problems: [String] = []
        let classIDs = classes.map(\.id)
        if Set(classIDs).count != classIDs.count { problems.append("duplicate class ids") }
        for cls in classes {
            if cls.sets.isEmpty { problems.append("class \(cls.id) has no sets") }
            let ids = cls.sets.map(\.id)
            if Set(ids).count != ids.count { problems.append("class \(cls.id) has duplicate set ids") }
            if ids.contains(Catalog.none) { problems.append("class \(cls.id) uses the reserved id \"none\"") }
            if cls.set(id: cls.default) == nil {
                problems.append("class \(cls.id) default \"\(cls.default)\" is not one of its sets")
            }
        }
        return problems
    }
}
