import AppKit

/// Si accorge di quando è in corso un trascinamento di file e di quando, durante il trascinamento,
/// viene premuto il tasto che apre il menu. Non richiede permessi di sistema: gli eventi del mouse
/// si possono osservare liberamente e lo stato dei modificatori viene letto, non intercettato.
final class DragMonitor {
  enum Event {
    case triggerPressed
    case triggerReleased
    case dragEnded
  }

  var onEvent: ((Event) -> Void)?

  /// Il tasto che apre il menu, come impostato dall'utente. Lo si rilegge a ogni trascinamento,
  /// così una modifica nelle impostazioni vale subito. I modificatori devono essere esattamente
  /// quelli scelti: con un altro in più si è in un'altra combinazione.
  private var trigger = TriggerShortcut.standard

  private static let legacyFilenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")

  private let dragPasteboard = NSPasteboard(name: .drag)
  private var changeCountAtMouseDown = 0
  private var lastCheck = Date.distantPast
  private var eventMonitor: Any?
  private var pollTask: Task<Void, Never>?
  private var isTriggerHeld = false
  private var isMenuRequested = false

  /// I file trascinati in questo momento, per proporre le azioni adatte (per esempio GIF per i
  /// video). Si leggono solo per questo, e non escono dal Mac.
  static func draggedFileURLs() -> [URL] {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    return NSPasteboard(name: .drag).readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
  }

  func start() {
    changeCountAtMouseDown = dragPasteboard.changeCount
    eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged]) { [weak self] event in
      self?.handle(event)
    }
  }

  func stop() {
    if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    eventMonitor = nil
    pollTask?.cancel()
    pollTask = nil
  }

  private func handle(_ event: NSEvent) {
    guard pollTask == nil else { return }
    if event.type == .leftMouseDown {
      changeCountAtMouseDown = dragPasteboard.changeCount
      return
    }
    // Un trascinamento vero scrive sulla pasteboard di trascinamento: se il contatore è cambiato
    // dal mouse-down, è partita una sessione. Il controllo è limitato a una ventina al secondo.
    let now = Date()
    guard now.timeIntervalSince(lastCheck) > 0.05 else { return }
    lastCheck = now
    guard dragPasteboard.changeCount != changeCountAtMouseDown else { return }
    beginTracking()
  }

  private var dragContainsFiles: Bool {
    guard let types = dragPasteboard.types else { return false }
    return types.contains(.fileURL) || types.contains(Self.legacyFilenames)
  }

  private func beginTracking() {
    trigger = .load()
    log.info("Trascinamento rilevato")
    pollTask = Task { [weak self] in
      while !Task.isCancelled, self?.poll() == true {
        try? await Task.sleep(for: .milliseconds(16))
      }
    }
  }

  /// Restituisce `false` quando il trascinamento è finito.
  private func poll() -> Bool {
    guard NSEvent.pressedMouseButtons & 1 != 0 else {
      endTracking()
      return false
    }
    // Lo stato di un tasto normale si legge, non si intercetta: non servono permessi, ma il tasto
    // arriva anche all'app da cui si trascina.
    let held = trigger.isHeld(modifiers: NSEvent.modifierFlags) { keyCode in
      CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
    }
    guard held != isTriggerHeld else { return true }
    isTriggerHeld = held
    if held {
      guard dragContainsFiles else {
        log.info("Tasto premuto, ma il trascinamento non contiene file")
        return true
      }
      isMenuRequested = true
      onEvent?(.triggerPressed)
    } else if isMenuRequested {
      isMenuRequested = false
      onEvent?(.triggerReleased)
    }
    return true
  }

  private func endTracking() {
    pollTask = nil
    isTriggerHeld = false
    isMenuRequested = false
    changeCountAtMouseDown = dragPasteboard.changeCount
    onEvent?(.dragEnded)
  }
}
