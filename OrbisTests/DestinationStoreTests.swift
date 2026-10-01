import Foundation
import Testing
@testable import Orbis

struct DestinationStoreTests {
  /// Un archivio a sé, e un elenco di cartelle che "esistono" senza toccare il disco.
  func makeStore(existing: [String]) -> DestinationStore {
    let suite = "OrbisTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let folders = Set(existing)
    return DestinationStore(defaults: defaults, isFolder: { folders.contains(DestinationStoreTests.plain($0)) })
  }

  func url(_ path: String) -> URL {
    URL(filePath: path, directoryHint: .isDirectory)
  }

  /// Il percorso senza la barra finale che un URL di cartella può avere.
  static func plain(_ url: URL) -> String {
    var path = url.path(percentEncoded: false)
    if path.count > 1, path.hasSuffix("/") { path.removeLast() }
    return path
  }

  func paths(_ destinations: [Destination]) -> [String] {
    destinations.map { Self.plain($0.url) }
  }

  static let clienti = ["/Users/prova/Clienti/Rossi", "/Users/prova/Clienti/Bianchi", "/Users/prova/Archivio/Rossi"]

  @Test("Senza niente di salvato non c'è nessuna proposta")
  func emptyStore() {
    let store = makeStore(existing: Self.clienti)

    #expect(store.destinations().isEmpty)
    #expect(store.recents.isEmpty)
    #expect(store.favoriteSlots == [nil, nil, nil, nil])
  }

  @Test("Le cartelle recenti si mettono in cima, l'ultima per prima")
  func recentsMostRecentFirst() {
    let store = makeStore(existing: Self.clienti)

    store.recordRecent(url("/Users/prova/Clienti/Rossi"))
    store.recordRecent(url("/Users/prova/Clienti/Bianchi"))

    #expect(store.recents.map(Self.plain)
      == ["/Users/prova/Clienti/Bianchi", "/Users/prova/Clienti/Rossi"])
  }

  @Test("Una cartella già tra le recenti passa in cima e non compare due volte")
  func recentsNoDuplicates() {
    let store = makeStore(existing: Self.clienti)

    store.recordRecent(url("/Users/prova/Clienti/Rossi"))
    store.recordRecent(url("/Users/prova/Clienti/Bianchi"))
    store.recordRecent(url("/Users/prova/Clienti/Rossi/"))

    #expect(store.recents.map(Self.plain)
      == ["/Users/prova/Clienti/Rossi", "/Users/prova/Clienti/Bianchi"])
  }

  @Test("Si ricordano solo le ultime dieci")
  func recentsAreCapped() {
    let store = makeStore(existing: [])

    for number in 1...15 {
      store.recordRecent(url("/Users/prova/Cartella\(number)"))
    }

    #expect(store.recents.count == 10)
    #expect(store.recents.first?.lastPathComponent == "Cartella15")
    #expect(store.recents.last?.lastPathComponent == "Cartella6")
  }

  @Test("Nel menu compaiono solo le prime due recenti")
  func onlyTwoRecentsShown() {
    let store = makeStore(existing: ["/a", "/b", "/c"])

    for path in ["/a", "/b", "/c"] {
      store.recordRecent(url(path))
    }

    #expect(paths(store.destinations()) == ["/c", "/b"])
    #expect(store.destinations().allSatisfy { $0.kind == .recent })
  }

  @Test("Prima le recenti, poi le preferite nell'ordine delle caselle")
  func recentsThenFavorites() {
    let store = makeStore(existing: ["/r1", "/r2", "/f1", "/f2", "/f3"])
    store.recordRecent(url("/r1"))
    store.recordRecent(url("/r2"))
    store.setFavorite(url("/f1"), slot: 0)
    store.setFavorite(url("/f3"), slot: 2)
    store.setFavorite(url("/f2"), slot: 3)

    let result = store.destinations()

    #expect(paths(result) == ["/r2", "/r1", "/f1", "/f3", "/f2"])
    #expect(result.map(\.kind) == [.recent, .recent, .favorite, .favorite, .favorite])
  }

  @Test("Una cartella già tra le preferite non occupa un posto anche tra le recenti")
  func favoritesAreNotRepeatedAsRecents() {
    let store = makeStore(existing: ["/a", "/b", "/c", "/fav"])
    store.setFavorite(url("/fav"), slot: 0)
    for path in ["/a", "/fav", "/b", "/c"] {
      store.recordRecent(url(path))
    }

    // Recenti, dalla più recente: c, b, fav, a. Fav è già preferita: restano c e b.
    #expect(paths(store.destinations()) == ["/c", "/b", "/fav"])
  }

  @Test("Le cartelle che non esistono più saltano, senza lasciare un buco")
  func missingFoldersAreSkipped() {
    let store = makeStore(existing: ["/presente", "/fav-presente"])
    store.recordRecent(url("/presente"))
    store.recordRecent(url("/sparita"))
    store.setFavorite(url("/fav-sparita"), slot: 0)
    store.setFavorite(url("/fav-presente"), slot: 1)

    #expect(paths(store.destinations()) == ["/presente", "/fav-presente"])
  }

  @Test("Una preferita sparita resta nella sua casella, così si vede e si può cambiare")
  func missingFavoriteStaysInSlot() {
    let store = makeStore(existing: [])

    store.setFavorite(url("/sparita"), slot: 1)

    #expect(store.favoriteSlots[1].map(Self.plain) == "/sparita")
    #expect(store.destinations().isEmpty)
  }

  @Test("Svuotare una casella la lascia vuota e non sposta le altre")
  func clearingASlot() {
    let store = makeStore(existing: ["/a", "/b"])
    store.setFavorite(url("/a"), slot: 0)
    store.setFavorite(url("/b"), slot: 1)

    store.setFavorite(nil, slot: 0)

    #expect(store.favoriteSlots.map { $0.map(Self.plain) } == [nil, "/b", nil, nil])
  }

  @Test("La stessa cartella in due caselle compare una volta sola")
  func sameFavoriteTwice() {
    let store = makeStore(existing: ["/a"])
    store.setFavorite(url("/a"), slot: 0)
    store.setFavorite(url("/a"), slot: 2)

    #expect(paths(store.destinations()) == ["/a"])
  }

  @Test("Una casella che non esiste è ignorata")
  func slotOutOfRange() {
    let store = makeStore(existing: ["/a"])

    store.setFavorite(url("/a"), slot: 4)
    store.setFavorite(url("/a"), slot: -1)

    #expect(store.favoriteSlots == [nil, nil, nil, nil])
  }

  @Test("Svuotare l'elenco toglie le recenti e lascia le preferite")
  func clearRecents() {
    let store = makeStore(existing: ["/a", "/f"])
    store.recordRecent(url("/a"))
    store.setFavorite(url("/f"), slot: 0)

    store.clearRecents()

    #expect(store.recents.isEmpty)
    #expect(paths(store.destinations()) == ["/f"])
  }

  @Test("Nel menu una cartella ha il nome e il percorso completo con la casa abbreviata")
  @MainActor
  func optionShowsNameAndPath() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let folder = home.appendingPathComponent("Sites/Clienti/Rossi", isDirectory: true)

    let option = OrbisOption(destination: Destination(url: folder, kind: .recent))

    #expect(option.subtitle == "~/Sites/Clienti/Rossi")
    #expect(option.title == "Rossi")
    #expect(option.badge == "clock")
  }

  @Test("Due cartelle con lo stesso nome si distinguono dal percorso")
  @MainActor
  func sameNameDifferentPath() {
    let first = OrbisOption(destination: Destination(url: url("/Users/prova/Clienti/Rossi"), kind: .favorite))
    let second = OrbisOption(destination: Destination(url: url("/Users/prova/Archivio/Rossi"), kind: .favorite))

    #expect(first.title == second.title)
    #expect(first.subtitle != second.subtitle)
    #expect(first.id != second.id)
  }

  @Test("Le voci del menu finiscono sempre con Scegli cartella")
  @MainActor
  func moveOptionsEndWithChoose() {
    let none = OrbisOption.moveOptions(for: [])
    #expect(none.map(\.id) == ["choose"])

    let some = OrbisOption.moveOptions(for: [Destination(url: url("/a"), kind: .recent)])
    #expect(some.count == 2)
    #expect(some.last?.id == "choose")
  }
}
