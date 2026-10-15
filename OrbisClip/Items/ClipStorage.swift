import Foundation

/// Un file conservato da Orbis Clip: un'immagine, la copia di un file.
nonisolated struct ClipBlob: Hashable, Codable, Sendable {
  var id = UUID()
  /// Il nome del file, con l'estensione: per le copie è quello dell'originale.
  var name: String

  var url: URL {
    ClipStorage.files.appending(path: id.uuidString, directoryHint: .isDirectory).appending(path: name)
  }
}

/// Dove Orbis Clip tiene i suoi dati: `~/Library/Application Support/Orbis Clip`, con l'elenco
/// degli elementi (`items.json`) e una cartella per ogni file conservato (`Files/<id>/<nome>`).
nonisolated enum ClipStorage {
  static let maximumFileSize = 10 * 1024 * 1024

  static let root = URL.applicationSupportDirectory.appending(path: "Orbis Clip", directoryHint: .isDirectory)
  static let files = root.appending(path: "Files", directoryHint: .isDirectory)
  static let itemsFile = root.appending(path: "items.json")

  enum StorageError: LocalizedError {
    case tooLarge(String)

    var errorDescription: String? {
      switch self {
      case .tooLarge(let name): "«\(name)» supera i 10 MB: Orbis Clip conserva solo file più piccoli."
      }
    }
  }

  static func store(_ data: Data, named name: String) throws -> ClipBlob {
    guard data.count <= maximumFileSize else { throw StorageError.tooLarge(name) }
    let blob = ClipBlob(name: name)
    try FileManager.default.createDirectory(at: blob.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: blob.url, options: .atomic)
    return blob
  }

  /// Una copia del file (o della cartella), che resta valida anche se l'originale si sposta.
  static func copy(_ source: URL) throws -> ClipBlob {
    guard size(of: source) <= maximumFileSize else { throw StorageError.tooLarge(source.lastPathComponent) }
    let blob = ClipBlob(name: source.lastPathComponent)
    try FileManager.default.createDirectory(at: blob.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: source, to: blob.url)
    return blob
  }

  static func remove(_ blob: ClipBlob) {
    try? FileManager.default.removeItem(at: blob.url.deletingLastPathComponent())
  }

  /// Toglie i file che nessun elemento usa più: quelli di un'aggiunta annullata, per esempio.
  static func removeUnused(keeping used: Set<UUID>) {
    let folders = (try? FileManager.default.contentsOfDirectory(at: files, includingPropertiesForKeys: nil)) ?? []
    for folder in folders {
      guard let id = UUID(uuidString: folder.lastPathComponent), !used.contains(id) else { continue }
      try? FileManager.default.removeItem(at: folder)
    }
  }

  /// La dimensione di un file, o di una cartella con tutto ciò che contiene.
  static func size(of url: URL) -> Int {
    let keys: Set<URLResourceKey> = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey]
    guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
    guard values.isDirectory == true else { return values.fileSize ?? 0 }
    let contents = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys))
    var total = 0
    while let child = contents?.nextObject() as? URL {
      total += (try? child.resourceValues(forKeys: keys))?.fileSize ?? 0
      if total > maximumFileSize { break }
    }
    return total
  }
}
