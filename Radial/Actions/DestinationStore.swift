import Foundation

/// Una cartella proposta da Sposta.
nonisolated struct Destination: Sendable, Equatable {
  enum Kind: Sendable, Equatable {
    case recent
    case favorite
  }

  let url: URL
  let kind: Kind
}

/// Le cartelle di destinazione di Sposta: le ultime usate e le preferite scelte dall'utente.
nonisolated struct DestinationStore {
  static let favoriteSlotCount = 4
  /// Quante cartelle recenti compaiono nel menu.
  static let visibleRecents = 2
  private static let storedRecents = 10

  private static let favoritesKey = "favoriteFolders"
  private static let recentsKey = "recentFolders"

  private let defaults: UserDefaults
  private let isFolder: @Sendable (URL) -> Bool

  init(
    defaults: UserDefaults = .standard,
    isFolder: @escaping @Sendable (URL) -> Bool = DestinationStore.folderExists
  ) {
    self.defaults = defaults
    self.isFolder = isFolder
  }

  static func folderExists(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
      && isDirectory.boolValue
  }

  // MARK: Preferite

  /// Le quattro caselle, com'erano state impostate: quelle vuote sono `nil`. Una cartella che
  /// nel frattempo non esiste più resta nella casella, così si vede e si può cambiare.
  var favoriteSlots: [URL?] {
    let stored = defaults.stringArray(forKey: Self.favoritesKey) ?? []
    return (0..<Self.favoriteSlotCount).map { slot in
      guard slot < stored.count, !stored[slot].isEmpty else { return nil }
      return URL(filePath: stored[slot], directoryHint: .isDirectory)
    }
  }

  func setFavorite(_ url: URL?, slot: Int) {
    guard (0..<Self.favoriteSlotCount).contains(slot) else { return }
    var paths = favoriteSlots.map { $0.map(Self.path) ?? "" }
    paths[slot] = url.map(Self.path) ?? ""
    defaults.set(paths, forKey: Self.favoritesKey)
  }

  // MARK: Recenti

  var recents: [URL] {
    (defaults.stringArray(forKey: Self.recentsKey) ?? []).map { URL(filePath: $0, directoryHint: .isDirectory) }
  }

  /// La cartella appena usata passa in cima; se c'era già, non compare due volte.
  func recordRecent(_ folder: URL) {
    let path = Self.path(folder)
    let key = Self.key(folder)
    var paths = (defaults.stringArray(forKey: Self.recentsKey) ?? []).filter { Self.key(URL(filePath: $0)) != key }
    paths.insert(path, at: 0)
    defaults.set(Array(paths.prefix(Self.storedRecents)), forKey: Self.recentsKey)
  }

  func clearRecents() {
    defaults.removeObject(forKey: Self.recentsKey)
  }

  // MARK: Proposte

  /// Nell'ordine del menu: prima le ultime cartelle usate, poi le preferite. Una cartella già tra
  /// le preferite non occupa anche un posto tra le recenti, e quelle che non esistono più saltano.
  func destinations() -> [Destination] {
    var seen = Set<String>()
    let favorites = favoriteSlots.compactMap { $0 }.filter { isFolder($0) && seen.insert(Self.key($0)).inserted }
    // Le preferite occupano già il loro posto: le recenti si confrontano con quelle.
    let favoriteKeys = Set(favorites.map(Self.key))
    let recents = self.recents
      .filter { isFolder($0) && !favoriteKeys.contains(Self.key($0)) }
      .prefix(Self.visibleRecents)

    return recents.map { Destination(url: $0, kind: .recent) }
      + favorites.map { Destination(url: $0, kind: .favorite) }
  }

  // MARK: Percorsi

  private static func path(_ url: URL) -> String {
    let path = url.standardizedFileURL.path(percentEncoded: false)
    return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
  }

  /// Per riconoscere la stessa cartella scritta in due modi (collegamenti simbolici, barra finale).
  private static func key(_ url: URL) -> String {
    path(url.resolvingSymlinksInPath())
  }
}
