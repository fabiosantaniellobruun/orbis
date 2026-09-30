import AppKit

/// Finestra trasparente che ospita il menu. Non prende mai il focus, così l'app da cui parte
/// il trascinamento resta attiva.
final class RadialPanel: NSPanel {
  init(contentView: NSView, side: CGFloat) {
    super.init(
      contentRect: NSRect(x: 0, y: 0, width: side, height: side),
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
    animationBehavior = .none
    // Sempre scuro: il menu compare sopra qualsiasi cosa, e con il vetro chiaro le icone scure
    // si perdono sugli sfondi scuri.
    appearance = NSAppearance(named: .darkAqua)
    // Impostato esplicitamente: altrimenti le zone trasparenti lasciano passare clic e rilasci.
    ignoresMouseEvents = false
    self.contentView = contentView
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
