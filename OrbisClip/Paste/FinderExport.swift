import AppKit

/// Nel Finder un elemento diventa un file: un'immagine in PNG, un testo in .txt (o .rtf, se
/// formattato), un link in .webloc, un file salvato come copia. Mai sopra un file che c'è già.
enum FinderExport {
  enum ExportError: LocalizedError {
    case password

    var errorDescription: String? { "Le password non diventano file." }
  }

  static func create(_ item: ClipItem, in folder: URL) throws -> URL {
    // Nei nomi di file "/" e ":" non sono ammessi.
    let stem = item.name.replacing(/[\/:]/, with: "-").trimmingCharacters(in: .whitespaces)
    let name = stem.isEmpty ? "Elemento" : stem
    switch item.content {
    case .text(let text, let rtf):
      let url = FileNames.availableURL(in: folder, stem: name, extension: rtf == nil ? "txt" : "rtf")
      try (rtf ?? Data(text.utf8)).write(to: url, options: .withoutOverwriting)
      return url
    case .link(let link):
      let url = FileNames.availableURL(in: folder, stem: name, extension: "webloc")
      let plist = try PropertyListSerialization.data(fromPropertyList: ["URL": link.absoluteString], format: .xml, options: 0)
      try plist.write(to: url, options: .withoutOverwriting)
      return url
    case .image(let blob):
      let url = FileNames.availableURL(in: folder, stem: name, extension: "png")
      try FileManager.default.copyItem(at: blob.url, to: url)
      return url
    case .file(let blob):
      // Il file mantiene il suo nome, non quello dell'elemento.
      let parts = FileNames.nameParts(of: blob.url)
      let url = FileNames.availableURL(in: folder, stem: parts.stem, extension: parts.extension)
      try FileManager.default.copyItem(at: blob.url, to: url)
      return url
    case .password:
      throw ExportError.password
    }
  }
}

/// La cartella della finestra del Finder in primo piano. Le API di accessibilità non la dicono: si
/// chiede al Finder con AppleScript, e la prima volta macOS chiede il permesso Automazione.
/// L'elenco delle finestre con le loro posizioni (`bounds of every Finder window`) sul Mac di prova
/// risponde con finestre fittizie, senza cartella: per questo si porta in primo piano la finestra
/// del clic e si chiede la `insertion location`, dove il Finder metterebbe un file nuovo.
enum FinderFolder {
  private static let script = NSAppleScript(source: """
    tell application "Finder" to return POSIX path of (insertion location as alias)
    """)

  /// `nil` se il Finder non risponde, se manca il permesso, o se la finestra non mostra una
  /// cartella (Recenti, AirDrop…).
  static func frontFolder() -> URL? {
    var error: NSDictionary?
    guard let path = script?.executeAndReturnError(&error).stringValue, !path.isEmpty else {
      log.error("Il Finder non dice la sua cartella: \(String(describing: error), privacy: .public)")
      return nil
    }
    return URL(filePath: path, directoryHint: .isDirectory)
  }
}
