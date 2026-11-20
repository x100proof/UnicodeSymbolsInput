import Carbon
import Cocoa
import InputMethodKit

/// One per text field. Translates key events into `Composer.Key`s, applies the
/// composer's effects to the app (insert text, show underlined marked text)
/// and drives the suggestion panel.
@objc(InputController)
final class InputController: IMKInputController {
    private let store = SymbolStore.shared
    private lazy var composer = Composer(table: store.table)
    private var generation = -1
    private let keys = KeyTranslator()

    // MARK: Events

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown else { return false }
        syncTable()

        // Shortcuts belong to the app. Finish any command as typed first.
        if !event.modifierFlags.intersection([.command, .control]).isEmpty {
            finishRaw()
            return false
        }

        guard let text = keys.text(for: event) else {
            finishRaw()
            return false
        }
        if text.isEmpty {  // a dead key is waiting for its letter
            refresh()
            return true
        }

        // A key yields printable text, a special key, or (after a dead key)
        // printable text followed by a special key: "´" then a space, say.
        var printable = text
        var special: Composer.Key?
        if let last = text.unicodeScalars.last, Self.isSpecial(last) {
            printable = String(String.UnicodeScalarView(text.unicodeScalars.dropLast()))
            special = last == "\\" ? .backslash : Self.specialKey(event)
        }

        var handled = true
        if !printable.isEmpty { handled = apply(composer.handle(.text(printable))) }
        if let special { handled = apply(composer.handle(special)) && handled }
        refresh()
        // Text before an unhandled special key was inserted by us, so the app
        // only needs the special key itself (e.g. an arrow to move the cursor).
        return handled
    }

    /// Space, backslash, and control characters (Tab, Return, arrows, Delete, …).
    private static func isSpecial(_ c: Unicode.Scalar) -> Bool {
        c.value <= 0x20 || c == "\\" || (0x7F...0x9F).contains(c.value)
    }

    private static func specialKey(_ event: NSEvent) -> Composer.Key {
        switch Int(event.keyCode) {
        case kVK_Space: return .space
        case kVK_Tab: return event.modifierFlags.contains(.shift) ? .backTab : .tab
        case kVK_Return, kVK_ANSI_KeypadEnter: return .enter
        case kVK_Escape: return .escape
        case kVK_Delete: return .backspace
        case kVK_UpArrow: return .up
        case kVK_DownArrow: return .down
        default: return .other
        }
    }

    /// Inserts the effect's text; returns whether the key was consumed.
    private func apply(_ effect: Composer.Effect) -> Bool {
        if !effect.commit.isEmpty {
            client()?.insertText(effect.commit, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        return effect.handled
    }

    private func finishRaw() {
        let pending = keys.pendingDeadKey
        keys.reset()
        _ = apply(Composer.Effect(commit: composer.abandon() + pending))
        refresh()
    }

    // MARK: Display

    /// Shows the composition as underlined marked text and updates the panel.
    private func refresh() {
        guard let client = client() else { return }
        let marked = composer.markedText + keys.pendingDeadKey
        let length = (marked as NSString).length
        // An exact match is marked as "converted" text (often a thicker
        // underline); a command that matches nothing yet as raw text.
        let style = composer.match != nil ? kTSMHiliteConvertedText : kTSMHiliteRawText
        var attributes: [NSAttributedString.Key: Any] = [:]
        if let marks = mark(forStyle: style, at: NSRange(location: 0, length: length)) {
            for (key, value) in marks {
                if let key = key as? String { attributes[NSAttributedString.Key(key)] = value }
            }
        }
        client.setMarkedText(NSAttributedString(string: marked, attributes: attributes),
                             selectionRange: NSRange(location: length, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))

        guard composer.isComposing, !composer.typed.isEmpty || composer.selection != nil else {
            CandidatePanel.shared.hide()
            return
        }
        CandidatePanel.shared.show(
            candidates: composer.candidates, highlighted: composer.highlighted,
            typed: composer.typed, near: caretRect(client))
    }

    /// Where the marked text is on screen, if the app says so believably.
    private func caretRect(_ client: IMKTextInput & NSObjectProtocol) -> NSRect? {
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        let plausible = rect != .zero && NSScreen.screens.contains { $0.frame.intersects(rect.insetBy(dx: -1, dy: -1)) }
        return plausible ? rect : nil
    }

    // MARK: Lifecycle

    /// Picks up a new table (after a set change) once no command is in progress.
    private func syncTable() {
        guard generation != store.generation, !composer.isComposing else { return }
        composer.table = store.table
        generation = store.generation
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        store.reloadIfChanged()
        syncTable()
    }

    override func deactivateServer(_ sender: Any!) {
        finishRaw()
        CandidatePanel.shared.hide()
        super.deactivateServer(sender)
    }

    /// The app ends the composition (click elsewhere, switch input source, …).
    override func commitComposition(_ sender: Any!) {
        finishRaw()
    }

    // MARK: Input menu: one set per class

    /// (class id, set id or "none") for each choice item, indexed by menu tag.
    private var menuChoices: [(String, String)] = []

    override func menu() -> NSMenu! {
        let menu = NSMenu()
        menuChoices = []
        guard let catalog = store.catalog else {
            menu.addItem(withTitle: "Symbol sets failed to load", action: nil, keyEquivalent: "")
            return menu
        }
        for cls in catalog.classes {
            if menu.numberOfItems > 0 { menu.addItem(.separator()) }
            let header = NSMenuItem(title: cls.name, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            let active = store.active(in: cls)
            for (id, name) in cls.sets.map({ ($0.id, $0.name) }) + [(Catalog.none, "None")] {
                let item = NSMenuItem(title: name, action: #selector(chooseSet(_:)), keyEquivalent: "")
                item.target = self
                item.tag = menuChoices.count
                item.state = id == active ? .on : .off
                item.indentationLevel = 1
                menu.addItem(item)
                menuChoices.append((cls.id, id))
            }
        }
        return menu
    }

    @objc private func chooseSet(_ sender: Any?) {
        // InputMethodKit passes a dictionary holding the menu item, not the item itself.
        let item = (sender as? NSMenuItem)
            ?? ((sender as? [String: Any])?[kIMKCommandMenuItemName] as? NSMenuItem)
        guard let item, menuChoices.indices.contains(item.tag) else { return }
        let (classID, setID) = menuChoices[item.tag]
        store.choose(setID, in: classID)
        syncTable()
    }
}
