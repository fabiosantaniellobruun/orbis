import AppKit

/// La combinazione che apre il pannello: i tasti da tenere premuti (di base ⇧) e il tasto del mouse
/// con cui fare clic (di base il destro).
nonisolated struct ClipTrigger: Codable, Equatable, Sendable {
  var keys: TriggerShortcut
  /// Il tasto del mouse, numerato come fa il sistema: 0 il sinistro, 1 il destro, 2 il centrale,
  /// 3 e oltre i laterali.
  var mouseButton: Int64

  static let standard = ClipTrigger(keys: TriggerShortcut(modifiers: [.shift]), mouseButton: 1)

  private static let defaultsKey = "clipTrigger"

  /// Senza tasti la combinazione scatterebbe a ogni clic.
  var isValid: Bool { keys.isValid }

  /// Se un clic con questo tasto del mouse e questi modificatori è la combinazione.
  func matches(button: Int64, flags: CGEventFlags) -> Bool {
    guard isValid, button == mouseButton else { return false }
    // I bit dei modificatori di `CGEventFlags` e di `NSEvent.ModifierFlags` coincidono.
    return keys.isHeld(modifiers: NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue))) { keyCode in
      CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
    }
  }

  var buttonName: String {
    switch mouseButton {
    case 0: "clic"
    case 1: "clic destro"
    case 2: "clic centrale"
    default: "tasto \(mouseButton + 1) del mouse"
    }
  }

  /// "⇧ + clic destro".
  var displayString: String {
    "\(keys.displayString) + \(buttonName)"
  }

  // MARK: Salvataggio

  static func load(from defaults: UserDefaults = .standard) -> ClipTrigger {
    guard let data = defaults.data(forKey: defaultsKey),
          let trigger = try? JSONDecoder().decode(ClipTrigger.self, from: data),
          trigger.isValid
    else { return .standard }
    return trigger
  }

  func save(to defaults: UserDefaults = .standard) {
    guard let data = try? JSONEncoder().encode(self) else { return }
    defaults.set(data, forKey: Self.defaultsKey)
  }
}
