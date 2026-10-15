import Foundation

/// Un elemento salvato: lo aggiunge l'utente, con un nome e, se vuole, una scorciatoia da scrivere
/// nella ricerca.
nonisolated struct ClipItem: Identifiable, Hashable, Codable, Sendable {
  enum Content: Hashable, Codable, Sendable {
    /// Il testo semplice e, se ce l'ha, quello formattato (RTF).
    case text(String, rtf: Data?)
    case link(URL)
    /// Un PNG.
    case image(ClipBlob)
    /// Una copia del file.
    case file(ClipBlob)
    /// La password sta nel Portachiavi: qui c'è solo il riferimento.
    case password(account: String)
  }

  var id = UUID()
  var name: String
  var shortcut: String?
  var isFavorite = false
  var content: Content
  var addedAt = Date()
  var lastUsedAt: Date?

  /// Il testo in cui si cerca, oltre al nome e alla scorciatoia.
  var searchableContent: String {
    switch content {
    case .text(let text, _): text
    case .link(let url): url.absoluteString
    case .file(let blob): blob.name
    case .image, .password: ""
    }
  }

  /// I file conservati per questo elemento.
  var blobs: [ClipBlob] {
    switch content {
    case .image(let blob), .file(let blob): [blob]
    case .text, .link, .password: []
    }
  }

  /// Quanto l'elemento risponde alla ricerca, 0 se non risponde. La scorciatoia conta più del nome,
  /// il nome più del contenuto. Maiuscole e accenti non contano.
  func score(for query: String) -> Int {
    let query = Self.fold(query.trimmingCharacters(in: .whitespaces))
    guard !query.isEmpty else { return 0 }
    if let shortcut {
      let shortcut = Self.fold(shortcut)
      if shortcut == query { return 100 }
      if shortcut.hasPrefix(query) { return 80 }
    }
    let name = Self.fold(name)
    if name.hasPrefix(query) { return 60 }
    let words = name.split { !$0.isLetter && !$0.isNumber }
    if words.contains(where: { $0.hasPrefix(query) }) { return 50 }
    if name.contains(query) { return 30 }
    if Self.fold(searchableContent).contains(query) { return 10 }
    return 0
  }

  private static func fold(_ string: String) -> String {
    string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
  }
}
