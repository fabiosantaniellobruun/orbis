import AppKit
import SwiftUI

/// Tiene insieme il rilevamento del trascinamento, il pannello e lo stato del menu.
final class RadialController {
  /// Largo per le etichette del secondo anello, alto per il suo arco e per l'onda.
  private static let panelSize = NSSize(width: 920, height: 640)

  private let model = RadialModel()
  private let monitor = DragMonitor()
  private let toast = ToastController()
  private let rename = RenameController()
  private let resize = ResizeController()
  private let gif = GIFController()
  private let dropView: RadialDropView
  private let panel: OverlayPanel

  private var isPreview = false
  /// Preferenza `stickyMenu`: il menu resta aperto anche dopo aver rilasciato il tasto,
  /// e si chiude con il rilascio dei file o uscendo dall'anello.
  private var staysOpenAfterRelease: Bool { UserDefaults.standard.bool(forKey: "stickyMenu") }
  private var hideTask: Task<Void, Never>?
  private var clickAwayMonitor: Any?
  /// L'ultima percentuale mostrata mentre si crea un GIF.
  private var gifPercent = -1

  init() {
    let frame = NSRect(origin: .zero, size: Self.panelSize)
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
      self?.highlightOption(nil)
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
  /// Per `move` il primo percorso è la cartella di destinazione, per `convert` il formato
  /// (png, jpeg, heic, avif, tiff, gif per i video, svg:1…svg:4 o svg:all per gli SVG), per `resize` la larghezza massima in pixel (senza, si apre il
  /// pannello); gli altri sono i file.
  func run(_ id: RadialAction.ID, on urls: [URL]) {
    guard let action = model.actions.first(where: { $0.id == id }), let screen = NSScreen.main else { return }
    let center = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
    Task {
      if id == .move, let destination = urls.first {
        let option = RadialOption(destination: Destination(url: destination, kind: .favorite))
        await perform(action, option: option, on: Array(urls.dropFirst()), toastAt: .centered(at: center))
      } else if id == .convert, let name = urls.first?.lastPathComponent, let option = RadialOption.svgOptions.first(where: { $0.id == name }) {
        await perform(action, option: option, on: Array(urls.dropFirst()), toastAt: .centered(at: center))
      } else if id == .convert, urls.first?.lastPathComponent == "gif" {
        await perform(action, option: .gif, on: Array(urls.dropFirst()), toastAt: .centered(at: center))
      } else if id == .convert, let name = urls.first?.lastPathComponent, let format = ImageFormat(rawValue: name) {
        await perform(action, option: RadialOption(format: format), on: Array(urls.dropFirst()), toastAt: .centered(at: center))
      } else if id == .resize, let width = urls.first.flatMap({ Int($0.lastPathComponent) }) {
        var options = ResizeOptions()
        options.width = width
        let sources = urls.dropFirst().map { ResizeSource(url: $0) }
        present(await ActionRunner.resize(ResizePlan.make(sources: sources, options: options).request), at: .centered(at: center))
      } else {
        await perform(action, option: nil, on: urls, toastAt: .centered(at: center))
      }
    }
  }
  #endif

  // MARK: Trascinamento

  private func handle(_ event: DragMonitor.Event) {
    switch event {
    case .triggerPressed:
      log.info("Tasto premuto durante un trascinamento di file")
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

  /// Aggiorna ciò che sta sotto il puntatore. Restituisce `true` se lì si può rilasciare: un
  /// bottone senza secondo anello, o una voce di un secondo anello.
  private func pointerMoved(to offset: CGSize, isDragging: Bool) -> Bool {
    guard model.phase == .ring else { return false }
    let distance = hypot(offset.width, offset.height)

    // Con un secondo anello aperto, oltre l'anello principale valgono le sue voci.
    if let sub = model.subGeometry, distance >= sub.innerRadius {
      if let option = sub.hit(offset) {
        highlightOption(option)
        return true
      }
      highlightOption(nil)
      if distance > sub.dismissRadius {
        leaveMenu(isDragging: isDragging)
        return false
      }
      // Fuori dall'arco ma vicino all'anello principale: vale ancora quello.
      if distance >= model.geometry.dismissRadius { return false }
    }

    switch model.geometry.hit(offset) {
    case .center:
      highlight(nil)
      collapse()
      return false

    case .sector(let index):
      highlight(index)
      if model.expanded != index {
        highlightOption(nil)
        model.expanded = model.hasOptions(at: index) ? index : nil
      }
      // Un bottone con un secondo anello non è un bersaglio: bisogna scegliere una voce.
      return !model.hasOptions(at: index)

    case .outside:
      highlight(nil)
      highlightOption(nil)
      leaveMenu(isDragging: isDragging)
      return false
    }
  }

  private func filesDropped(_ urls: [URL]) -> Bool {
    guard model.phase == .ring, let index = model.highlighted else {
      log.info("Rilascio ignorato: nessuna azione sotto il puntatore")
      return false
    }
    if model.hasOptions(at: index), model.highlightedOption == nil {
      log.info("Rilascio ignorato: nessuna voce del secondo anello sotto il puntatore")
      return false
    }
    confirm(model.actions[index], option: model.highlightedOption, urls: urls)
    return true
  }

  private func clicked() {
    guard model.phase == .ring else { return }
    guard let index = model.highlighted else {
      dismiss()
      return
    }
    if model.hasOptions(at: index), model.highlightedOption == nil { return }
    confirm(model.actions[index], option: model.highlightedOption, urls: [])
  }

  // MARK: Stato del menu

  private func highlight(_ index: Int?) {
    guard model.highlighted != index else { return }
    model.highlighted = index
    if index != nil {
      NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
  }

  private func highlightOption(_ index: Int?) {
    guard model.highlightedOption != index else { return }
    model.highlightedOption = index
    if index != nil {
      NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
  }

  private func collapse() {
    highlightOption(nil)
    model.expanded = nil
  }

  /// Trascinando fuori dal menu lo si chiude, così il rilascio torna a ciò che sta sotto.
  private func leaveMenu(isDragging: Bool) {
    guard isDragging else { return }
    log.info("Trascinamento uscito dall'anello")
    dismiss()
  }

  private func show(centeredAt point: NSPoint) {
    hideTask?.cancel()
    hideTask = nil
    model.highlighted = nil
    model.highlightedOption = nil
    model.expanded = nil
    model.phase = .hidden
    model.options = [
      .move: RadialOption.moveOptions(for: DestinationStore().destinations()),
      // Il menu di prova non trascina nulla: la pasteboard avrebbe i file del trascinamento di prima.
      .convert: RadialOption.convertOptions(for: isPreview ? [] : DragMonitor.draggedFileURLs()),
    ]

    let size = Self.panelSize
    var origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
    let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
    // Vicino ai bordi il pannello si sposta quanto basta perché l'anello resti sullo schermo, e in
    // verticale anche l'arco del secondo anello, che è più alto dell'anello.
    if let screen {
      let geometry = model.geometry
      let ringExtent = geometry.radius + geometry.buttonSize / 2 + 12
      let bounds = screen.visibleFrame.insetBy(
        dx: -(size.width / 2 - ringExtent),
        dy: -(size.height / 2 - max(ringExtent, SubRingGeometry.verticalReach))
      )
      origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
      origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size.height)
    }
    panel.setFrameOrigin(origin)
    arrangeActions(on: screen)
    panel.orderFrontRegardless()

    // Un giro di run loop dopo, così lo stato chiuso viene disegnato e l'apertura si anima.
    Task {
      model.phase = .ring
    }
  }

  /// Le etichette del secondo anello vogliono posto di lato. Se da una parte non ce n'è, le voci
  /// che ne hanno uno passano dall'altra parte dell'anello: capovolgere l'arco non basterebbe,
  /// perché per raggiungerlo bisognerebbe attraversare il centro, e lì il sottomenu si chiude.
  private func arrangeActions(on screen: NSScreen?) {
    guard let screen else {
      model.arrange(RadialAction.all)
      return
    }
    let bounds = screen.visibleFrame
    model.arrange(RadialAction.layout(
      roomLeft: panel.frame.midX - bounds.minX,
      roomRight: bounds.maxX - panel.frame.midX
    ))
  }

  private func confirm(_ action: RadialAction, option optionIndex: Int?, urls: [URL]) {
    var option: RadialOption?
    if let optionIndex, let expanded = model.expanded {
      let options = model.options(at: expanded)
      if options.indices.contains(optionIndex) {
        option = options[optionIndex]
      }
    }
    log.notice("Azione scelta: \(action.id.rawValue, privacy: .public), file ricevuti: \(urls.count)")
    let anchor = toastAnchor(for: action, option: optionIndex)
    model.highlighted = nil
    model.highlightedOption = nil
    model.phase = .confirmation(action, option: optionIndex)
    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    scheduleHide(after: .milliseconds(900))

    // L'avviso compare accanto al bottone usato e sopravvive all'anello.
    Task {
      await perform(action, option: option, on: urls, toastAt: anchor)
    }
  }

  /// Dove va l'avviso: accanto al bottone (o alla voce del secondo anello) su cui si è
  /// rilasciato, dalla parte che guarda fuori dall'anello. Al centro coprirebbe i file trascinati.
  private func toastAnchor(for action: RadialAction, option: Int?) -> ToastAnchor {
    let center = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
    if let option, let sub = model.subGeometry {
      return .beside(offset: sub.offset(at: option), from: center, radius: sub.buttonSize * 1.18 / 2, vertical: true)
    }
    guard let index = model.actions.firstIndex(of: action) else { return .centered(at: center) }
    let geometry = model.geometry
    return .beside(offset: geometry.offset(at: index), from: center, radius: geometry.buttonSize * 1.18 / 2)
  }

  // MARK: Azioni

  private func perform(_ action: RadialAction, option: RadialOption?, on urls: [URL], toastAt anchor: ToastAnchor) async {
    // Il menu di prova non ha file: mostra solo quale azione è stata scelta.
    guard !urls.isEmpty else {
      let text = option.map { "\(action.title) · \($0.title)" } ?? action.title
      toast.show(ToastContent(symbol: action.symbol, text: text), at: anchor, for: .milliseconds(1400))
      return
    }

    // Il GIF ha bisogno di tante scelte: si apre il suo pannello, e l'esito arriva dopo.
    if action.id == .convert, case .gif = option?.kind {
      try? await Task.sleep(for: .milliseconds(450))
      presentGIF(urls, for: action, at: anchor)
      return
    }

    // Ridimensiona ha bisogno delle misure: si apre il suo pannello, e l'esito arriva dopo.
    if action.id == .resize {
      try? await Task.sleep(for: .milliseconds(450))
      let opened = resize.present(urls, near: anchor.point) { [weak self] request in
        Task {
          let working = self?.showWorking(action, at: anchor)
          let outcome = await ActionRunner.resize(request)
          working?.cancel()
          self?.present(outcome, at: anchor)
        }
      }
      if !opened {
        let message = urls.count == 1 ? "Il file non è un'immagine da ridimensionare" : "I file non sono immagini da ridimensionare"
        present(ActionOutcome(symbol: "info.circle.fill", message: message), at: anchor)
      }
      return
    }

    // Rinomina ha bisogno di opzioni: si apre il suo pannello, e l'esito arriva dopo.
    if action.id == .rename {
      // Il tempo di vedere l'onda partire dal bottone.
      try? await Task.sleep(for: .milliseconds(450))
      rename.present(urls, near: anchor.point) { [weak self] entries in
        Task {
          let outcome = await ActionRunner.rename(entries)
          self?.present(outcome, at: anchor)
        }
      }
      return
    }

    // Sposta ha bisogno della cartella: quella della voce scelta, o una da cercare.
    var destination: URL?
    if action.id == .move {
      switch option?.kind {
      case .folder(let url):
        destination = url
      case .chooseFolder:
        try? await Task.sleep(for: .milliseconds(450))
        destination = await chooseFolder()
        // Niente scelta, niente da fare.
        guard destination != nil else { return }
      case .format, .gif, .svgScales, nil:
        return
      }
    }

    let working = showWorking(action, at: anchor)
    let outcome: ActionOutcome
    if let destination {
      outcome = await ActionRunner.move(urls, to: destination)
    } else if action.id == .convert, let scales = option?.svgScales {
      outcome = await ActionRunner.rasterizeSVGs(urls, scales: scales)
    } else if action.id == .convert {
      // Converti in ha bisogno del formato, scelto nel secondo anello.
      guard let format = option?.format else {
        working.cancel()
        return
      }
      outcome = await ActionRunner.convert(urls, to: format)
    } else {
      outcome = await ActionRunner.run(action, on: urls)
    }
    working.cancel()
    present(outcome, at: anchor)
  }

  private func presentGIF(_ urls: [URL], for action: RadialAction, at anchor: ToastAnchor) {
    let opened = gif.present(urls, near: anchor.point) { [weak self] request in
      Task { await self?.makeGIFs(request, for: action, at: anchor) }
    }
    if !opened {
      let message = urls.count == 1 ? "Il file non è un video da trasformare in GIF" : "I file non sono video da trasformare in GIF"
      present(ActionOutcome(symbol: "info.circle.fill", message: message), at: anchor)
    }
  }

  /// Crea i GIF, con l'avviso "in corso" che dice a che punto si è: può volerci un po'.
  private func makeGIFs(_ request: GIFRequest, for action: RadialAction, at anchor: ToastAnchor) async {
    let working = showWorking(action, at: anchor, text: "Creo il GIF")
    gifPercent = -1
    let outcome = await ActionRunner.makeGIFs(request) { [weak self] fraction in
      Task { @MainActor in
        // Gli aggiornamenti possono arrivare in disordine: la percentuale non torna indietro.
        let percent = Int(fraction * 100)
        guard let self, percent > self.gifPercent, self.toast.isShowingWork else { return }
        self.gifPercent = percent
        self.toast.show(
          ToastContent(symbol: "film", text: "Creo il GIF · \(percent)%", isWorking: true),
          at: anchor,
          for: nil
        )
      }
    }
    working.cancel()
    present(outcome, at: anchor)
  }

  /// L'avviso "in corso", che compare solo se l'azione non è immediata. Va annullato quando
  /// l'azione finisce.
  private func showWorking(_ action: RadialAction, at anchor: ToastAnchor, text: String? = nil) -> Task<Void, Never> {
    Task {
      try? await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled else { return }
      toast.show(
        ToastContent(symbol: action.symbol, text: text ?? action.title, isWorking: true),
        at: anchor,
        for: nil
      )
    }
  }

  /// Chiede una cartella di destinazione. Radial si attiva per mostrare il pannello, e alla fine
  /// restituisce il focus all'app di prima.
  private func chooseFolder() async -> URL? {
    NSApp.activate()
    let open = NSOpenPanel()
    open.canChooseDirectories = true
    open.canChooseFiles = false
    open.canCreateDirectories = true
    open.allowsMultipleSelection = false
    open.prompt = "Sposta qui"
    open.message = "Scegli la cartella di destinazione"
    open.directoryURL = DestinationStore().destinations().first?.url
    let response = await open.begin()
    NSApp.hide(nil)
    return response == .OK ? open.url : nil
  }

  private func present(_ outcome: ActionOutcome, at anchor: ToastAnchor) {
    let content = ToastContent(symbol: outcome.symbol, text: outcome.message, canUndo: outcome.undo != nil)
    guard let step = outcome.undo else {
      toast.show(content, at: anchor, for: .seconds(2))
      return
    }
    toast.show(content, at: anchor, for: .seconds(5)) { [weak self] in
      self?.undo(step, at: anchor)
    }
  }

  private func undo(_ step: UndoStep, at anchor: ToastAnchor) {
    Task {
      let outcome = await ActionRunner.undo(step)
      log.notice("Annullamento: \(outcome.message, privacy: .private)")
      present(outcome, at: anchor)
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
      model.highlightedOption = nil
      model.phase = .hidden
      // Il tempo dell'animazione di chiusura, poi la finestra esce davvero.
      try? await Task.sleep(for: .milliseconds(140))
      guard !Task.isCancelled else { return }
      model.expanded = nil
      panel.orderOut(nil)
      isPreview = false
      if let clickAwayMonitor {
        NSEvent.removeMonitor(clickAwayMonitor)
        self.clickAwayMonitor = nil
      }
    }
  }
}
