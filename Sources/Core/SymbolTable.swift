import Foundation

/// A command and the text it inserts, e.g. `to` → `→`.
public struct Candidate: Equatable {
    public let command: String
    public let symbol: String
    public init(command: String, symbol: String) {
        self.command = command
        self.symbol = symbol
    }
}

/// The merged commands of the active sets, with exact lookup and prefix search.
public final class SymbolTable {
    private let entries: [String: String]
    /// All candidates, pre-sorted in suggestion order: shorter commands first,
    /// then alphabetical. Prefix search keeps this order.
    private let ordered: [Candidate]

    public init(_ entries: [String: String]) {
        self.entries = entries
        ordered = entries
            .map { Candidate(command: $0.key, symbol: $0.value) }
            .sorted { ($0.command.count, $0.command) < ($1.command.count, $1.command) }
    }

    public var count: Int { entries.count }

    public func symbol(for command: String) -> String? { entries[command] }

    /// Commands starting with `prefix`, the exact match (if any) first, then
    /// shorter before longer. Matching is case-sensitive, as in Lean and Agda
    /// (`\N` and `\n` differ). An empty prefix matches nothing.
    public func candidates(prefix: String) -> [Candidate] {
        guard !prefix.isEmpty else { return [] }
        // Linear scan: a few thousand short strings per keystroke is well under a millisecond.
        return ordered.filter { $0.command.hasPrefix(prefix) }
    }
}
