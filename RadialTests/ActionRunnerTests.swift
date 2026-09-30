import AppKit
import Testing
@testable import Radial

@MainActor
final class ActionRunnerTests {
  let directory: URL

  init() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("RadialTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: directory)
  }

  private func makeFiles(_ names: String...) throws -> [URL] {
    try names.map { name in
      let url = directory.appendingPathComponent(name)
      try "prova".write(to: url, atomically: true, encoding: .utf8)
      return url
    }
  }

  private func names() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
  }

  private func action(_ id: RadialAction.ID) throws -> RadialAction {
    try #require(RadialAction.all.first { $0.id == id })
  }

  @Test("Clona dice quanti elementi ha clonato e sa quali copie togliere")
  func cloneOutcome() async throws {
    let files = try makeFiles("uno.txt", "due.txt")

    let outcome = try await ActionRunner.run(action(.clone), on: files)

    #expect(outcome.message == "2 elementi clonati")
    guard case .discard(let created) = outcome.undo else {
      Issue.record("Clona deve potersi annullare togliendo le copie")
      return
    }
    #expect(created.map(\.lastPathComponent).sorted() == ["due copia.txt", "uno copia.txt"])
  }

  @Test("Con un elemento solo il messaggio è al singolare")
  func cloneSingularMessage() async throws {
    let files = try makeFiles("uno.txt")

    let outcome = try await ActionRunner.run(action(.clone), on: files)

    #expect(outcome.message == "1 elemento clonato")
  }

  @Test("Se qualcosa non riesce, il messaggio lo dice")
  func clonePartialFailure() async throws {
    let files = try makeFiles("uno.txt") + [directory.appendingPathComponent("sparito.txt")]

    let outcome = try await ActionRunner.run(action(.clone), on: files)

    #expect(outcome.message == "1 elemento clonato, 1 non riuscito")
  }

  @Test("Se non riesce nulla, non c'è niente da annullare")
  func cloneTotalFailure() async throws {
    let missing = directory.appendingPathComponent("sparito.txt")

    let outcome = try await ActionRunner.run(action(.clone), on: [missing])

    #expect(outcome.message == "Impossibile clonare")
    #expect(outcome.undo == nil)
  }

  @Test("Comprimi nomina l'archivio creato")
  func compressOutcome() async throws {
    let files = try makeFiles("uno.txt", "due.txt")

    let outcome = try await ActionRunner.run(action(.compress), on: files)

    #expect(outcome.message == "Archivio.zip creato")
    #expect(try names() == ["Archivio.zip", "due.txt", "uno.txt"])
  }

  @Test("Cestina e Annulla riportano i file dov'erano")
  func trashThenUndo() async throws {
    let files = try makeFiles("uno.txt", "due.txt")

    let outcome = try await ActionRunner.run(action(.trash), on: files)
    #expect(outcome.message == "2 elementi nel Cestino")
    #expect(try names().isEmpty)

    let undone = await ActionRunner.undo(try #require(outcome.undo))
    #expect(undone.message == "Annullato")
    #expect(try names() == ["due.txt", "uno.txt"])
  }

  @Test("Copia percorso mette un percorso per riga, senza la barra finale delle cartelle")
  func copyPath() async throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let file = try makeFiles("uno.txt")[0]
    let folder = directory.appendingPathComponent("Cartella", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let outcome = try await ActionRunner.run(action(.copyPath), on: [file, folder], pasteboard: pasteboard)

    #expect(outcome.message == "2 percorsi copiati")
    #expect(outcome.undo == nil)
    let lines = try #require(pasteboard.string(forType: .string)).split(separator: "\n")
    #expect(lines.count == 2)
    #expect(lines.first?.hasSuffix("/uno.txt") == true)
    #expect(lines.last?.hasSuffix("/Cartella") == true)
  }

  // MARK: Sposta

  /// Un archivio a sé per le cartelle recenti, così i test non toccano quello dell'app.
  private func makeStore() -> DestinationStore {
    let suite = "RadialTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return DestinationStore(defaults: defaults)
  }

  private func makeDestination(_ name: String) throws -> URL {
    let url = directory.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test("Sposta dice quanti elementi ha spostato e dove, e ricorda la cartella")
  func moveOutcome() async throws {
    let files = try makeFiles("uno.txt", "due.txt")
    let destination = try makeDestination("Archivio")
    let store = makeStore()

    let outcome = await ActionRunner.move(files, to: destination, store: store)

    #expect(outcome.message == "2 elementi spostati in «Archivio»")
    #expect(outcome.undo != nil)
    #expect(store.recents.map(\.lastPathComponent) == ["Archivio"])
  }

  @Test("Con un elemento solo il messaggio è al singolare")
  func moveSingularMessage() async throws {
    let files = try makeFiles("uno.txt")
    let destination = try makeDestination("Archivio")

    let outcome = await ActionRunner.move(files, to: destination, store: makeStore())

    #expect(outcome.message == "1 elemento spostato in «Archivio»")
  }

  @Test("Se i file sono già lì lo dice, senza offrire di annullare e senza ricordare la cartella")
  func moveAlreadyThere() async throws {
    let destination = try makeDestination("Archivio")
    let inside = destination.appendingPathComponent("gia.txt")
    try "x".write(to: inside, atomically: true, encoding: .utf8)
    let store = makeStore()

    let outcome = await ActionRunner.move([inside], to: destination, store: store)

    #expect(outcome.message == "Già in «Archivio»")
    #expect(outcome.undo == nil)
    #expect(store.recents.isEmpty)
  }

  @Test("Se qualcosa non riesce, il messaggio lo dice")
  func movePartialFailure() async throws {
    let files = try makeFiles("uno.txt") + [directory.appendingPathComponent("sparito.txt")]
    let destination = try makeDestination("Archivio")

    let outcome = await ActionRunner.move(files, to: destination, store: makeStore())

    #expect(outcome.message == "1 elemento spostato in «Archivio», 1 non riuscito")
  }

  @Test("Se non riesce nulla non c'è niente da annullare e la cartella non si ricorda")
  func moveTotalFailure() async throws {
    let missing = directory.appendingPathComponent("sparito.txt")
    let destination = try makeDestination("Archivio")
    let store = makeStore()

    let outcome = await ActionRunner.move([missing], to: destination, store: store)

    #expect(outcome.message == "Impossibile spostare")
    #expect(outcome.undo == nil)
    #expect(store.recents.isEmpty)
  }

  @Test("Ridimensiona senza pannello non tocca i file")
  func resizeNeedsItsPanel() async throws {
    let files = try makeFiles("uno.txt")

    let outcome = try await ActionRunner.run(action(.resize), on: files)

    #expect(outcome.undo == nil)
    #expect(try names() == ["uno.txt"])
  }
}
