import AppKit

/// Il tasto, o la combinazione di tasti, da tenere premuti durante un trascinamento per aprire il
/// menu: solo modificatori (⇧, ⌥⇧, ⌃⌥…) oppure modificatori più un tasto normale.
nonisolated struct TriggerShortcut: Codable, Equatable, Sendable {
  /// I modificatori richiesti, come bit di `NSEvent.ModifierFlags`.
  var modifierBits: UInt
  /// Un tasto normale da tenere premuto insieme ai modificatori: il codice virtuale e la sua
  /// etichetta, com'era sulla tastiera di chi l'ha scelto.
  var keyCode: UInt16?
  var keyLabel: String?

  static let standard = TriggerShortcut(modifiers: [.shift])

  /// I modificatori che contano: maiuscole bloccate e simili non fanno parte della combinazione.
  static let relevantModifiers: NSEvent.ModifierFlags = [.shift, .control, .option, .command, .function]

  private static let defaultsKey = "triggerShortcut"

  init(modifiers: NSEvent.ModifierFlags, keyCode: UInt16? = nil, keyLabel: String? = nil) {
    modifierBits = modifiers.intersection(Self.relevantModifiers).rawValue
    self.keyCode = keyCode
    self.keyLabel = keyLabel
  }

  var modifiers: NSEvent.ModifierFlags {
    NSEvent.ModifierFlags(rawValue: modifierBits).intersection(Self.relevantModifiers)
  }

  /// Una combinazione vuota scatterebbe sempre: non è una combinazione.
  var isValid: Bool {
    !modifiers.isEmpty || keyCode != nil
  }

  var usesRegularKey: Bool { keyCode != nil }

  // MARK: Uso

  /// Se, dato lo stato dei tasti adesso, la combinazione è tenuta premuta. I modificatori devono
  /// essere esattamente quelli scelti: con ⌘ o ⌥ in più si è in un'altra combinazione.
  func isHeld(modifiers flags: NSEvent.ModifierFlags, isKeyDown: (UInt16) -> Bool) -> Bool {
    guard isValid else { return false }
    let expected = modifiers
    var current = flags.intersection(Self.relevantModifiers)
    // Il sistema accende "fn" da solo con le frecce e i tasti funzione: conta solo se la si è scelta.
    if !expected.contains(.function) {
      current.remove(.function)
    }
    guard current == expected else { return false }
    guard let keyCode else { return true }
    return isKeyDown(keyCode)
  }

  // MARK: Nome

  /// Come si scrive sulla tastiera: "⇧", "⌃⌥", "⌥ Spazio".
  var displayString: String {
    let modifiers = modifiers
    var symbols = ""
    if modifiers.contains(.function) { symbols += "fn" }
    if modifiers.contains(.control) { symbols += "⌃" }
    if modifiers.contains(.option) { symbols += "⌥" }
    if modifiers.contains(.shift) { symbols += "⇧" }
    if modifiers.contains(.command) { symbols += "⌘" }
    guard let keyLabel else { return symbols }
    return symbols.isEmpty ? keyLabel : "\(symbols) \(keyLabel)"
  }

  // MARK: Salvataggio

  static func load(from defaults: UserDefaults = .standard) -> TriggerShortcut {
    guard let data = defaults.data(forKey: defaultsKey),
          let shortcut = try? JSONDecoder().decode(TriggerShortcut.self, from: data),
          shortcut.isValid
    else { return .standard }
    return shortcut
  }

  func save(to defaults: UserDefaults = .standard) {
    guard let data = try? JSONEncoder().encode(self) else { return }
    defaults.set(data, forKey: Self.defaultsKey)
  }

  static func reset(in defaults: UserDefaults = .standard) {
    defaults.removeObject(forKey: defaultsKey)
  }

  static var storageKey: String { defaultsKey }
}

/// I nomi dei tasti che non hanno un carattere da mostrare.
nonisolated enum KeyNames {
  private static let special: [UInt16: String] = [
    49: "Spazio", 36: "Invio", 76: "Invio (tastierino)", 48: "Tab", 53: "Esc", 51: "⌫", 117: "⌦",
    123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "Fine", 116: "Pag↑", 121: "Pag↓",
    122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
    109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
    79: "F18", 80: "F19", 90: "F20",
  ]

  static func label(keyCode: UInt16, characters: String?) -> String {
    if let name = special[keyCode] { return name }
    if let characters = characters?.trimmingCharacters(in: .whitespacesAndNewlines), !characters.isEmpty {
      return characters.uppercased()
    }
    return "Tasto \(keyCode)"
  }
}
