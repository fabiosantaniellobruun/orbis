import Foundation
import Testing
@testable import Radial

/// Ogni test lavora in una cartella temporanea sua, rimossa alla fine.
final class FileOperationsTests {
  let directory: URL

  init() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("RadialTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: directory)
  }

  private func makeFile(_ name: String, contents: String = "prova") throws -> URL {
    let url = directory.appendingPathComponent(name)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  private func makeFolder(_ name: String) throws -> URL {
    let url = directory.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func names() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
  }

  private func entries(of archive: URL) throws -> [String] {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(filePath: "/usr/bin/zipinfo")
    process.arguments = ["-1", archive.path(percentEncoded: false)]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).sorted()
  }

  // MARK: Clona

  @Test("Clona mette la copia accanto all'originale, con lo stesso contenuto")
  func cloneCreatesSibling() async throws {
    let file = try makeFile("foto.jpg", contents: "contenuto")

    let result = await FileOperations.clone([file])

    #expect(result.failed == 0)
    #expect(try names() == ["foto copia.jpg", "foto.jpg"])
    let copy = try #require(result.done.first)
    #expect(try String(contentsOf: copy, encoding: .utf8) == "contenuto")
  }

  @Test("Clonare due volte numera la seconda copia")
  func cloneTwiceNumbersTheCopy() async throws {
    let file = try makeFile("foto.jpg")

    _ = await FileOperations.clone([file])
    _ = await FileOperations.clone([file])

    #expect(try names() == ["foto copia 2.jpg", "foto copia.jpg", "foto.jpg"])
  }

  @Test("Il punto nel nome di una cartella non è un'estensione")
  func cloneFolderKeepsWholeName() async throws {
    let folder = try makeFolder("Progetto v1.2")

    _ = await FileOperations.clone([folder])

    #expect(try names() == ["Progetto v1.2", "Progetto v1.2 copia"])
  }

  @Test("Un file che non esiste più conta come non riuscito, gli altri vanno avanti")
  func cloneReportsFailures() async throws {
    let file = try makeFile("uno.txt")
    let missing = directory.appendingPathComponent("sparito.txt")

    let result = await FileOperations.clone([missing, file])

    #expect(result.failed == 1)
    #expect(result.done.map(\.lastPathComponent) == ["uno copia.txt"])
  }

  // MARK: Comprimi

  @Test("Un elemento solo dà un archivio con il suo nome")
  func compressSingleItem() async throws {
    let file = try makeFile("foto.jpg")

    let archive = try await FileOperations.compress([file])

    #expect(archive.lastPathComponent == "foto.jpg.zip")
    #expect(try entries(of: archive) == ["foto.jpg"])
    #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
  }

  @Test("Più elementi finiscono in Archivio.zip, cartelle comprese")
  func compressSeveralItems() async throws {
    let file = try makeFile("uno.txt")
    let folder = try makeFolder("Cartella")
    try "dentro".write(to: folder.appendingPathComponent("due.txt"), atomically: true, encoding: .utf8)

    let archive = try await FileOperations.compress([file, folder])

    #expect(archive.lastPathComponent == "Archivio.zip")
    #expect(try entries(of: archive) == ["Cartella/", "Cartella/due.txt", "uno.txt"])
  }

  @Test("Un archivio esistente non viene sovrascritto")
  func compressDoesNotOverwrite() async throws {
    let file = try makeFile("foto.jpg")

    let first = try await FileOperations.compress([file])
    let second = try await FileOperations.compress([file])

    #expect(first.lastPathComponent == "foto.jpg.zip")
    #expect(second.lastPathComponent == "foto.jpg 2.zip")
  }

  @Test("Un nome che comincia con un trattino non viene preso per un'opzione di zip")
  func compressNameStartingWithDash() async throws {
    let file = try makeFile("-r.txt")

    let archive = try await FileOperations.compress([file])

    #expect(try entries(of: archive) == ["-r.txt"])
  }

  // MARK: Cestino

  @Test("Cestina e poi rimette a posto")
  func trashAndPutBack() async throws {
    let file = try makeFile("uno.txt", contents: "da ripristinare")

    let trashed = await FileOperations.trash([file])
    #expect(trashed.failed == 0)
    #expect(try names().isEmpty)

    let restored = await FileOperations.putBack(trashed.done)
    #expect(restored.failed == 0)
    #expect(try names() == ["uno.txt"])
    #expect(try String(contentsOf: file, encoding: .utf8) == "da ripristinare")
  }

  @Test("Rimettere a posto non sovrascrive ciò che nel frattempo ha preso quel nome")
  func putBackDoesNotOverwrite() async throws {
    let file = try makeFile("uno.txt", contents: "vecchio")
    let trashed = await FileOperations.trash([file])
    _ = try makeFile("uno.txt", contents: "nuovo")

    let restored = await FileOperations.putBack(trashed.done)

    #expect(restored.failed == 1)
    #expect(try String(contentsOf: file, encoding: .utf8) == "nuovo")
    // Il file cestinato resta nel Cestino: lo si toglie per non lasciare tracce del test.
    for item in trashed.done {
      try? FileManager.default.removeItem(at: item.trashed)
    }
  }

  // MARK: Nomi

  @Test("Il primo nome libero salta quelli già presi")
  func availableURLSkipsTakenNames() throws {
    _ = try makeFile("Archivio.zip")
    _ = try makeFile("Archivio 2.zip")

    let url = FileOperations.availableURL(in: directory, stem: "Archivio", extension: "zip")

    #expect(url.lastPathComponent == "Archivio 3.zip")
  }
}
