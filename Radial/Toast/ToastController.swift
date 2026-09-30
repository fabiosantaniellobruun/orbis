import AppKit
import SwiftUI

/// Mostra l'avviso in un pannello suo, piccolo quanto basta: resta visibile e cliccabile anche
/// dopo che il menu è sparito, senza coprire altro.
final class ToastController {
  private static let size = NSSize(width: 640, height: 80)

  private let model = ToastModel()
  private let panel: OverlayPanel
  private var hideTask: Task<Void, Never>?

  init() {
    let hostingView = FirstMouseHostingView(rootView: ToastView(model: model).ignoresSafeArea())
    hostingView.sizingOptions = []
    hostingView.frame = NSRect(origin: .zero, size: Self.size)
    panel = OverlayPanel(contentView: hostingView, size: Self.size, catchesTransparentAreas: false)
  }

  /// Se l'avviso in vista è quello di un lavoro in corso (e non già il suo esito).
  var isShowingWork: Bool { model.content?.isWorking == true }

  /// - Parameter duration: dopo quanto l'avviso sparisce; `nil` lo lascia finché non ne arriva un altro.
  func show(
    _ content: ToastContent,
    centeredAt point: NSPoint,
    for duration: Duration?,
    onUndo: (() -> Void)? = nil
  ) {
    hideTask?.cancel()
    hideTask = nil

    panel.setFrameOrigin(NSPoint(x: point.x - Self.size.width / 2, y: point.y - Self.size.height / 2))
    panel.orderFrontRegardless()
    model.onUndo = onUndo
    model.content = content

    guard let duration else { return }
    hideTask = Task {
      try? await Task.sleep(for: duration)
      guard !Task.isCancelled else { return }
      model.content = nil
      // Il tempo della dissolvenza, poi la finestra esce davvero.
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      panel.orderOut(nil)
    }
  }
}

/// Il pannello non diventa mai la finestra attiva: senza questo, ogni clic verrebbe speso per
/// "attivarla" invece di arrivare al pulsante.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
