import AppKit

/// Vista di contenuto del pannello: riceve il trascinamento dei file (e il mouse, nel menu di prova)
/// e lo traduce in posizioni relative al centro dell'anello.
final class RadialDropView: NSView {
  /// Posizione del puntatore rispetto al centro, con y verso il basso.
  /// Restituisce `true` se sotto il puntatore c'è un'azione.
  var pointerMoved: ((CGSize, _ isDragging: Bool) -> Bool)?
  var pointerLeft: (() -> Void)?
  var filesDropped: (([URL]) -> Bool)?
  var clicked: (() -> Void)?

  private(set) var isDragInside = false

  override init(frame: NSRect) {
    super.init(frame: frame)
    registerForDraggedTypes([.fileURL])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) non è supportato")
  }

  // Tutti gli eventi arrivano qui, non alla vista SwiftUI sottostante.
  override func hitTest(_ point: NSPoint) -> NSView? {
    frame.contains(point) ? self : nil
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  private func offset(ofWindowPoint point: NSPoint) -> CGSize {
    let local = convert(point, from: nil)
    return CGSize(width: local.x - bounds.midX, height: bounds.midY - local.y)
  }

  // MARK: Mouse (menu di prova)

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(NSTrackingArea(
      rect: .zero,
      options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self
    ))
  }

  override func mouseMoved(with event: NSEvent) {
    _ = pointerMoved?(offset(ofWindowPoint: event.locationInWindow), false)
  }

  override func mouseExited(with event: NSEvent) {
    pointerLeft?()
  }

  override func mouseDown(with event: NSEvent) {
    _ = pointerMoved?(offset(ofWindowPoint: event.locationInWindow), false)
    clicked?()
  }

  // MARK: Trascinamento

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    log.info("Trascinamento entrato nel pannello")
    isDragInside = true
    return operation(for: sender)
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    operation(for: sender)
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    isDragInside = false
    pointerLeft?()
  }

  override func draggingEnded(_ sender: NSDraggingInfo) {
    isDragInside = false
  }

  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let urls = sender.draggingPasteboard.readObjects(
      forClasses: [NSURL.self],
      options: [.urlReadingFileURLsOnly: true]
    ) as? [URL] ?? []
    return filesDropped?(urls) ?? false
  }

  private func operation(for sender: NSDraggingInfo) -> NSDragOperation {
    guard pointerMoved?(offset(ofWindowPoint: sender.draggingLocation), true) == true else { return [] }
    // I modificatori premuti restringono le operazioni ammesse dalla sorgente: si prende la prima
    // disponibile. Mai `.move` o `.delete`, che direbbero al Finder di toccare gli originali.
    let allowed = sender.draggingSourceOperationMask
    return [NSDragOperation.generic, .copy, .link].first(where: allowed.contains) ?? []
  }
}
