import AppKit
import Observation
import SwiftUI

/// Apre il pannello alla combinazione, lo chiude con Esc o con un clic fuori, e incolla l'elemento
/// scelto dove si era fatto clic.
@Observable final class ClipController {
  /// Se il sistema ha concesso il permesso Accessibilità e il clic viene intercettato.
  private(set) var hasAccessibility = false

  @ObservationIgnored private let store: ClipStore
  @ObservationIgnored private let model: ClipPanelModel
  @ObservationIgnored private let trigger = ClickTrigger()
  @ObservationIgnored private var panel: ClipPanel?
  /// Il punto del clic che ha aperto il pannello, in coordinate globali con l'origine in alto a
  /// sinistra; `nil` per il pannello di prova.
  @ObservationIgnored private var clickPoint: CGPoint?
  @ObservationIgnored private var outsideClickMonitor: Any?
  @ObservationIgnored private var permissionTask: Task<Void, Never>?

  init(store: ClipStore) {
    self.store = store
    model = ClipPanelModel(store: store)
  }

  func start() {
    trigger.onTrigger = { [weak self] point in self?.triggered(at: point) }
    Accessibility.requestIfNeeded()
    // Il permesso si concede nelle impostazioni di sistema, mentre l'app è aperta: si riprova
    // finché non arriva.
    permissionTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        if Accessibility.isTrusted, self.trigger.start() {
          self.hasAccessibility = true
          log.info("Clic intercettato")
          return
        }
        try? await Task.sleep(for: .seconds(2))
      }
    }
  }

  /// Il pannello al centro dello schermo, senza un punto in cui incollare: l'elemento scelto
  /// finisce negli appunti.
  func showPreview() {
    clickPoint = nil
    guard let frame = NSScreen.main?.visibleFrame else { return }
    show(at: NSPoint(x: frame.midX - 150, y: frame.midY))
  }

  private func triggered(at point: CGPoint) {
    clickPoint = point
    let target = PasteTarget.inspect(at: point)
    log.info("Pannello aperto sopra \(String(describing: target.kind), privacy: .public): \(target.description, privacy: .public)")
    show(at: NSEvent.mouseLocation)
  }

  // MARK: Pannello

  private func show(at location: NSPoint) {
    let screen = NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
    guard let visible = screen?.visibleFrame else { return }
    let size = CGSize(width: ClipCard.size.width + 40, height: min(visible.height, 720))
    let gap: CGFloat = 10
    let side: ClipPanelModel.Side = location.x + gap + size.width <= visible.maxX ? .right : .left
    let x = side == .right ? location.x + gap : location.x - gap - size.width
    let y = min(max(location.y - size.height / 2, visible.minY), visible.maxY - size.height)
    model.reset(side: side, anchorY: y + size.height - location.y, size: size)

    let panel = panel ?? makePanel()
    panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    // Il pannello riceve la tastiera senza attivare Orbis Clip.
    panel.makeKeyAndOrderFront(nil)
    Task {
      try? await Task.sleep(for: .milliseconds(16))
      model.hasAppeared = true
    }

    if outsideClickMonitor == nil {
      // I clic nelle altre app, e quelli che attraversano le zone trasparenti del pannello.
      outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
        matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
      ) { [weak self] _ in
        self?.close()
      }
    }
  }

  private func makePanel() -> ClipPanel {
    let view = NSHostingView(rootView: ClipPanelView(model: model) { [weak self] item in
      self?.choose(item)
    })
    view.sizingOptions = []
    let panel = ClipPanel(contentView: view)
    panel.onKeyDown = { [weak self] event in self?.handleKey(event) ?? false }
    panel.onResignKey = { [weak self] in self?.close() }
    self.panel = panel
    return panel
  }

  func close() {
    if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    outsideClickMonitor = nil
    guard let panel, panel.isVisible else { return }
    panel.orderOut(nil)
    model.hasAppeared = false
  }

  // MARK: Tastiera

  private func handleKey(_ event: NSEvent) -> Bool {
    switch event.keyCode {
    case 53: // Esc
      close()
    case 36, 76: // Invio
      if let item = model.selectedItem { choose(item) }
    case 125: // ↓
      model.moveSelection(by: 1)
    case 126: // ↑
      model.moveSelection(by: -1)
    case 51: // ⌫
      if !model.query.isEmpty { model.query.removeLast() }
      model.selectedID = nil
    default:
      guard event.modifierFlags.isDisjoint(with: [.command, .control]),
            let characters = event.characters, !characters.isEmpty,
            characters.unicodeScalars.allSatisfy(Self.isTypable)
      else { return false }
      // Uno spazio all'inizio non cerca nulla.
      if model.query.isEmpty && characters.allSatisfy(\.isWhitespace) { return true }
      model.query += characters
      model.selectedID = nil
    }
    return true
  }

  /// Esclude i caratteri di controllo e quelli che macOS usa per frecce e tasti funzione.
  private static func isTypable(_ scalar: Unicode.Scalar) -> Bool {
    !CharacterSet.controlCharacters.contains(scalar) && !(0xF700...0xF8FF).contains(scalar.value)
  }

  // MARK: Scelta

  private func choose(_ item: ClipItem) {
    let point = clickPoint
    close()
    store.markUsed(item.id)
    Task {
      let outcome = await Paster.paste(item, at: point)
      log.info("Elemento scelto: \(String(describing: outcome), privacy: .public)")
    }
  }
}
