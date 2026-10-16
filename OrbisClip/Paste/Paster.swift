import AppKit
import LocalAuthentication

/// Incolla un elemento dove si era fatto clic: lo mette negli appunti, riporta il cursore di testo
/// nel punto del clic e preme ⌘V. L'elemento resta negli appunti, pronto per incollarlo ancora.
enum Paster {
  enum Outcome {
    case pasted(String)
    /// Sotto il clic non c'era un campo di testo: l'elemento è rimasto negli appunti.
    case copied(String)
    /// Nel Finder: il file creato.
    case created(URL)
    case failed(String)
    case unavailable
    /// Touch ID (o la password del Mac) non confermato.
    case cancelled
  }

  static func paste(_ item: ClipItem, at point: CGPoint?) async -> Outcome {
    // Si guarda di nuovo che cosa c'è sotto il clic: all'apertura del pannello le app basate su
    // Chromium non avevano ancora pubblicato i loro campi.
    let target = point.map(PasteTarget.inspect(at:))
    let kind = target?.kind ?? .other
    if case .password = item.content, !(await confirmOwner(for: item.name)) { return .cancelled }
    guard write(item, for: kind, to: .general) else { return .unavailable }
    if case .finder(let desktop) = kind, let target {
      // Se non si sa quale cartella, l'elemento resta almeno negli appunti.
      if !desktop {
        // La finestra del clic passa in primo piano, così il Finder dice la sua cartella.
        click(at: target.point)
        try? await Task.sleep(for: .milliseconds(150))
      }
      guard let folder = desktop ? URL.desktopDirectory : FinderFolder.frontFolder() else {
        return .copied(target.description)
      }
      do {
        return .created(try FinderExport.create(item, in: folder))
      } catch {
        return .failed(error.localizedDescription)
      }
    }
    guard let target, kind != .other else { return .copied(target?.description ?? "pannello di prova") }

    // Il clic originale non è arrivato all'app: se ne manda uno nello stesso punto, così il campo
    // prende il focus e il cursore di testo va dove si era fatto clic.
    try? await Task.sleep(for: .milliseconds(60))
    click(at: target.point)
    try? await Task.sleep(for: .milliseconds(80))
    pressCommandV()
    return .pasted(target.description)
  }

  /// In un campo di una riga, di un'immagine o di un file si incolla il nome; altrove l'elemento.
  private static func write(_ item: ClipItem, for kind: PasteTarget.Kind, to pasteboard: NSPasteboard) -> Bool {
    switch item.content {
    case .text(let text, let rtf):
      // Con tutti e due, ogni app prende quello che sa usare: un campo semplice il testo, un
      // editor la formattazione.
      pasteboard.clearContents()
      pasteboard.setString(text, forType: .string)
      if let rtf { pasteboard.setData(rtf, forType: .rtf) }
    case .link(let url):
      pasteboard.clearContents()
      pasteboard.setString(url.absoluteString, forType: .string)
      pasteboard.setString(url.absoluteString, forType: .URL)
    case .image(let blob):
      pasteboard.clearContents()
      if kind == .singleLineText {
        pasteboard.setString(item.name, forType: .string)
      } else if let png = try? Data(contentsOf: blob.url) {
        pasteboard.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation {
          pasteboard.setData(tiff, forType: .tiff)
        }
      }
    case .file(let blob):
      pasteboard.clearContents()
      if kind == .singleLineText {
        pasteboard.setString(blob.name, forType: .string)
      } else {
        pasteboard.writeObjects([blob.url as NSURL])
      }
    case .password(let account):
      guard let password = PasswordStore.password(account: account) else { return false }
      pasteboard.clearContents()
      pasteboard.setString(password, forType: .string)
      // Dice ai gestori di appunti di non conservarla (nspasteboard.org).
      pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
      clearLater(pasteboard)
    }
    return true
  }

  /// Touch ID, o la password del Mac dove Touch ID non c'è o non riesce.
  private static func confirmOwner(for name: String) async -> Bool {
    let context = LAContext()
    do {
      return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "incollare la password «\(name)»")
    } catch {
      log.info("Password non confermata: \(error.localizedDescription, privacy: .public)")
      return false
    }
  }

  /// Una password non resta negli appunti: dopo un minuto si toglie, se nel frattempo non si è
  /// copiato altro.
  private static func clearLater(_ pasteboard: NSPasteboard) {
    let written = pasteboard.changeCount
    Task {
      try? await Task.sleep(for: .seconds(60))
      if pasteboard.changeCount == written { pasteboard.clearContents() }
    }
  }

  // MARK: Eventi

  /// Un clic sinistro nel punto dato; poi il puntatore torna dov'era.
  private static func click(at point: CGPoint) {
    let current = CGEvent(source: nil)?.location
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
      let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
      event?.flags = []
      event?.setIntegerValueField(.mouseEventClickState, value: 1)
      event?.post(tap: .cghidEventTap)
    }
    if let current { CGWarpMouseCursorPosition(current) }
  }

  private static func pressCommandV() {
    let source = CGEventSource(stateID: .combinedSessionState)
    let keyV: CGKeyCode = 9
    for isDown in [true, false] {
      let event = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: isDown)
      event?.flags = .maskCommand
      event?.post(tap: .cghidEventTap)
    }
  }
}
