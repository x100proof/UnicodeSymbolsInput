# Unicode Symbols Input

A macOS input method for typing symbols by name in any app: `\to` → `→`, `\all` → `∀`,
`\:tada:` → 🎉. As you type, a list shows every command that starts with what you've typed, so
you can see whether it will work, and **Tab** completes.

```
\tri
 ┌──────────────────────────────────────────────┐
 │ △  \triangle                                 │
 │ ▽  \triangledown                             │
 │ ◁  \triangleleft                             │
 │ …                                            │
 │ ⇥ complete  ↑↓ choose  ␣ insert · 7 matches  │
 └──────────────────────────────────────────────┘
```

It comes with symbol sets in two classes. You use one set from each class (or none):

| Class  | Sets                                                     | Examples                     |
|--------|----------------------------------------------------------|------------------------------|
| Prover | **Lean 4** (default), Agda                               | `\to` →, `\all` ∀, `\N` ℕ (Lean) / `\bN` ℕ (Agda) |
| Emoji  | **Gemoji** (default): GitHub's emoji shortcodes          | `\:smile:` 😄, `\:+1:` 👍     |

Sets from different classes never share a command, so emoji can't get in the way of prover
symbols. [ARCHITECTURE.md](ARCHITECTURE.md) explains the rules and how the input method works.

## Install

Needs macOS 12 or later and the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone <this repo> && cd UnicodeSymbolsInput
./install.sh                       # Lean 4 + Gemoji
./install.sh --prover agda         # Agda + Gemoji
./install.sh --emoji none          # no emoji
```

Then choose **Unicode Symbols** in the input menu in the menu bar. If it isn't listed, log out
and back in once, or add it under System Settings → Keyboard → Input Sources → Edit → + →
English.

## Typing

| Key              | Does                                                                   |
|------------------|------------------------------------------------------------------------|
| `\` + name       | start a command; suggestions appear                                    |
| Tab / ⇧Tab, ↓ / ↑ | complete: step through the suggestions                                |
| Space            | insert the highlighted symbol and a space (your text as typed if none is highlighted) |
| Return           | the same, without the space                                            |
| `\`              | insert, and start the next command (`\to\to` → `→→`)                   |
| `\\`             | a literal backslash                                                    |
| Delete           | remove a character; on a bare `\`, cancel                              |
| Esc              | keep your text as typed                                                |

## Switching sets

From the input menu (the Unicode Symbols icon in the menu bar), tick a set under each class.
Or from the terminal:

```sh
build/usi-ctl status            # classes, sets, and which are active
build/usi-ctl use prover agda
build/usi-ctl use emoji none
```

Changes apply from the next text field you click into, and are kept across reinstalls.

## Updating the symbol data

```sh
scripts/update-sets.py          # all sets; or name some: scripts/update-sets.py gemoji
./build.sh test                 # must pass: checks no command is shared between classes
./install.sh
```

## Uninstall

```sh
./install.sh --uninstall
```

## Credits

- Inspired by [Math Symbols Input](https://github.com/knrafto/MathSymbolsInput) by Kyle
  Raftogianis. This is a separate implementation, written from scratch.
- Lean 4 abbreviations from [leanprover/vscode-lean4](https://github.com/leanprover/vscode-lean4)
  (Apache License 2.0).
- Agda abbreviations from [banacorn/agda-mode-vscode](https://github.com/banacorn/agda-mode-vscode)
  (MIT), generated from Agda's `agda-input.el`.
- Emoji shortcodes from [github/gemoji](https://github.com/github/gemoji) (MIT).

The licence texts for the bundled data are in `Sets/licenses/`.

## Licence

MIT, see [LICENSE](LICENSE). The bundled symbol data keeps its own licences (above).
