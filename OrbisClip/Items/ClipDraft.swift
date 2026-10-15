import AppKit

/// Ciò che si sta per aggiungere: il contenuto, letto da una pasteboard, e un nome proposto.
/// Immagini e file sono già copiati nella cartella di Orbis Clip: se l'aggiunta si annulla,
/// `discard()` li toglie.
struct ClipDraft {
  var content: ClipItem.Content
  var suggestedName: String

  func discard() {
    switch content {
    case .image(let blob), .file(let blob): ClipStorage.remove(blob)
    case .text, .link, .password: break
    }
  }
}

extension ClipDraft {
  /// Legge il contenuto più ricco: prima i file, poi le immagini, poi i link, poi il testo.
  /// Un'immagine copiata dal browser porta con sé anche il suo indirizzo: conta l'immagine.
  /// Lancia un errore se un file supera i 10 MB.
  init?(pasteboard: NSPasteboard) throws {
    let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    if let url = (pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL])?.first {
      self.init(content: .file(try ClipStorage.copy(url)), suggestedName: url.deletingPathExtension().lastPathComponent)
      return
    }
    if let png = Self.png(from: pasteboard) {
      self.init(content: .image(try ClipStorage.store(png, named: "Immagine.png")), suggestedName: "Immagine")
      return
    }
    if let url = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first(where: Self.isWebLink) {
      self.init(link: url)
      return
    }
    let rtf = Self.rtf(from: pasteboard)
    let plain = pasteboard.string(forType: .string)
      ?? rtf.flatMap { NSAttributedString(rtf: $0, documentAttributes: nil)?.string }
    guard let text = plain, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed), Self.isWebLink(url) {
      self.init(link: url)
      return
    }
    let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
    self.init(content: .text(text, rtf: rtf), suggestedName: String(firstLine.prefix(40)))
  }

  private init(link url: URL) {
    let host = url.host(percentEncoded: false) ?? url.absoluteString
    self.init(content: .link(url), suggestedName: host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)
  }

  private static func isWebLink(_ url: URL) -> Bool {
    url.scheme == "http" || url.scheme == "https"
  }

  private static func png(from pasteboard: NSPasteboard) -> Data? {
    if let png = pasteboard.data(forType: .png) { return png }
    guard let tiff = pasteboard.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
  }

  /// La formattazione: RTF se c'è, altrimenti ricavato dall'HTML (Chrome e molte app web danno
  /// solo quello).
  private static func rtf(from pasteboard: NSPasteboard) -> Data? {
    if let rtf = pasteboard.data(forType: .rtf) { return rtf }
    guard let html = pasteboard.data(forType: .html),
          let attributed = NSAttributedString(html: html, documentAttributes: nil)
    else { return nil }
    return attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:])
  }
}
