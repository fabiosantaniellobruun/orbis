import AppKit

nonisolated struct TrashedItem: Sendable, Equatable {
  let original: URL
  let trashed: URL
}

/// L'esito di un'operazione su più file: ogni file riesce o fallisce per conto suo.
nonisolated struct BatchResult<Item: Sendable>: Sendable {
  var done: [Item] = []
  var failed = 0
}

nonisolated enum FileOperationError: Error {
  case noFiles
  case processFailed(status: Int32, message: String)
}

/// Le operazioni sui file. Girano fuori dal thread principale: copie e archivi possono durare.
nonisolated enum FileOperations {
  // MARK: Clona

  /// Copia ogni elemento accanto all'originale, con il nome che userebbe il Finder:
  /// "foto copia.jpg", poi "foto copia 2.jpg".
  @concurrent
  static func clone(_ urls: [URL]) async -> BatchResult<URL> {
    var result = BatchResult<URL>()
    for url in urls {
      let (stem, ext) = nameParts(of: url)
      let destination = availableURL(
        in: url.deletingLastPathComponent(),
        stem: "\(stem) copia",
        extension: ext
      )
      do {
        try FileManager.default.copyItem(at: url, to: destination)
        result.done.append(destination)
      } catch {
        log.error("Clona non riuscito: \(error.localizedDescription, privacy: .public)")
        result.failed += 1
      }
    }
    return result
  }

  // MARK: Comprimi

  /// Crea un archivio zip accanto al primo elemento: "foto.jpg.zip" per un elemento solo,
  /// "Archivio.zip" per più elementi.
  @concurrent
  static func compress(_ urls: [URL]) async throws -> URL {
    guard let first = urls.first else { throw FileOperationError.noFiles }
    let destination = availableURL(
      in: first.deletingLastPathComponent(),
      stem: urls.count == 1 ? first.lastPathComponent : "Archivio",
      extension: "zip"
    )
    do {
      // zip registra i percorsi relativi alla cartella da cui parte e aggiunge a un archivio
      // esistente: un giro per ogni cartella d'origine.
      let byParent = Dictionary(grouping: urls) { $0.deletingLastPathComponent() }
      for (parent, items) in byParent {
        let names = items.map { "./\($0.lastPathComponent)" }
        try await run(
          "/usr/bin/zip",
          ["-r", "-q", "-y", "-X", destination.path(percentEncoded: false)] + names + ["-x", "*.DS_Store"],
          in: parent
        )
      }
    } catch {
      try? FileManager.default.removeItem(at: destination)
      throw error
    }
    return destination
  }

  // MARK: Cestino

  /// Usa la stessa chiamata del Finder: `FileManager.trashItem` sposta il file ma non annota da dove
  /// viene, e il Finder non potrebbe più rimetterlo a posto ("Ripristina" resterebbe grigio).
  @concurrent
  static func trash(_ urls: [URL]) async -> BatchResult<TrashedItem> {
    var result = BatchResult<TrashedItem>()
    for url in urls {
      let moved = await recycle(url)
      if let trashed = moved {
        result.done.append(TrashedItem(original: url, trashed: trashed))
      } else {
        log.error("Cestina non riuscito: \(url.lastPathComponent, privacy: .public)")
        result.failed += 1
      }
    }
    return result
  }

  private static func recycle(_ url: URL) async -> URL? {
    await withCheckedContinuation { continuation in
      NSWorkspace.shared.recycle([url]) { newURLs, error in
        if let error {
          log.error("recycle: \(error.localizedDescription, privacy: .public)")
        }
        continuation.resume(returning: newURLs[url])
      }
    }
  }

  /// Rimette al loro posto gli elementi cestinati. Non sovrascrive: se nel frattempo al posto
  /// dell'originale c'è altro, quell'elemento resta nel Cestino.
  @concurrent
  static func putBack(_ items: [TrashedItem]) async -> BatchResult<URL> {
    var result = BatchResult<URL>()
    for item in items {
      do {
        try FileManager.default.moveItem(at: item.trashed, to: item.original)
        result.done.append(item.original)
      } catch {
        log.error("Ripristino non riuscito: \(error.localizedDescription, privacy: .public)")
        result.failed += 1
      }
    }
    return result
  }

  // MARK: Nomi

  /// Il primo nome libero nella cartella: "stem.ext", poi "stem 2.ext", "stem 3.ext"…
  static func availableURL(in directory: URL, stem: String, extension ext: String) -> URL {
    func candidate(_ number: Int) -> URL {
      let name = number == 1 ? stem : "\(stem) \(number)"
      let url = directory.appendingPathComponent(name)
      return ext.isEmpty ? url : url.appendingPathExtension(ext)
    }
    var number = 1
    while FileManager.default.fileExists(atPath: candidate(number).path(percentEncoded: false)) {
      number += 1
    }
    return candidate(number)
  }

  /// Nome ed estensione. Per le cartelle il punto fa parte del nome: "Progetto v1.2" non ha
  /// estensione. I pacchetti (come le app) si comportano invece come file.
  static func nameParts(of url: URL) -> (stem: String, extension: String) {
    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
    if values?.isDirectory == true, values?.isPackage != true {
      return (url.lastPathComponent, "")
    }
    return (url.deletingPathExtension().lastPathComponent, url.pathExtension)
  }

  // MARK: Processi

  @concurrent
  private static func run(_ executable: String, _ arguments: [String], in directory: URL) async throws {
    let process = Process()
    process.executableURL = URL(filePath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.standardOutput = FileHandle.nullDevice
    process.standardError = Pipe()

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      process.terminationHandler = { process in
        guard process.terminationStatus != 0 else {
          continuation.resume()
          return
        }
        let output = (process.standardError as? Pipe)?.fileHandleForReading.readDataToEndOfFile()
        continuation.resume(throwing: FileOperationError.processFailed(
          status: process.terminationStatus,
          message: String(decoding: output ?? Data(), as: UTF8.self)
        ))
      }
      do {
        try process.run()
      } catch {
        // Il processo non è partito: il gestore di fine non verrà mai chiamato.
        process.terminationHandler = nil
        continuation.resume(throwing: error)
      }
    }
  }
}
