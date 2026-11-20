// Test runner: ./build.sh test
// A plain executable rather than XCTest, so it builds with the Command Line Tools alone.
import Foundation

var failures = 0
var checks = 0

func check(_ ok: @autoclosure () -> Bool, _ message: @autoclosure () -> String,
           file: StaticString = #fileID, line: UInt = #line) {
    checks += 1
    if !ok() {
        failures += 1
        print("FAIL \(file):\(line): \(message())")
    }
}

func expectEqual<T: Equatable>(_ a: T, _ b: T, _ what: String = "",
                               file: StaticString = #fileID, line: UInt = #line) {
    check(a == b, "\(what) expected \(b), got \(a)", file: file, line: line)
}

let setsDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Sets")

// MARK: - The catalog rules (ARCHITECTURE.md)

let catalog = try Catalog.load(from: setsDir)
for problem in catalog.structuralProblems() { check(false, "catalog: \(problem)") }

for cls in catalog.classes {
    for set in cls.sets {
        let entries = (try? catalog.entries(of: set)) ?? [:]
        check(!entries.isEmpty, "\(cls.id)/\(set.id): missing or empty \(set.file)")
        let bad = entries.filter { $0.key.isEmpty || $0.value.isEmpty
            || ($0.key + $0.value).contains(where: \.isWhitespace) || $0.key.contains("\\") }
        check(bad.isEmpty, "\(cls.id)/\(set.id): \(bad.count) commands are empty, contain whitespace or a backslash")
    }
}

// The rule that matters most: no command name in two classes.
let conflicts = try catalog.crossClassConflicts()
check(conflicts.isEmpty, "\(conflicts.count) cross-class conflicts, e.g.\n  "
      + conflicts.prefix(20).map(\.description).joined(separator: "\n  "))

// Every combination of one set per class (or none) merges without skipping anything.
func combinations(_ classes: ArraySlice<Catalog.SetClass>) -> [[String: String]] {
    guard let first = classes.first else { return [[:]] }
    let rest = combinations(classes.dropFirst())
    return (first.sets.map(\.id) + [Catalog.none]).flatMap { choice in
        rest.map { $0.merging([first.id: choice]) { a, _ in a } }
    }
}
for choices in combinations(catalog.classes[...]) {
    let (_, skipped) = try catalog.table(choices: choices)
    expectEqual(skipped, [], "duplicates when merging \(choices)")
}

// Selection: defaults, explicit choices, "none", unknown ids.
expectEqual(catalog.activeSets(choices: [:]).map(\.1.id), ["lean4", "gemoji"], "defaults")
expectEqual(catalog.activeSets(choices: ["prover": "agda"]).map(\.1.id), ["agda", "gemoji"], "choose agda")
expectEqual(catalog.activeSets(choices: ["emoji": "none"]).map(\.1.id), ["lean4"], "emoji off")
expectEqual(catalog.activeSets(choices: ["prover": "nope"]).map(\.1.id), ["lean4", "gemoji"], "unknown falls back")

// Real data spot checks.
let lean = SymbolTable(try catalog.table(choices: [:]).entries)
expectEqual(lean.symbol(for: "to"), "→", "\\to")
expectEqual(lean.symbol(for: "N"), "ℕ", "\\N (Lean)")
expectEqual(lean.symbol(for: ":+1:"), "👍", "\\:+1:")
expectEqual(lean.symbol(for: ":t"), "⦂", "\\:t still Lean's")
check(lean.candidates(prefix: ":hea").contains { $0.command == ":heart:" }, "\\:hea suggests :heart:")
let agda = SymbolTable(try catalog.table(choices: ["prover": "agda", "emoji": "none"]).entries)
expectEqual(agda.symbol(for: "bN"), "ℕ", "\\bN (Agda)")
expectEqual(agda.symbol(for: ":smile:"), nil, "emoji off")

// MARK: - Composer

let table = SymbolTable(["to": "→", "top": "⊤", "tau": "τ", "alpha": "α", ":smile:": "😄"])

/// Feeds keys; returns everything committed and whether every key was handled.
func type(_ keys: [Composer.Key], into c: Composer = Composer(table: table)) -> (String, Bool, Composer) {
    var out = ""
    var handled = true
    for k in keys {
        let e = c.handle(k)
        out += e.commit
        handled = handled && e.handled
    }
    return (out, handled, c)
}
func chars(_ s: String) -> [Composer.Key] { s.map { $0 == "\\" ? .backslash : .text(String($0)) } }

expectEqual(type(chars("a")).0, "a", "idle text passes through")
expectEqual(type([.space]).1, false, "idle space goes to the app")
expectEqual(type(chars("\\to") + [.space]).0, "→ ", "\\to space")
expectEqual(type(chars("\\to") + [.enter]).0, "→", "\\to return")
expectEqual(type(chars("\\tox") + [.space]).0, "\\tox ", "no match keeps the text")
expectEqual(type(chars("\\to\\to") + [.space]).0, "→→ ", "backslash chains")
expectEqual(type(chars("\\\\to")).0, "\\to", "\\\\ types a backslash, then plain text")
expectEqual(type(chars("\\:smile:") + [.space]).0, "😄 ", "emoji")

// Ordering and Tab cycling: "t" → to, tau, top (shorter first, then alphabetical).
var (_, _, c) = type(chars("\\t"))
expectEqual(c.candidates.map(\.command), ["to", "tau", "top"], "candidates for t")
expectEqual(c.highlighted, nil, "nothing highlighted without an exact match")
_ = c.handle(.tab); expectEqual(c.markedText, "\\to", "tab 1")
_ = c.handle(.tab); expectEqual(c.markedText, "\\tau", "tab 2")
_ = c.handle(.tab); expectEqual(c.markedText, "\\top", "tab 3")
_ = c.handle(.tab); expectEqual(c.markedText, "\\to", "tab wraps")
_ = c.handle(.backTab); expectEqual(c.markedText, "\\top", "shift-tab wraps back")
expectEqual(c.handle(.space).commit, "⊤ ", "space inserts the chosen suggestion")

// The first Tab skips an exact match.
(_, _, c) = type(chars("\\to"))
expectEqual(c.highlighted, 0, "exact match highlighted")
_ = c.handle(.tab); expectEqual(c.markedText, "\\top", "tab past the exact match")

// Typing after choosing continues from the choice; Delete edits it.
expectEqual(type(chars("\\a") + [.tab] + chars("x") + [.space]).0, "\\alphax ", "type after tab")
expectEqual(type(chars("\\a") + [.tab, .backspace, .space]).0, "\\alph ", "delete after tab")

// Arrows choose only while there are suggestions.
expectEqual(type(chars("\\t") + [.down, .down, .enter]).0, "τ", "down down return")
let (out, handled, _) = type(chars("\\zz") + [.down])
expectEqual(out, "\\zz", "down without suggestions ends the command")
expectEqual(handled, false, "...and the app gets the arrow")

// No suggestions means it can't succeed.
(_, _, c) = type(chars("\\zz"))
check(c.candidates.isEmpty && c.match == nil, "\\zz has no suggestions")
_ = c.handle(.tab); expectEqual(c.markedText, "\\zz", "tab with nothing to complete does nothing")

// Cancelling.
expectEqual(type(chars("\\") + [.backspace]).0, "", "delete on a bare backslash removes it")
(_, _, c) = type(chars("\\") + [.backspace]); check(!c.isComposing, "…and ends the command")
expectEqual(type(chars("\\to") + [.escape]).0, "\\to", "esc keeps the text")
expectEqual(type(chars("\\to") + [.other]).0, "\\to", "other keys keep the text")
expectEqual(type(chars("\\to") + [.other]).1, false, "…and go to the app")
(_, _, c) = type(chars("\\to")); expectEqual(c.abandon(), "\\to", "abandon")

print(failures == 0 ? "All \(checks) checks passed." : "\(failures) of \(checks) checks failed.")
exit(failures == 0 ? 0 : 1)
