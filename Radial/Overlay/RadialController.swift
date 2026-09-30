import AppKit
import SwiftUI

/// Tiene insieme il rilevamento del trascinamento, il pannello e lo stato del menu.
final class RadialController {
  private static let panelSide: CGFloat = 600

  private let model = RadialModel()
  private let monitor = DragMonitor()
  private let dropView: RadialDropView
  private let panel: RadialPanel

  private var isPreview = false
  /// Preferenza `stickyMenu`: il menu resta aperto anche dopo aver rilasciato la combinazione,
  /// e si chiude con il rilascio dei file o uscendo dall'anello.
  private var staysOpenAfterRelease: Bool { UserDefaults.standard.bool(forKey: "stickyMenu") }
  private var hideTask: Task<Void, Never>?
  private var clickAwayMonitor: Any?

  init() {
    let frame = NSRect(x: 0, y: 0, width: Self.panelSide, height: Self.panelSide)
    dropView = RadialDropView(frame: frame)

    let hostingView = NSHostingView(rootView: RadialMenuView(model: model).ignoresSafeArea())
    hostingView.sizingOptions = []
    hostingView.frame = frame
    hostingView.autoresizingMask = [.width, .height]
    dropView.addSubview(hostingView)

    panel = RadialPanel(contentView: dropView, side: Self.panelSide)

    dropView.pointerMoved = { [weak self] offset, isDragging in
      self?.pointerMoved(to: offset, isDragging: isDragging) ?? false
    }
    dropView.pointerLeft = { [weak self] in
      self?.highlight(nil)
    }
    dropView.filesDropped = { [weak self] urls in
      self?.filesDropped(urls) ?? false
    }
    dropView.clicked = { [weak self] in
      self?.clicked()
    }
    monitor.onEvent = { [weak self] event in
      self?.handle(event)
    }
  }

  func start() {
    monitor.start()
  }

  /// Mostra il menu al centro dello schermo, pilotato dal mouse invece che da un trascinamento.
  func showPreview() {
    guard let screen = NSScreen.main else { return }
    isPreview = true
    show(centeredAt: NSPoint(x: screen.frame.midX, y: screen.frame.midY))
    clickAwayMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
      self?.dismiss()
    }
  }

  // MARK: Trascinamento

  private func handle(_ event: DragMonitor.Event) {
    switch event {
    case .comboPressed:
      log.info("Combinazione premuta durante un trascinamento di file")
      isPreview = false
      show(centeredAt: NSEvent.mouseLocation)
    case .comboReleased:
      guard !isPreview, !staysOpenAfterRelease else { return }
      dismiss()
    case .dragEnded:
      guard !isPreview, model.phase == .ring else { return }
      if dropView.isDragInside {
        // Il rilascio sta arrivando al pannello: chiudere ora lo farebbe perdere.
        // Se non arriva, si chiude comunque poco dopo.
        scheduleHide(after: .milliseconds(300))
      } else {
        dismiss()
      }
    }
  }

  private func pointerMoved(to offset: CGSize, isDragging: Bool) -> Bool {
    guard model.phase == .ring else { return false }
    switch model.geometry.hit(offset) {
    case .center:
      highlight(nil)
      return false
    case .sector(let index):
      highlight(index)
      return true
    case .outside:
      highlight(nil)
      // Trascinando fuori dal menu lo si chiude, così il rilascio torna a ciò che sta sotto.
      if isDragging { dismiss() }
      return false
    }
  }

  private func filesDropped(_ urls: [URL]) -> Bool {
    guard model.phase == .ring, let index = model.highlighted else { return false }
    confirm(model.actions[index], urls: urls)
    return true
  }

  private func clicked() {
    guard model.phase == .ring else { return }
    if let index = model.highlighted {
      confirm(model.actions[index], urls: [])
    } else {
      dismiss()
    }
  }

  // MARK: Stato del menu

  private func highlight(_ index: Int?) {
    guard model.highlighted != index else { return }
    model.highlighted = index
    if index != nil {
      NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
  }

  private func show(centeredAt point: NSPoint) {
    hideTask?.cancel()
    hideTask = nil
    model.highlighted = nil
    model.phase = .hidden

    let side = Self.panelSide
    var origin = NSPoint(x: point.x - side / 2, y: point.y - side / 2)
    // Vicino ai bordi il pannello si sposta quanto basta perché l'anello resti sullo schermo.
    if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main {
      let geometry = model.geometry
      let ringExtent = geometry.radius + geometry.buttonSize / 2 + 12
      let overhang = side / 2 - ringExtent
      let bounds = screen.visibleFrame.insetBy(dx: -overhang, dy: -overhang)
      origin.x = min(max(origin.x, bounds.minX), bounds.maxX - side)
      origin.y = min(max(origin.y, bounds.minY), bounds.maxY - side)
    }
    panel.setFrameOrigin(origin)
    panel.orderFrontRegardless()

    // Un giro di run loop dopo, così lo stato chiuso viene disegnato e l'apertura si anima.
    Task {
      model.phase = .ring
    }
  }

  private func confirm(_ action: RadialAction, urls: [URL]) {
    log.notice("Azione scelta: \(action.id, privacy: .public), file ricevuti: \(urls.count)")
    model.highlighted = nil
    model.phase = .confirmation(action, fileCount: urls.count)
    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    scheduleHide(after: .milliseconds(1200))
  }

  private func dismiss() {
    guard model.phase == .ring else { return }
    scheduleHide(after: .zero)
  }

  private func scheduleHide(after delay: Duration) {
    hideTask?.cancel()
    hideTask = Task {
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      model.highlighted = nil
      model.phase = .hidden
      // Il tempo dell'animazione di chiusura, poi la finestra esce davvero.
      try? await Task.sleep(for: .milliseconds(140))
      guard !Task.isCancelled else { return }
      panel.orderOut(nil)
      isPreview = false
      if let clickAwayMonitor {
        NSEvent.removeMonitor(clickAwayMonitor)
        self.clickAwayMonitor = nil
      }
    }
  }
}
