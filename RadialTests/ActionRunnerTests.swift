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

  @Test("Le azioni non ancora pronte lo dicono e non toccano i file")
  func unimplementedAction() async throws {
    let files = try makeFiles("uno.txt")

    let outcome = try await ActionRunner.run(action(.rename), on: files)

    #expect(outcome.message == "Rinomina: in arrivo")
    #expect(outcome.undo == nil)
    #expect(try names() == ["uno.txt"])
  }
}
