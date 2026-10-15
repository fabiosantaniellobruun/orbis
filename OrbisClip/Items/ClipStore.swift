import AppKit
import Observation

/// Gli elementi salvati, in `items.json` dentro la cartella di Orbis Clip. Si riscrive a ogni
/// modifica: sono poche decine di elementi, e i file stanno a parte.
@Observable final class ClipStore {
  static let favoriteCount = 6
  static let recentCount = 4
  static let resultCount = 10

  private(set) var items: [ClipItem] = []
  @ObservationIgnored private let persists: Bool

  /// - Parameter persists: `false` per un elenco di prova che non tocca il disco.
  init(persists: Bool = true) {
    self.persists = persists
    if persists { load() }
  }

  /// Gli ultimi preferiti aggiunti.
  var favorites: [ClipItem] {
    Array(items.filter(\.isFavorite).sorted { $0.addedAt > $1.addedAt }.prefix(Self.favoriteCount))
  }

  /// Gli ultimi usati, senza quelli che compaiono già tra i preferiti.
  var recents: [ClipItem] {
    let shown = Set(favorites.map(\.id))
    let used = items.filter { $0.lastUsedAt != nil && !shown.contains($0.id) }
    return Array(used.sorted { $0.lastUsedAt! > $1.lastUsedAt! }.prefix(Self.recentCount))
  }

  /// Gli elementi che rispondono alla ricerca, dal più pertinente; a pari merito, il più usato
  /// di recente.
  func results(for query: String) -> [ClipItem] {
    items
      .map { (item: $0, score: $0.score(for: query)) }
      .filter { $0.score > 0 }
      .sorted { lhs, rhs in
        guard lhs.score == rhs.score else { return lhs.score > rhs.score }
        return (lhs.item.lastUsedAt ?? .distantPast) > (rhs.item.lastUsedAt ?? .distantPast)
      }
      .prefix(Self.resultCount)
      .map(\.item)
  }

  func item(_ id: ClipItem.ID) -> ClipItem? {
    items.first { $0.id == id }
  }

  // MARK: Modifiche

  func add(_ item: ClipItem) {
    items.append(item)
    save()
  }

  func update(_ item: ClipItem) {
    guard let index = items.firstIndex(where: { $0.id == item.id }), items[index] != item else { return }
    items[index] = item
    save()
  }

  /// Toglie l'elemento e i file che conservava.
  func remove(_ id: ClipItem.ID) {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    let removed = items.remove(at: index)
    if persists { removed.blobs.forEach(ClipStorage.remove) }
    save()
  }

  func markUsed(_ id: ClipItem.ID) {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    items[index].lastUsedAt = Date()
    save()
  }

  /// Scarica l'anteprima dei link che non ce l'hanno ancora: appena aggiunti, o quando mancava la
  /// rete. Si riprova a ogni avvio.
  func loadMissingPreviews() async {
    for item in items where item.preview == nil {
      guard case .link(let url) = item.content,
            let png = await LinkPreview.png(for: url),
            let blob = try? ClipStorage.store(png, named: "Anteprima.png")
      else { continue }
      // Nel frattempo l'elemento può essere stato eliminato.
      guard var current = self.item(item.id) else {
        ClipStorage.remove(blob)
        continue
      }
      current.preview = blob
      update(current)
    }
  }

  // MARK: Disco

  private func load() {
    let url = ClipStorage.itemsFile
    guard let data = try? Data(contentsOf: url) else { return }
    do {
      items = try Self.decoder.decode([ClipItem].self, from: data)
      // I file di un'aggiunta annullata, o di un elemento tolto mentre l'app si chiudeva.
      ClipStorage.removeUnused(keeping: Set(items.flatMap(\.blobs).map(\.id)))
    } catch {
      // Un elenco illeggibile non si sovrascrive: lo si mette da parte, con i suoi file.
      log.error("Elenco illeggibile: \(error.localizedDescription, privacy: .public)")
      let aside = url.deletingPathExtension().appendingPathExtension("illeggibile-\(Int(Date().timeIntervalSince1970)).json")
      try? FileManager.default.moveItem(at: url, to: aside)
    }
  }

  private func save() {
    guard persists else { return }
    do {
      try FileManager.default.createDirectory(at: ClipStorage.root, withIntermediateDirectories: true)
      try Self.encoder.encode(items).write(to: ClipStorage.itemsFile, options: .atomic)
    } catch {
      log.error("Non riesco a salvare gli elementi: \(error.localizedDescription, privacy: .public)")
    }
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}

// MARK: Esempi

#if DEBUG
extension ClipStore {
  /// Un elemento per tipo, per provare il pannello senza toccare gli elementi veri (`--samples`).
  /// I file degli esempi finiscono nella cartella di Orbis Clip e si tolgono al prossimo avvio.
  static func withSamples() -> ClipStore {
    let store = ClipStore(persists: false)
    let now = Date()
    func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
    func text(_ string: String) -> ClipItem.Content { .text(string, rtf: nil) }

    var samples: [ClipItem] = [
      ClipItem(name: "LinkedIn", shortcut: "lin", isFavorite: true,
               content: .link(URL(string: "https://www.linkedin.com/in/")!), addedAt: ago(10)),
      ClipItem(name: "Firma email", shortcut: "firma", isFavorite: true,
               content: text("Un saluto,\nFabio"), addedAt: ago(20)),
      ClipItem(name: "Wi-Fi ufficio", shortcut: "wifi", isFavorite: true,
               content: .password(account: "wifi-ufficio"), addedAt: ago(50)),
      ClipItem(name: "Orbis su GitHub", shortcut: "gh", isFavorite: true,
               content: .link(URL(string: "https://github.com/fabiosantaniellobruun/orbis")!), addedAt: ago(60)),
      ClipItem(name: "Indirizzo ufficio", shortcut: "ind",
               content: text("Via Esempio 1, 20100 Milano"), addedAt: ago(500), lastUsedAt: ago(5)),
      ClipItem(name: "Calendario", shortcut: "cal",
               content: .link(URL(string: "https://calendar.google.com")!), addedAt: ago(600), lastUsedAt: ago(15)),
      ClipItem(name: "Grazie, a presto",
               content: text("Grazie mille, ci sentiamo presto!"), addedAt: ago(700), lastUsedAt: ago(25)),
      ClipItem(name: "Codice cliente", shortcut: "cod",
               content: text("GS-2026-001"), addedAt: ago(800), lastUsedAt: ago(35)),
    ]
    if let logo = try? ClipStorage.store(samplePNG(), named: "Logo.png") {
      samples.append(ClipItem(name: "Logo", shortcut: "logo", isFavorite: true, content: .image(logo), addedAt: ago(30)))
    }
    if let note = try? ClipStorage.store(Data("Da ricordare".utf8), named: "Promemoria.txt") {
      samples.append(ClipItem(name: "Promemoria", isFavorite: true, content: .file(note), addedAt: ago(40)))
    }
    samples.forEach(store.add)
    return store
  }

  private static func samplePNG() -> Data {
    let side = 96
    guard let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return Data() }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGradient(colors: [.systemTeal, .systemIndigo])?.draw(in: NSRect(x: 0, y: 0, width: side, height: side), angle: 45)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:]) ?? Data()
  }
}
#endif
