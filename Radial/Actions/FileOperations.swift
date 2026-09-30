import AppKit

nonisolated struct TrashedItem: Sendable, Equatable {
  let original: URL
  let trashed: URL
}

/// L'esito di un'operazione su più file: ogni file riesce o fallisce per conto suo.
nonisolated struct BatchResult<Item: Sendable>: Sendable {
  var done: [Item] = []
  var failed = 0
  /// Elementi che non c'era nulla da fare (già nella cartella di destinazione).
  var skipped = 0
}

nonisolated struct MovedItem: Sendable, Equatable {
  let original: URL
  let moved: URL
}

/// Un elemento da rinominare: il file com'è adesso e il nome che deve avere.
nonisolated struct RenameEntry: Sendable, Equatable {
  let source: URL
  let newName: String

  var destination: URL { source.deletingLastPathComponent().appendingPathComponent(newName) }
}

nonisolated struct RenamedItem: Sendable, Equatable {
  let original: URL
  let renamed: URL
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

  // MARK: Sposta

  /// Sposta gli elementi in una cartella. Non sovrascrive mai: se il nome è già occupato l'elemento
  /// arriva come "nome 2", come fa il Finder con "Mantieni entrambi". Chi è già in quella cartella
  /// resta dov'è, e una cartella non si può spostare dentro sé stessa.
  @concurrent
  static func move(_ urls: [URL], to folder: URL) async -> BatchResult<MovedItem> {
    let fileManager = FileManager.default
    var result = BatchResult<MovedItem>()
    let target = comparablePath(folder.resolvingSymlinksInPath())

    for url in urls {
      // Si risolvono i collegamenti della cartella che contiene l'elemento, non dell'elemento:
      // se è un alias lo si sposta lui, non ciò a cui punta.
      let parent = comparablePath(url.deletingLastPathComponent().resolvingSymlinksInPath())
      if parent == target {
        result.skipped += 1
        continue
      }
      let itemPath = (parent == "/" ? "" : parent) + "/" + url.lastPathComponent
      if target == itemPath || target.hasPrefix(itemPath + "/") {
        log.error("Sposta non riuscito: \(url.lastPathComponent, privacy: .public) verrebbe spostato dentro sé stesso")
        result.failed += 1
        continue
      }

      let (stem, ext) = nameParts(of: url)
      let destination = availableURL(in: folder, stem: stem, extension: ext)
      do {
        try fileManager.moveItem(at: url, to: destination)
        result.done.append(MovedItem(original: url, moved: destination))
      } catch {
        log.error("Sposta non riuscito: \(error.localizedDescription, privacy: .public)")
        result.failed += 1
      }
    }
    return result
  }

  /// Rimette gli elementi dov'erano. Non sovrascrive: se nel frattempo il loro posto è stato
  /// preso, quell'elemento resta dov'è arrivato.
  @concurrent
  static func moveBack(_ items: [MovedItem]) async -> BatchResult<URL> {
    var result = BatchResult<URL>()
    for item in items {
      do {
        try FileManager.default.moveItem(at: item.moved, to: item.original)
        result.done.append(item.original)
      } catch {
        log.error("Ripristino non riuscito: \(error.localizedDescription, privacy: .public)")
        result.failed += 1
      }
    }
    return result
  }

  private static func comparablePath(_ url: URL) -> String {
    let path = url.standardizedFileURL.path(percentEncoded: false)
    return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
  }

  // MARK: Rinomina

  /// Rinomina gli elementi. Non sovrascrive mai: se un nome è occupato da un elemento che non
  /// fa parte del gruppo, quell'elemento resta com'era.
  ///
  /// Quando un nuovo nome coincide con il vecchio nome di un altro elemento del gruppo (uno
  /// scambio, uno scorrimento di numeri, un cambio di sole maiuscole), i due passaggi non si
  /// possono fare uno dopo l'altro: gli elementi coinvolti vengono prima messi da parte con un
  /// nome provvisorio, poi portati al nome finale.
  @concurrent
  static func rename(_ entries: [RenameEntry]) async -> BatchResult<RenamedItem> {
    let fileManager = FileManager.default
    var result = BatchResult<RenamedItem>()

    let sourceKeys = Set(entries.map { pathKey($0.source) })
    let entangled = entries.filter { sourceKeys.contains(pathKey($0.destination)) }
    let direct = entries.filter { !sourceKeys.contains(pathKey($0.destination)) }

    for entry in direct {
      do {
        try fileManager.moveItem(at: entry.source, to: entry.destination)
        result.done.append(RenamedItem(original: entry.source, renamed: entry.destination))
      } catch {
        log.error("Rinomina non riuscita: \(error.localizedDescription, privacy: .public)")
        result.failed += 1
      }
    }

    var parked: [(entry: RenameEntry, temporary: URL)] = []
    for entry in entangled {
      let temporary = entry.source.deletingLastPathComponent()
        .appendingPathComponent(".radial-\(UUID().uuidString)")
      do {
        try fileManager.moveItem(at: entry.source, to: temporary)
        parked.append((entry, temporary))
      } catch {
        log.error("Rinomina non riuscita: \(error.localizedDescription, privacy: .public)")
        result.failed += 1
      }
    }
    for (entry, temporary) in parked {
      do {
        try fileManager.moveItem(at: temporary, to: entry.destination)
        result.done.append(RenamedItem(original: entry.source, renamed: entry.destination))
      } catch {
        log.error("Rinomina non riuscita: \(error.localizedDescription, privacy: .public)")
        // Il nome finale è occupato: l'elemento torna dov'era.
        try? fileManager.moveItem(at: temporary, to: entry.source)
        result.failed += 1
      }
    }
    return result
  }

  /// Cartella e nome come li confronta il disco, per riconoscere lo stesso elemento.
  private static func pathKey(_ url: URL) -> String {
    let directory = url.deletingLastPathComponent().standardizedFileURL.path(percentEncoded: false)
    return directory + "\u{0}" + RenamePlan.nameKey(url.lastPathComponent)
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
