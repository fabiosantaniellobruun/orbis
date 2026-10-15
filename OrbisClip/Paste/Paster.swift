import AppKit

/// Incolla un elemento dove si era fatto clic: lo mette negli appunti, riporta il cursore di testo
/// nel punto del clic e preme ⌘V. L'elemento resta negli appunti, pronto per incollarlo ancora.
enum Paster {
  enum Outcome {
    case pasted(String)
    /// Sotto il clic non c'era un campo di testo: l'elemento è rimasto negli appunti.
    case copied(String)
    case unavailable
  }

  static func paste(_ item: ClipItem, at point: CGPoint?) async -> Outcome {
    // Si guarda di nuovo che cosa c'è sotto il clic: all'apertura del pannello le app basate su
    // Chromium non avevano ancora pubblicato i loro campi.
    let target = point.map(PasteTarget.inspect(at:))
    let kind = target?.kind ?? .other
    guard write(item, for: kind, to: .general) else { return .unavailable }
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
    case .password:
      // Arriverà con il Portachiavi. La password andrà negli appunti con il tipo
      // `org.nspasteboard.ConcealedType`, che dice ai gestori di appunti di non conservarla.
      log.info("Le password non sono ancora collegate al Portachiavi")
      return false
    }
    return true
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
