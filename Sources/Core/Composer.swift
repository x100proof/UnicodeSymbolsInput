import Foundation

/// The input method's state machine, free of any UI or InputMethodKit types so
/// it can be tested directly.
///
/// Idle, every key passes through. A backslash starts a *composition*: the
/// text after it is the command being typed, shown underlined by the app and
/// matched against the symbol table as you type.
///
/// | Key        | While composing                                               |
/// |------------|---------------------------------------------------------------|
/// | text       | extend the command                                            |
/// | Tab / ⇧Tab | complete: step forward / back through the suggestions         |
/// | ↓ / ↑      | the same as Tab / ⇧Tab while there are suggestions            |
/// | Space      | insert the symbol (or the typed text if no exact match), then a space |
/// | Return     | insert the symbol (or the typed text), no newline             |
/// | `\`        | insert the symbol and start a new command; on a bare `\`, insert a backslash |
/// | Delete     | remove the last character; on a bare `\`, cancel               |
/// | Esc        | give up: insert the typed text unchanged                      |
/// | other keys | insert the typed text unchanged, then let the app handle the key |
public final class Composer {
    public enum Key: Equatable {
        case text(String)
        case backslash, space, tab, backTab, enter, escape, backspace, up, down
        /// Any key the composer doesn't use: arrows left/right, function keys, …
        case other
    }

    /// What the input method must do after a key.
    public struct Effect: Equatable {
        /// Text to insert into the app (may be empty).
        public var commit: String = ""
        /// false: the app should also process the key itself.
        public var handled: Bool = true
    }

    public var table: SymbolTable

    public private(set) var isComposing = false
    /// The command as typed (no backslash). Suggestions are for this prefix.
    public private(set) var typed = ""
    /// Suggestions for `typed`, in display order.
    public private(set) var candidates: [Candidate] = []
    /// Index into `candidates` chosen with Tab or the arrow keys, if any.
    public private(set) var selection: Int?

    public init(table: SymbolTable) { self.table = table }

    /// The command as it currently reads: the chosen suggestion, or what was typed.
    public var command: String { selection.map { candidates[$0].command } ?? typed }

    /// The text the app shows underlined.
    public var markedText: String { isComposing ? "\\" + command : "" }

    /// What Space or Return would insert now, or nil if the command has no exact match.
    public var match: String? { table.symbol(for: command) }

    /// The suggestion row that Space would insert: the chosen one, or the
    /// exact match for the typed text.
    public var highlighted: Int? {
        if let selection { return selection }
        return candidates.first?.command == typed ? 0 : nil
    }

    public func handle(_ key: Key) -> Effect {
        guard isComposing else {
            switch key {
            case .backslash: start(); return Effect()
            case .text(let s): return Effect(commit: s)
            default: return Effect(handled: false)
            }
        }
        switch key {
        case .text(let s):
            setTyped(command + s)
            return Effect()
        case .backslash:
            if command.isEmpty { return Effect(commit: finish("\\")) }  // `\\` types a backslash
            let out = resolved()
            start()
            return Effect(commit: out)
        case .space:
            return Effect(commit: finish(resolved()) + " ")
        case .enter:
            return Effect(commit: finish(resolved()))
        case .tab:
            step(+1)
            return Effect()
        case .backTab:
            step(-1)
            return Effect()
        case .down, .up:
            if candidates.isEmpty { return Effect(commit: finish(raw), handled: false) }
            step(key == .down ? +1 : -1)
            return Effect()
        case .backspace:
            if command.isEmpty { return Effect(commit: finish("")) }
            setTyped(String(command.dropLast()))
            return Effect()
        case .escape:
            return Effect(commit: finish(raw))
        case .other:
            return Effect(commit: finish(raw), handled: false)
        }
    }

    /// Ends any composition, returning the typed text unchanged (for when the
    /// app takes focus away or the user clicks elsewhere).
    public func abandon() -> String {
        guard isComposing else { return "" }
        return finish(raw)
    }

    // MARK: -

    private var raw: String { "\\" + command }
    private func resolved() -> String { match ?? raw }

    private func start() {
        isComposing = true
        setTyped("")
    }

    private func finish(_ text: String) -> String {
        isComposing = false
        typed = ""
        candidates = []
        selection = nil
        return text
    }

    private func setTyped(_ text: String) {
        typed = text
        candidates = table.candidates(prefix: text)
        selection = nil
    }

    /// Tab cycling. The first Tab skips the exact match, since it's already
    /// what you typed, so it always shows something new when there is something.
    private func step(_ delta: Int) {
        let n = candidates.count
        guard n > 0 else { return }
        if let selection {
            self.selection = ((selection + delta) % n + n) % n
        } else if delta > 0 {
            selection = (candidates[0].command == typed && n > 1) ? 1 : 0
        } else {
            selection = n - 1
        }
    }
}
