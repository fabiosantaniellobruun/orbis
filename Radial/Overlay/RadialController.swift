import AppKit
import SwiftUI

/// Tiene insieme il rilevamento del trascinamento, il pannello e lo stato del menu.
final class RadialController {
  private static let panelSide: CGFloat = 600

  private let model = RadialModel()
  private let monitor = DragMonitor()
  private let toast = ToastController()
  private let dropView: RadialDropView
  private let panel: OverlayPanel

  private var isPreview = false
  /// Preferenza `stickyMenu`: il menu resta aperto anche dopo aver rilasciato Shift,
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

    // Il pannello riceve i rilasci su tutto l'anello, anche negli spazi vuoti tra i bottoni.
    panel = OverlayPanel(contentView: dropView, size: frame.size, catchesTransparentAreas: true)

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

  #if DEBUG
  /// Esegue un'azione senza passare dal menu; l'avviso compare al centro dello schermo.
  func run(_ id: RadialAction.ID, on urls: [URL]) {
    guard let action = model.actions.first(where: { $0.id == id }), let screen = NSScreen.main else { return }
    Task {
      await perform(action, on: urls, toastAt: NSPoint(x: screen.frame.midX, y: screen.frame.midY))
    }
  }
  #endif

  // MARK: Trascinamento

  private func handle(_ event: DragMonitor.Event) {
    switch event {
    case .triggerPressed:
      log.info("Shift premuto durante un trascinamento di file")
      isPreview = false
      show(centeredAt: NSEvent.mouseLocation)
    case .triggerReleased:
      guard !isPreview, !staysOpenAfterRelease else { return }
      dismiss()
    case .dragEnded:
      log.info("Trascinamento finito, dentro il pannello: \(self.dropView.isDragInside)")
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
      if isDragging {
        log.info("Trascinamento uscito dall'anello")
        dismiss()
      }
      return false
    }
  }

  private func filesDropped(_ urls: [URL]) -> Bool {
    guard model.phase == .ring, let index = model.highlighted else {
      log.info("Rilascio ignorato: nessuna azione sotto il puntatore")
      return false
    }
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
    log.notice("Azione scelta: \(action.id.rawValue, privacy: .public), file ricevuti: \(urls.count)")
    model.highlighted = nil
    model.phase = .confirmation(action)
    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    scheduleHide(after: .milliseconds(900))

    // L'avviso compare al centro dell'anello e gli sopravvive.
    let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
    Task {
      await perform(action, on: urls, toastAt: center)
    }
  }

  // MARK: Azioni

  private func perform(_ action: RadialAction, on urls: [URL], toastAt point: NSPoint) async {
    // Il menu di prova non ha file: mostra solo quale azione è stata scelta.
    guard !urls.isEmpty else {
      toast.show(ToastContent(symbol: action.symbol, text: action.title), centeredAt: point, for: .milliseconds(1400))
      return
    }

    // L'avviso "in corso" compare solo se l'azione non è immediata.
    let working = Task {
      try? await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled else { return }
      toast.show(
        ToastContent(symbol: action.symbol, text: action.title, isWorking: true),
        centeredAt: point,
        for: nil
      )
    }
    let outcome = await ActionRunner.run(action, on: urls)
    working.cancel()
    present(outcome, at: point)
  }

  private func present(_ outcome: ActionOutcome, at point: NSPoint) {
    let content = ToastContent(symbol: outcome.symbol, text: outcome.message, canUndo: outcome.undo != nil)
    guard let step = outcome.undo else {
      toast.show(content, centeredAt: point, for: .seconds(2))
      return
    }
    toast.show(content, centeredAt: point, for: .seconds(5)) { [weak self] in
      self?.undo(step, at: point)
    }
  }

  private func undo(_ step: UndoStep, at point: NSPoint) {
    Task {
      let outcome = await ActionRunner.undo(step)
      log.notice("Annullamento: \(outcome.message, privacy: .public)")
      present(outcome, at: point)
    }
  }

  // MARK: Chiusura

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
