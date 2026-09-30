import AppKit

/// Come si annulla un'azione appena eseguita.
nonisolated enum UndoStep: Sendable {
  /// Cestina ciò che l'azione ha creato.
  case discard([URL])
  /// Rimette a posto ciò che l'azione ha cestinato.
  case putBack([TrashedItem])
  /// Ridà ai file il nome che avevano.
  case renameBack([RenamedItem])
  /// Riporta i file nella cartella da cui erano partiti.
  case moveBack([MovedItem])
}

/// Cosa mostrare dopo un'azione.
nonisolated struct ActionOutcome: Sendable {
  var symbol = "checkmark.circle.fill"
  var message: String
  var undo: UndoStep?

  static func failure(_ message: String) -> ActionOutcome {
    ActionOutcome(symbol: "exclamationmark.triangle.fill", message: message)
  }
}

/// Esegue le azioni del menu sui file rilasciati.
enum ActionRunner {
  static func run(
    _ action: RadialAction,
    on urls: [URL],
    pasteboard: NSPasteboard = .general
  ) async -> ActionOutcome {
    switch action.id {
    case .clone:
      let result = await FileOperations.clone(urls)
      return outcome(
        of: result,
        one: "elemento clonato",
        many: "elementi clonati",
        failure: "Impossibile clonare",
        undo: .discard(result.done)
      )

    case .compress:
      do {
        let archive = try await FileOperations.compress(urls)
        return ActionOutcome(message: "\(archive.lastPathComponent) creato", undo: .discard([archive]))
      } catch {
        log.error("Comprimi non riuscito: \(String(describing: error), privacy: .private)")
        return .failure("Impossibile comprimere")
      }

    case .copyPath:
      let paths = urls.map(\.displayPath)
      pasteboard.clearContents()
      pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
      return ActionOutcome(message: paths.count == 1 ? "Percorso copiato" : "\(paths.count) percorsi copiati")

    case .trash:
      let result = await FileOperations.trash(urls)
      return outcome(
        of: result,
        one: "elemento nel Cestino",
        many: "elementi nel Cestino",
        failure: "Impossibile cestinare",
        undo: .putBack(result.done)
      )

    case .rename:
      // Servono le opzioni: se ne occupa il pannello di `RenameController`, che poi chiama `rename`.
      return .failure("Rinomina passa dal suo pannello")

    case .move:
      // Serve la cartella di destinazione, scelta nel secondo anello: vedi `move(_:to:)`.
      return .failure("Sposta ha bisogno di una cartella")

    case .convert:
      // Serve il formato, scelto nel secondo anello: vedi `convert(_:to:)`.
      return .failure("Converti in ha bisogno di un formato")

    case .resize:
      return ActionOutcome(symbol: action.symbol, message: "\(action.title): in arrivo")
    }
  }

  static func convert(_ urls: [URL], to format: ImageFormat) async -> ActionOutcome {
    let result = await FileOperations.convert(urls, to: format)

    guard !result.done.isEmpty else {
      if result.failed == 0, result.skipped > 0 {
        let reason = result.skipped == 1 ? "non è un'immagine da convertire" : "non sono immagini da convertire"
        return ActionOutcome(symbol: "info.circle.fill", message: "\(result.skipped == 1 ? "Il file" : "I file") \(reason) in \(format.title)")
      }
      return .failure("Impossibile convertire")
    }

    let count = result.done.count
    var message = "\(count) \(count == 1 ? "immagine convertita" : "immagini convertite") in \(format.title)"
    if result.failed > 0 {
      message += ", \(result.failed) non \(result.failed == 1 ? "riuscita" : "riuscite")"
    }
    if result.skipped > 0 {
      message += ", \(result.skipped) \(result.skipped == 1 ? "saltato" : "saltati")"
    }
    return ActionOutcome(message: message, undo: .discard(result.done))
  }

  static func move(_ urls: [URL], to folder: URL, store: DestinationStore = DestinationStore()) async -> ActionOutcome {
    let result = await FileOperations.move(urls, to: folder)
    let name = FileManager.default.displayName(atPath: folder.path(percentEncoded: false))

    guard !result.done.isEmpty else {
      if result.failed == 0, result.skipped > 0 {
        return ActionOutcome(symbol: "info.circle.fill", message: "Già in «\(name)»")
      }
      return .failure("Impossibile spostare")
    }

    store.recordRecent(folder)
    let count = result.done.count
    var message = "\(count) \(count == 1 ? "elemento spostato" : "elementi spostati") in «\(name)»"
    if result.failed > 0 {
      message += ", \(result.failed) non \(result.failed == 1 ? "riuscito" : "riusciti")"
    }
    return ActionOutcome(message: message, undo: .moveBack(result.done))
  }

  static func rename(_ entries: [RenameEntry]) async -> ActionOutcome {
    let result = await FileOperations.rename(entries)
    return outcome(
      of: result,
      one: "elemento rinominato",
      many: "elementi rinominati",
      failure: "Impossibile rinominare",
      undo: .renameBack(result.done)
    )
  }

  static func undo(_ step: UndoStep) async -> ActionOutcome {
    let failed: Int
    switch step {
    case .discard(let urls):
      failed = await FileOperations.trash(urls).failed
    case .putBack(let items):
      failed = await FileOperations.putBack(items).failed
    case .renameBack(let items):
      let entries = items.map { RenameEntry(source: $0.renamed, newName: $0.original.lastPathComponent) }
      failed = await FileOperations.rename(entries).failed
    case .moveBack(let items):
      failed = await FileOperations.moveBack(items).failed
    }
    guard failed == 0 else { return .failure("Impossibile annullare") }
    return ActionOutcome(symbol: "arrow.uturn.backward.circle.fill", message: "Annullato")
  }

  private static func outcome<Item>(
    of result: BatchResult<Item>,
    one: String,
    many: String,
    failure: String,
    undo: UndoStep
  ) -> ActionOutcome {
    guard !result.done.isEmpty else { return .failure(failure) }
    var message = "\(result.done.count) \(result.done.count == 1 ? one : many)"
    if result.failed > 0 {
      message += ", \(result.failed) non \(result.failed == 1 ? "riuscito" : "riusciti")"
    }
    return ActionOutcome(message: message, undo: undo)
  }
}

private extension URL {
  /// Il percorso come lo scriverebbe il Finder: senza la barra finale delle cartelle.
  var displayPath: String {
    let path = path(percentEncoded: false)
    return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
  }
}
