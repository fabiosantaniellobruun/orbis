import AppKit
import Testing
@testable import Radial

struct TriggerShortcutTests {
  /// Un archivio a sé, per non toccare le preferenze dell'app.
  func makeDefaults() -> UserDefaults {
    let suite = "RadialTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
  }

  static let noKeysDown: @Sendable (UInt16) -> Bool = { _ in false }

  // MARK: Nome

  @Test("Il nome si scrive con i simboli, nell'ordine della tastiera", arguments: [
    (NSEvent.ModifierFlags.shift, "⇧"),
    (NSEvent.ModifierFlags([.control, .shift]), "⌃⇧"),
    (NSEvent.ModifierFlags([.shift, .control, .option, .command]), "⌃⌥⇧⌘"),
    (NSEvent.ModifierFlags.option, "⌥"),
    (NSEvent.ModifierFlags.function, "fn"),
    (NSEvent.ModifierFlags([.function, .shift]), "fn⇧"),
  ])
  func displayString(modifiers: NSEvent.ModifierFlags, expected: String) {
    #expect(TriggerShortcut(modifiers: modifiers).displayString == expected)
  }

  @Test("Un tasto normale si scrive dopo i modificatori")
  func displayStringWithKey() {
    #expect(TriggerShortcut(modifiers: [.option], keyCode: 49, keyLabel: "Spazio").displayString == "⌥ Spazio")
    #expect(TriggerShortcut(modifiers: [], keyCode: 49, keyLabel: "Spazio").displayString == "Spazio")
  }

  @Test("I nomi dei tasti senza carattere")
  func keyNames() {
    #expect(KeyNames.label(keyCode: 49, characters: " ") == "Spazio")
    #expect(KeyNames.label(keyCode: 122, characters: nil) == "F1")
    #expect(KeyNames.label(keyCode: 0, characters: "a") == "A")
    #expect(KeyNames.label(keyCode: 200, characters: nil) == "Tasto 200")
  }

  // MARK: Riconoscimento

  @Test("Solo Shift: scatta con Shift e basta")
  func shiftOnly() {
    let shortcut = TriggerShortcut.standard

    #expect(shortcut.isHeld(modifiers: [.shift], isKeyDown: Self.noKeysDown))
    #expect(!shortcut.isHeld(modifiers: [], isKeyDown: Self.noKeysDown))
  }

  @Test("Un modificatore in più è un'altra combinazione", arguments: [
    NSEvent.ModifierFlags([.shift, .command]),
    [.shift, .option],
    [.shift, .control],
  ])
  func extraModifierIsAnotherCombination(flags: NSEvent.ModifierFlags) {
    #expect(!TriggerShortcut.standard.isHeld(modifiers: flags, isKeyDown: Self.noKeysDown))
  }

  @Test("Una combinazione di due modificatori li vuole tutti e due")
  func twoModifiers() {
    let shortcut = TriggerShortcut(modifiers: [.control, .shift])

    #expect(shortcut.isHeld(modifiers: [.control, .shift], isKeyDown: Self.noKeysDown))
    #expect(!shortcut.isHeld(modifiers: [.shift], isKeyDown: Self.noKeysDown))
    #expect(!shortcut.isHeld(modifiers: [.control], isKeyDown: Self.noKeysDown))
  }

  @Test("Le maiuscole bloccate non contano")
  func capsLockIsIgnored() {
    #expect(TriggerShortcut.standard.isHeld(modifiers: [.shift, .capsLock], isKeyDown: Self.noKeysDown))
  }

  @Test("fn acceso dal sistema con le frecce non disturba, a meno che fn sia stata scelta")
  func functionFlag() {
    #expect(TriggerShortcut.standard.isHeld(modifiers: [.shift, .function], isKeyDown: Self.noKeysDown))

    let fn = TriggerShortcut(modifiers: [.function])
    #expect(fn.isHeld(modifiers: [.function], isKeyDown: Self.noKeysDown))
    #expect(!fn.isHeld(modifiers: [], isKeyDown: Self.noKeysDown))
  }

  @Test("Con un tasto normale serve che sia premuto, oltre ai modificatori")
  func regularKey() {
    let shortcut = TriggerShortcut(modifiers: [.option], keyCode: 49, keyLabel: "Spazio")

    #expect(shortcut.isHeld(modifiers: [.option]) { $0 == 49 })
    #expect(!shortcut.isHeld(modifiers: [.option], isKeyDown: Self.noKeysDown))
    #expect(!shortcut.isHeld(modifiers: []) { $0 == 49 })
    #expect(!shortcut.isHeld(modifiers: [.option]) { $0 == 50 })
  }

  @Test("Un tasto normale senza modificatori scatta quando è premuto e nessun modificatore è tenuto")
  func regularKeyAlone() {
    let shortcut = TriggerShortcut(modifiers: [], keyCode: 49, keyLabel: "Spazio")

    #expect(shortcut.isHeld(modifiers: []) { $0 == 49 })
    #expect(!shortcut.isHeld(modifiers: [.shift]) { $0 == 49 })
  }

  @Test("Una combinazione vuota non scatta mai")
  func emptyNeverFires() {
    let empty = TriggerShortcut(modifiers: [])

    #expect(!empty.isValid)
    #expect(!empty.isHeld(modifiers: [], isKeyDown: Self.noKeysDown))
    #expect(!empty.isHeld(modifiers: [.shift], isKeyDown: Self.noKeysDown))
  }

  // MARK: Salvataggio

  @Test("Senza nulla di salvato vale Shift")
  func defaultIsShift() {
    #expect(TriggerShortcut.load(from: makeDefaults()) == .standard)
  }

  @Test("Quel che si salva si ritrova, con tasto ed etichetta")
  func roundTrip() {
    let defaults = makeDefaults()
    let shortcut = TriggerShortcut(modifiers: [.control, .option], keyCode: 49, keyLabel: "Spazio")

    shortcut.save(to: defaults)

    #expect(TriggerShortcut.load(from: defaults) == shortcut)
  }

  @Test("Dati rovinati o una combinazione vuota ridanno Shift, senza rompere nulla")
  func corruptedDataFallsBack() {
    let defaults = makeDefaults()

    defaults.set(Data("non è json".utf8), forKey: TriggerShortcut.storageKey)
    #expect(TriggerShortcut.load(from: defaults) == .standard)

    TriggerShortcut(modifiers: []).save(to: defaults)
    #expect(TriggerShortcut.load(from: defaults) == .standard)
  }

  @Test("Ripristinare toglie la scelta")
  func reset() {
    let defaults = makeDefaults()
    TriggerShortcut(modifiers: [.option]).save(to: defaults)

    TriggerShortcut.reset(in: defaults)

    #expect(TriggerShortcut.load(from: defaults) == .standard)
    #expect(defaults.data(forKey: TriggerShortcut.storageKey) == nil)
  }

  @Test("Si salvano solo i modificatori che contano")
  func onlyRelevantModifiersAreKept() {
    let shortcut = TriggerShortcut(modifiers: [.shift, .capsLock, .numericPad])

    #expect(shortcut.modifiers == [.shift])
    #expect(shortcut == .standard)
  }
}
