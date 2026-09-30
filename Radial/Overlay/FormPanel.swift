import AppKit
import SwiftUI

/// Un pannello che può ricevere la tastiera senza rendere attiva l'app: come Spotlight, scrivi
/// subito e l'app da cui arrivi resta dov'era.
final class FormPanel: NSPanel {
  var onCancel: (() -> Void)?

  init(contentView: NSView, size: NSSize) {
    super.init(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    level = .floating
    collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    hidesOnDeactivate = false
    isReleasedWhenClosed = false
    animationBehavior = .none
    self.contentView = contentView
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func cancelOperation(_ sender: Any?) {
    onCancel?()
  }

  /// Esc chiude il pannello anche quando un campo di testo lo avrebbe preso per sé.
  override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown, event.keyCode == 53 {
      onCancel?()
      return
    }
    super.sendEvent(event)
  }
}

/// Mostra un modulo (Rinomina, Ridimensiona…) in un `FormPanel` vicino al punto indicato, e lo
/// chiude restituendo il focus all'app da cui si veniva.
final class FormPanelHost {
  private static let margin: CGFloat = 20

  private var panel: FormPanel?

  var isPresenting: Bool { panel != nil }

  /// - Parameters:
  ///   - cardSize: la misura della carta di vetro; il pannello è più grande del margine per l'ombra.
  ///   - onCancel: chiamata con Esc.
  func present<Content: View>(_ content: Content, cardSize: CGSize, near point: NSPoint, onCancel: @escaping () -> Void) {
    close()

    let size = NSSize(width: cardSize.width + 2 * Self.margin, height: cardSize.height + 2 * Self.margin)
    let hostingView = NSHostingView(rootView: content.padding(Self.margin).ignoresSafeArea())
    hostingView.sizingOptions = []
    hostingView.frame = NSRect(origin: .zero, size: size)

    let panel = FormPanel(contentView: hostingView, size: size)
    panel.onCancel = onCancel
    panel.setFrameOrigin(origin(for: size, near: point))
    // Da app inattiva il pannello non diventa "key" e i campi restano spenti fino al primo clic.
    NSApp.activate()
    panel.makeKeyAndOrderFront(nil)
    self.panel = panel
  }

  func close() {
    guard panel != nil else { return }
    panel?.orderOut(nil)
    panel = nil
    // Il focus torna all'app da cui si veniva.
    NSApp.hide(nil)
  }

  /// Il pannello sta dove si stava lavorando, senza uscire dallo schermo.
  private func origin(for size: NSSize, near point: NSPoint) -> NSPoint {
    var origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
    if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main {
      let bounds = screen.visibleFrame
      origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
      origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size.height)
    }
    return origin
  }
}
