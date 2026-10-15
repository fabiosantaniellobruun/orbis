import AppKit

/// Intercetta la combinazione del mouse in tutto il sistema e la toglie all'app sotto il puntatore,
/// che altrimenti aprirebbe il suo menu contestuale. Un monitor globale degli eventi il clic lo
/// vede ma non lo ferma: serve un event tap, e il sistema lo crea solo con il permesso
/// Accessibilità.
///
/// Il tap gira sul run loop principale, quindi lo stato si tocca sempre dallo stesso thread.
nonisolated final class ClickTrigger: @unchecked Sendable {
  /// Chiamato sul thread principale con il punto del clic, in coordinate globali con l'origine
  /// in alto a sinistra (quelle di Core Graphics).
  var onTrigger: (@MainActor (CGPoint) -> Void)?

  private var tap: CFMachPort?
  private var trigger = ClipTrigger.standard
  /// Il tasto del mouse premuto con la combinazione: anche il suo rilascio non deve arrivare all'app.
  private var swallowedButton: Int64?

  var isRunning: Bool { tap != nil }

  /// Restituisce `false` se il sistema non crea il tap: manca il permesso Accessibilità.
  @discardableResult
  func start() -> Bool {
    guard tap == nil else { return true }
    trigger = .load()
    let types: [CGEventType] = [
      .leftMouseDown, .leftMouseUp, .leftMouseDragged,
      .rightMouseDown, .rightMouseUp, .rightMouseDragged,
      .otherMouseDown, .otherMouseUp, .otherMouseDragged,
    ]
    let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    guard let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: mask,
      callback: clickTriggerCallback,
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    ) else { return false }
    let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    self.tap = tap
    return true
  }

  /// Rilegge la combinazione, dopo una modifica nelle impostazioni.
  func reload() {
    trigger = .load()
  }

  fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    let pass = Unmanaged.passUnretained(event)
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      // Il sistema spegne il tap se una risposta tarda: lo si riaccende.
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return pass
    case .leftMouseDown, .rightMouseDown, .otherMouseDown:
      let button = event.getIntegerValueField(.mouseEventButtonNumber)
      guard swallowedButton == nil, trigger.matches(button: button, flags: event.flags) else { return pass }
      swallowedButton = button
      let location = event.location
      Task { @MainActor in self.onTrigger?(location) }
      return nil
    case .leftMouseUp, .rightMouseUp, .otherMouseUp:
      guard let swallowedButton, event.getIntegerValueField(.mouseEventButtonNumber) == swallowedButton else { return pass }
      self.swallowedButton = nil
      return nil
    default:
      guard let swallowedButton, event.getIntegerValueField(.mouseEventButtonNumber) == swallowedButton else { return pass }
      return nil
    }
  }
}

nonisolated private func clickTriggerCallback(
  proxy: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let userInfo else { return Unmanaged.passUnretained(event) }
  return Unmanaged<ClickTrigger>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
}

/// Il permesso Accessibilità: serve per intercettare il clic e per incollare.
enum Accessibility {
  static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

  static var isTrusted: Bool { AXIsProcessTrusted() }

  /// Mostra la richiesta del sistema, se il permesso non c'è ancora.
  static func requestIfNeeded() {
    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
  }
}
