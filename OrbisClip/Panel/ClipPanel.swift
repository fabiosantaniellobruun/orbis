import AppKit

/// La finestra trasparente del pannello, sopra tutte le altre. A differenza dell'anello di Orbis
/// diventa la finestra che riceve la tastiera, per la ricerca, ma senza attivare l'app: quella in
/// cui si è fatto clic resta in primo piano.
final class ClipPanel: NSPanel {
  /// Restituisce `true` se ha usato il tasto.
  var onKeyDown: ((NSEvent) -> Bool)?
  var onResignKey: (() -> Void)?

  init(contentView: NSView) {
    super.init(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    level = .popUpMenu
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    becomesKeyOnlyIfNeeded = false
    animationBehavior = .none
    // `ignoresMouseEvents` non si tocca: così i clic nelle zone trasparenti passano a ciò che sta
    // sotto, e chiudono il pannello come un clic fuori.
    self.contentView = contentView
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown, onKeyDown?(event) == true { return }
    super.sendEvent(event)
  }

  override func resignKey() {
    super.resignKey()
    onResignKey?()
  }
}
