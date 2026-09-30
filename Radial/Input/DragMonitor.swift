import AppKit

/// Si accorge di quando è in corso un trascinamento di file e di quando, durante il trascinamento,
/// viene premuta la combinazione di tasti. Non richiede permessi di sistema: gli eventi del mouse
/// si possono osservare liberamente e lo stato dei modificatori viene letto, non intercettato.
final class DragMonitor {
  enum Event {
    case comboPressed
    case comboReleased
    case dragEnded
  }

  var onEvent: ((Event) -> Void)?
  var combo: NSEvent.ModifierFlags = [.control, .shift]

  private static let comboKeys: NSEvent.ModifierFlags = [.control, .shift, .option, .command]
  private static let legacyFilenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")

  private let dragPasteboard = NSPasteboard(name: .drag)
  private var changeCountAtMouseDown = 0
  private var lastCheck = Date.distantPast
  private var eventMonitor: Any?
  private var pollTask: Task<Void, Never>?
  private var isComboHeld = false
  private var isMenuRequested = false

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
    let held = NSEvent.modifierFlags.intersection(Self.comboKeys) == combo
    guard held != isComboHeld else { return true }
    isComboHeld = held
    if held {
      guard dragContainsFiles else {
        log.info("Combinazione premuta, ma il trascinamento non contiene file")
        return true
      }
      isMenuRequested = true
      onEvent?(.comboPressed)
    } else if isMenuRequested {
      isMenuRequested = false
      onEvent?(.comboReleased)
    }
    return true
  }

  private func endTracking() {
    pollTask = nil
    isComboHeld = false
    isMenuRequested = false
    changeCountAtMouseDown = dragPasteboard.changeCount
    onEvent?(.dragEnded)
  }
}
