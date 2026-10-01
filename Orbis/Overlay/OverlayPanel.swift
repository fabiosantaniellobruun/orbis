import AppKit

/// Finestra trasparente sopra tutte le altre. Non prende mai il focus, così l'app da cui parte
/// il trascinamento resta attiva.
final class OverlayPanel: NSPanel {
  /// - Parameter catchesTransparentAreas: se `true` la finestra riceve clic e rilasci anche dove
  ///   è trasparente; se `false` lì passano a ciò che sta sotto.
  init(contentView: NSView, size: NSSize, catchesTransparentAreas: Bool) {
    super.init(
      contentRect: NSRect(origin: .zero, size: size),
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
    // Il sistema lascia passare i clic nelle zone trasparenti solo finché questa proprietà
    // non viene toccata: impostarla, anche a `false`, glieli fa ricevere tutti.
    if catchesTransparentAreas {
      ignoresMouseEvents = false
    }
    self.contentView = contentView
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
