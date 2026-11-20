# Architecture

Unicode Symbols Input is a macOS input method. Type a backslash command in any app (`\to`,
`\all`, `\:smile:`) and it becomes the symbol (`→`, `∀`, 😄), with suggestions as you type
and Tab completion.

It is opinionated: it ships curated **symbol sets**, grouped into **classes**, rather than a
general-purpose command editor. It is written from scratch; the idea of a backslash-command
input method comes from [Math Symbols Input](https://github.com/knrafto/MathSymbolsInput).

## Symbol sets and classes

A **symbol set** is one table of commands, such as Lean 4's abbreviations. A **class** groups
sets that do the same job, so that a user picks exactly one of them:

| Class    | Sets            | Default | Command style   |
|----------|-----------------|---------|-----------------|
| Prover   | Lean 4, Agda    | Lean 4  | `\to`, `\bN`    |
| Emoji    | Gemoji          | Gemoji  | `\:smile:`      |

`Sets/catalog.json` is the source of truth for classes, their sets, defaults and data sources.

### The rules

1. **At most one set per class is active.** Each class has its own choice: a set, or `none`.
   Nothing ever merges two sets of the same class.
2. **Sets in the same class may conflict.** Lean 4 and Agda both define `\to`, and disagree on
   others (`\N` is ℕ in Lean, `\bN` in Agda). That is fine, because only one of them is ever active.
3. **Sets in different classes must never conflict.** No command name may appear in a set of one
   class and in any set of another class, whichever sets are chosen. This is checked against
   *every* set of each class, not only the defaults, so any combination of choices is safe.

Rule 3 is what lets classes be switched independently: choosing an emoji set can never change
what a prover command does, and vice versa. It is a directive for every future class and set.
At the time of writing it holds trivially, since Gemoji commands are all `:name:` and no prover
command has that form. Lean's `\:`, `\::`, `\:=` and `\:t` sit next to it but are different
names; sharing a prefix is allowed (see below).

### Where the rules are enforced

- **Tests (the gate).** `./build.sh` runs the test suite before it builds anything, and
  `./install.sh` runs `./build.sh`. The suite fails on any cross-class conflict
  (`Catalog.crossClassConflicts`), listing each command and the two sets. It also merges every
  combination of one set per class (including `none`) and fails if any command is claimed twice.
  So a catalog that breaks rule 3 cannot be built or installed.
- **The catalog's structure.** `Catalog.structuralProblems` (also run by the tests) rejects
  duplicate class or set ids, a default that isn't one of the class's sets, an empty class, and
  a set named `none`.
- **Runtime (safety net only).** `Catalog.table(choices:)` merges active sets in catalog order,
  first claim wins, and returns anything it skipped. The input method logs that as a fault. With a
  catalog that passed the tests this never happens.
- **Selection.** The stored choice is one value per class (`[classID: setID]`), so "two sets of
  one class" cannot even be expressed. An unknown id falls back to the class default.

`scripts/update-sets.py` only converts upstream data; it does not check the rules. Always run
`./build.sh test` after updating sets.

### Prefixes are not conflicts

A command is replaced only when it matches a set's command *exactly* (on Space, Return or `\`).
Suggestions are prefix matches, so `\:` (Lean's `∶`) and `\:smile:` can coexist: typing `\:`
shows both in the suggestion list, and Space on `\:` still gives `∶`. Rule 3 is about exact
names only.

### Adding a set or a class

1. Add the set to a class in `Sets/catalog.json`, with `source.format` one of `flat`
   (`{"command": "symbol"}`), `agda-keymap` or `gemoji`. Add a parser in
   `scripts/update-sets.py` for a new format.
2. Run `scripts/update-sets.py <set-id>` to write `Sets/<file>` and its licence text.
3. Run `./build.sh test`. If it reports cross-class conflicts, the new set (or class) has to
   rename those commands. A new class should choose a command style that cannot collide with
   the others, as Emoji does with `:name:`.

## Data format

Each set is a flat JSON object, `{"command": "replacement"}`, with the command written
without its backslash and sorted by command. `update-sets.py` normalises upstream data:

- Lean's `$CURSOR` marker is dropped (the cursor ends after the inserted text).
- Entries whose command or replacement contains whitespace are dropped: Space ends a command.
- Commands containing a backslash are dropped: typing `\` always starts a new command, so they
  could never be reached. A literal backslash is built in instead: `\\` types `\`.
- Agda offers several candidates for some commands. The first, Agda's own default, is kept.

The app bundle carries the catalog, every set and the licence texts in
`Contents/Resources/Sets`, so switching sets never needs a rebuild.

## Components

```
                 key events                         insertText / setMarkedText
  app ───────────────────────────▶ InputController ─────────────────────────▶ app
  (any text field)                  │    │     │
                                    │    │     └──▶ CandidatePanel   (own floating window)
                    KeyTranslator ◀─┘    │
                    (layout, dead keys)  ▼
                                      Composer ──▶ SymbolTable ◀── SymbolStore ◀── Catalog
                                   (state machine)  (lookup,        (choices in      (Sets/)
                                                     prefix search)  preferences)
```

`Sources/Core` has no UI or InputMethodKit code and is shared by the app, the tests and
`usi-ctl`:

- **`Catalog`** loads `catalog.json` and set files, resolves the user's choices to active sets,
  merges them, and validates the rules above.
- **`SymbolTable`** holds the merged commands: exact lookup, and prefix search returning
  suggestions shortest first, then alphabetical. The exact match is therefore always first.
- **`Composer`** is the input state machine (below). It takes abstract keys and returns what to
  insert and whether the app should still see the key.

`Sources/App` is the input method:

- **`main.swift`** starts an `IMKServer` on the connection named in `Info.plist`.
- **`InputController`** (one per text field) turns `NSEvent`s into composer keys, inserts text,
  shows the command as underlined marked text, drives the panel, and builds the input menu.
- **`KeyTranslator`** asks the current ASCII-capable keyboard layout what a key types, with
  dead keys, via `UCKeyTranslate`. An input method receives raw key events, so it has to do this
  itself to respect Dvorak, British, ⌥-accents and so on.
- **`CandidatePanel`** is the suggestion list (below).
- **`SymbolStore`** loads the catalog once, keeps the merged table, and reloads it when the
  choices change.

`Sources/Tools/usi-ctl` registers and enables the input source (Text Input Sources API) and
reads and writes set choices. `Sources/Tools/make-icon` drew `Resources/icon.tiff`.

## Typing behaviour

Idle, every key passes straight through. `\` starts a command:

| Key        | While typing a command                                                       |
|------------|-------------------------------------------------------------------------------|
| text       | extends the command; suggestions update                                      |
| Tab / ⇧Tab | completes: steps forward / back through the suggestions (wraps)              |
| ↓ / ↑      | the same as Tab / ⇧Tab while there are suggestions                          |
| Space      | inserts the symbol, or the text as typed if nothing matches exactly, then a space |
| Return     | the same, without a newline                                                  |
| `\`        | inserts the symbol and starts the next command; `\\` types a backslash       |
| Delete     | removes the last character; on a bare `\`, cancels it                        |
| Esc        | inserts the text as typed                                                    |
| other keys | insert the text as typed, then the app handles the key (e.g. ← moves the cursor) |
| ⌘/⌃ shortcuts | insert the text as typed, then go to the app                              |

The first Tab skips an exact match, since that's already what you typed. Typing after a Tab
continues from the chosen suggestion.

### Feedback

The point of the design is that you can tell whether a command will work *before* pressing
Space:

- The suggestion panel highlights the row Space will insert. If no row is highlighted, Space
  inserts your text unchanged.
- If nothing starts with what you've typed, the panel says "No command starts with \…".
- The underlined text uses the "converted" style when it matches exactly and the "raw" style
  when it doesn't. Many apps draw these differently, but not all, so the panel is the reliable
  signal.

## The suggestion panel

The panel is a borderless, non-activating `NSPanel` owned by the input method process. It never
takes focus or clicks, so it works over any app. The only thing it needs from the app is where
the text is, from `IMKTextInput.attributes(forCharacterIndex:lineHeightRectangle:)`. Apps that
handle CJK input (practically all of them) report this correctly. When an app reports nothing
believable (a zero rect, or one on no screen), the panel appears by the mouse pointer instead.
It goes below the line of text, or above if there's no room, and shows 8 rows, scrolling with
the selection.

`IMKCandidates`, the system's own candidate window, was not used. It is awkward to drive from a
third-party input method and can't show the symbol, the command and the "no match" state in
one place.

Tab completion does not depend on the panel at all: the completed command replaces the
underlined text in the app itself.

## Preferences

The input method's preferences domain is its bundle id,
`org.100proof.inputmethod.UnicodeSymbolsInput`. `ActiveSets` is `{classID: setID | "none"}`;
a missing class means its default. It is written by the input menu and by `usi-ctl use`, and
re-read whenever a text field gains focus.

## Build, install, test

There is no Xcode project. `build.sh` calls `swiftc` directly (Command Line Tools are enough):
tests first, then the app bundle (ad-hoc signed) and `usi-ctl`, which is also copied into the
bundle (`Contents/MacOS/usi-ctl`) so an installed copy can register itself. `UNIVERSAL=1`
builds arm64 and x86_64 and joins them with `lipo`. `install.sh` copies the bundle
to `~/Library/Input Methods`, stops the running copy so the new code loads, and registers and
enables the input source. The tests are a plain executable (`Tests/main.swift`) rather than
XCTest, for the same reason.

`package.sh` (maintainers) wraps a universal build in a `.pkg` with `pkgbuild`/`productbuild`.
The package installs into `/Library/Input Methods` (non-relocatable) and its `postinstall`
script (`Resources/pkg/scripts/postinstall`) registers the input source for the console user
via the bundled `usi-ctl`. Signing and notarization are opt-in through environment variables.
Building from source is the supported install; the package is not distributed yet.

The tests cover the catalog rules against the real data, and the composer's behaviour
(completion order, Tab cycling, accepting, cancelling, `\\`). The InputMethodKit glue and the
panel are checked by hand.
