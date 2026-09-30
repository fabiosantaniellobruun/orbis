import Foundation

/// Una voce del secondo anello: per Sposta, una cartella di destinazione.
struct RadialOption: Identifiable {
  enum Kind {
    case folder(URL)
    case chooseFolder
  }

  let id: String
  let kind: Kind
  let title: String
  /// Il percorso completo, in piccolo: spesso più cartelle hanno lo stesso nome.
  let subtitle: String?
  /// Un simbolo piccolo prima del nome, che dice da dove viene la voce.
  let badge: String?
  /// Per le voci che non sono una cartella, il simbolo da mostrare nel bottone.
  let symbol: String

  var folder: URL? {
    if case .folder(let url) = kind { url } else { nil }
  }

  init(destination: Destination) {
    let path = destination.url.path(percentEncoded: false)
    id = "\(destination.kind):\(path)"
    kind = .folder(destination.url)
    // Il nome come lo mostra il Finder ("Scrivania", non "Desktop").
    title = FileManager.default.displayName(atPath: path)
    subtitle = Self.displayPath(destination.url)
    badge = destination.kind == .recent ? "clock" : "star.fill"
    symbol = "folder"
  }

  static let chooseFolder = RadialOption()

  private init() {
    id = "choose"
    kind = .chooseFolder
    title = "Scegli cartella…"
    subtitle = "Sfoglia il Mac"
    badge = nil
    symbol = "ellipsis"
  }

  /// Le voci di Sposta, nell'ordine del menu: recenti, preferite e, per ultima, "Scegli cartella…".
  static func moveOptions(for destinations: [Destination]) -> [RadialOption] {
    destinations.map(RadialOption.init(destination:)) + [.chooseFolder]
  }

  /// Il percorso completo con la casa abbreviata: "~/Sites/Clienti/Rossi".
  static func displayPath(_ url: URL) -> String {
    var path = url.path(percentEncoded: false)
    if path.count > 1, path.hasSuffix("/") { path.removeLast() }
    return (path as NSString).abbreviatingWithTildeInPath
  }
}
