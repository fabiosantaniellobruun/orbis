import Foundation

/// Una voce del secondo anello: per Sposta una cartella di destinazione, per Converti in un formato.
struct RadialOption: Identifiable {
  enum Kind {
    case folder(URL)
    case chooseFolder
    case format(ImageFormat)
  }

  let id: String
  let kind: Kind
  let title: String
  /// Sotto il nome, in piccolo: il percorso completo di una cartella (spesso più cartelle hanno lo
  /// stesso nome), o a cosa serve un formato.
  let subtitle: String?
  /// Un simbolo piccolo prima del nome, che dice da dove viene la voce.
  let badge: String?
  /// Per le voci che non sono una cartella, il simbolo da mostrare nel bottone.
  let symbol: String
  /// Al posto del simbolo, una scritta nel bottone: per i formati, la sigla.
  let glyphText: String?

  var folder: URL? {
    if case .folder(let url) = kind { url } else { nil }
  }

  var format: ImageFormat? {
    if case .format(let format) = kind { format } else { nil }
  }

  // MARK: Sposta

  init(destination: Destination) {
    let path = destination.url.path(percentEncoded: false)
    id = "\(destination.kind):\(path)"
    kind = .folder(destination.url)
    // Il nome come lo mostra il Finder ("Scrivania", non "Desktop").
    title = FileManager.default.displayName(atPath: path)
    subtitle = Self.displayPath(destination.url)
    badge = destination.kind == .recent ? "clock" : "star.fill"
    symbol = "folder"
    glyphText = nil
  }

  static let chooseFolder = RadialOption(
    id: "choose", kind: .chooseFolder, title: "Scegli cartella…", subtitle: "Sfoglia il Mac",
    symbol: "ellipsis"
  )

  /// Le voci di Sposta, nell'ordine del menu: recenti, preferite e, per ultima, "Scegli cartella…".
  static func moveOptions(for destinations: [Destination]) -> [RadialOption] {
    destinations.map(RadialOption.init(destination:)) + [.chooseFolder]
  }

  // MARK: Converti in

  init(format: ImageFormat) {
    id = "format:\(format.rawValue)"
    kind = .format(format)
    title = format.title
    subtitle = format.detail
    badge = nil
    symbol = "photo"
    glyphText = format.title
  }

  /// I formati che questo Mac sa scrivere, nell'ordine di ImageFormat.
  static func convertOptions(formats: [ImageFormat] = ImageFormat.available) -> [RadialOption] {
    formats.map(RadialOption.init(format:))
  }

  // MARK: Comune

  private init(id: String, kind: Kind, title: String, subtitle: String?, symbol: String) {
    self.id = id
    self.kind = kind
    self.title = title
    self.subtitle = subtitle
    self.badge = nil
    self.symbol = symbol
    self.glyphText = nil
  }

  /// Il percorso completo con la casa abbreviata: "~/Sites/Clienti/Rossi".
  static func displayPath(_ url: URL) -> String {
    var path = url.path(percentEncoded: false)
    if path.count > 1, path.hasSuffix("/") { path.removeLast() }
    return (path as NSString).abbreviatingWithTildeInPath
  }
}
