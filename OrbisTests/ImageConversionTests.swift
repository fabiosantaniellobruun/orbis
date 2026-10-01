import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Orbis

/// Ogni test lavora in una cartella temporanea sua, rimossa alla fine.
@MainActor
final class ImageConversionTests {
  let directory: URL

  init() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("OrbisTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: directory)
  }

  // MARK: Aiuti

  /// Un'immagine a tinta unita, opaca o con trasparenza.
  private func makeImage(width: Int = 40, height: Int = 30, transparent: Bool = false) throws -> CGImage {
    let info = transparent ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
    let context = try #require(CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info.rawValue
    ))
    if !transparent {
      context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    } else {
      // Un quadrato rosso nell'angolo: il resto resta trasparente.
      context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
    }
    return try #require(context.makeImage())
  }

  @discardableResult
  private func writeImage(
    _ image: CGImage,
    named name: String,
    as type: UTType = .png,
    properties: [CFString: Any] = [:]
  ) throws -> URL {
    let url = directory.appendingPathComponent(name)
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    try #require(CGImageDestinationFinalize(destination))
    return url
  }

  private func type(of url: URL) -> String? {
    ImageConverter.imageType(of: url)
  }

  private func size(of url: URL) throws -> (width: Int, height: Int) {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    return (
      properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
      properties[kCGImagePropertyPixelHeight] as? Int ?? 0
    )
  }

  /// Il colore di un pixel (0, 0 è l'angolo in alto a sinistra).
  private func pixel(of url: URL, x: Int, y: Int) throws -> (r: Int, g: Int, b: Int) {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = try #require(CGContext(
      data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
  }

  private func names() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
  }

  // MARK: Formati

  @Test("PNG e JPEG si sanno sempre scrivere, e tutti i formati proposti sono davvero scrivibili")
  func availableFormats() {
    let available = ImageFormat.available

    #expect(available.contains(.png))
    #expect(available.contains(.jpeg))
    let writable = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
    for format in available {
      #expect(writable.contains(format.typeIdentifier), "\(format.title)")
    }
  }

  @Test("Ogni formato ha estensione e tipo propri")
  func formatsAreDistinct() {
    #expect(Set(ImageFormat.allCases.map(\.fileExtension)).count == ImageFormat.allCases.count)
    #expect(Set(ImageFormat.allCases.map(\.typeIdentifier)).count == ImageFormat.allCases.count)
  }

  // MARK: Conversione

  @Test("Una PNG diventa JPEG, HEIC, AVIF o TIFF, con le stesse dimensioni", arguments: [
    ImageFormat.jpeg, .heic, .avif, .tiff,
  ])
  func convertsPNG(format: ImageFormat) async throws {
    try #require(ImageFormat.available.contains(format), "\(format.title) non si scrive su questo Mac")
    let source = try writeImage(makeImage(width: 64, height: 48), named: "foto.png")

    let result = await FileOperations.convert([source], to: format)

    #expect(result.failed == 0)
    let created = try #require(result.done.first)
    #expect(created.lastPathComponent == "foto.\(format.fileExtension)")
    #expect(type(of: created) == format.typeIdentifier)
    let dimensions = try size(of: created)
    #expect(dimensions.width == 64)
    #expect(dimensions.height == 48)
    // L'originale resta dov'è.
    #expect(FileManager.default.fileExists(atPath: source.path(percentEncoded: false)))
  }

  @Test("Una JPEG diventa PNG")
  func convertsJPEGToPNG() async throws {
    let source = try writeImage(makeImage(), named: "foto.jpg", as: .jpeg)

    let result = await FileOperations.convert([source], to: .png)

    #expect(try names() == ["foto.jpg", "foto.png"])
    #expect(type(of: try #require(result.done.first)) == UTType.png.identifier)
  }

  @Test("Il fondo trasparente diventa bianco in JPEG, non nero")
  func transparencyBecomesWhiteInJPEG() async throws {
    let source = try writeImage(makeImage(width: 40, height: 40, transparent: true), named: "logo.png")

    let result = await FileOperations.convert([source], to: .jpeg)
    let created = try #require(result.done.first)

    // L'angolo in alto a destra era trasparente.
    let transparent = try pixel(of: created, x: 35, y: 5)
    #expect(transparent.r > 235 && transparent.g > 235 && transparent.b > 235, "era \(transparent)")
    // Il quadrato rosso, in basso a sinistra, resta rosso.
    let red = try pixel(of: created, x: 5, y: 35)
    #expect(red.r > 180 && red.g < 90 && red.b < 90, "era \(red)")
  }

  @Test("La trasparenza si conserva in PNG")
  func transparencyIsKeptInPNG() async throws {
    let source = try writeImage(makeImage(width: 40, height: 40, transparent: true), named: "logo.tiff", as: .tiff)

    let result = await FileOperations.convert([source], to: .png)
    let created = try #require(result.done.first)

    let source2 = try #require(CGImageSourceCreateWithURL(created as CFURL, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source2, 0, nil) as? [CFString: Any])
    #expect(properties[kCGImagePropertyHasAlpha] as? Bool == true)
  }

  @Test("L'orientamento dell'originale si conserva")
  func orientationIsKept() async throws {
    let source = try writeImage(
      makeImage(width: 40, height: 20), named: "foto.jpg", as: .jpeg,
      properties: [kCGImagePropertyOrientation: 6]
    )

    let result = await FileOperations.convert([source], to: .tiff)
    let created = try #require(result.done.first)

    let converted = try #require(CGImageSourceCreateWithURL(created as CFURL, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(converted, 0, nil) as? [CFString: Any])
    #expect(properties[kCGImagePropertyOrientation] as? Int == 6)
  }

  @Test("Di un'immagine animata si prende il primo fotogramma")
  func animatedGIFUsesFirstFrame() async throws {
    let url = directory.appendingPathComponent("animata.gif")
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 2, nil))
    CGImageDestinationAddImage(destination, try makeImage(width: 20, height: 10), nil)
    CGImageDestinationAddImage(destination, try makeImage(width: 20, height: 10), nil)
    try #require(CGImageDestinationFinalize(destination))

    let result = await FileOperations.convert([url], to: .png)

    #expect(result.failed == 0)
    let created = try #require(result.done.first)
    let dimensions = try size(of: created)
    #expect(dimensions.width == 20 && dimensions.height == 10)
    let converted = try #require(CGImageSourceCreateWithURL(created as CFURL, nil))
    #expect(CGImageSourceGetCount(converted) == 1)
  }

  // MARK: Cosa si salta

  @Test("Chi è già in quel formato si salta e non si duplica")
  func sameFormatIsSkipped() async throws {
    let source = try writeImage(makeImage(), named: "foto.png")

    let result = await FileOperations.convert([source], to: .png)

    #expect(result.done.isEmpty)
    #expect(result.skipped == 1)
    #expect(try names() == ["foto.png"])
  }

  @Test("Un file che non è un'immagine si salta")
  func nonImageIsSkipped() async throws {
    let text = directory.appendingPathComponent("nota.txt")
    try "ciao".write(to: text, atomically: true, encoding: .utf8)
    let image = try writeImage(makeImage(), named: "foto.png")

    let result = await FileOperations.convert([text, image], to: .jpeg)

    #expect(result.skipped == 1)
    #expect(result.done.map(\.lastPathComponent) == ["foto.jpg"])
    #expect(try names() == ["foto.jpg", "foto.png", "nota.txt"])
  }

  @Test("Una cartella si salta")
  func folderIsSkipped() async throws {
    let folder = directory.appendingPathComponent("Immagini", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    let result = await FileOperations.convert([folder], to: .jpeg)

    #expect(result.skipped == 1)
    #expect(result.done.isEmpty)
  }

  @Test("Con un nome già occupato il file arriva come 'nome 2'")
  func nameConflict() async throws {
    let source = try writeImage(makeImage(), named: "foto.png")
    try "altro".write(to: directory.appendingPathComponent("foto.jpg"), atomically: true, encoding: .utf8)

    let result = await FileOperations.convert([source], to: .jpeg)

    #expect(result.done.map(\.lastPathComponent) == ["foto 2.jpg"])
    #expect(try String(contentsOf: directory.appendingPathComponent("foto.jpg"), encoding: .utf8) == "altro")
  }

  @Test("Il punto nel nome non fa perdere un pezzo di nome")
  func dotInName() async throws {
    let source = try writeImage(makeImage(), named: "schema v1.2.png")

    let result = await FileOperations.convert([source], to: .jpeg)

    #expect(result.done.map(\.lastPathComponent) == ["schema v1.2.jpg"])
  }

  // MARK: Esito

  @MainActor
  @Test("L'esito dice quante immagini ha convertito, e si annulla togliendo le nuove")
  func outcomeAndUndo() async throws {
    let one = try writeImage(makeImage(), named: "uno.png")
    let two = try writeImage(makeImage(), named: "due.png")

    let outcome = await ActionRunner.convert([one, two], to: .jpeg)

    #expect(outcome.message == "2 immagini convertite in JPEG")
    #expect(try names() == ["due.jpg", "due.png", "uno.jpg", "uno.png"])

    let undone = await ActionRunner.undo(try #require(outcome.undo))
    #expect(undone.message == "Annullato")
    #expect(try names() == ["due.png", "uno.png"])
  }

  @MainActor
  @Test("Con un'immagine sola il messaggio è al singolare")
  func singularMessage() async throws {
    let one = try writeImage(makeImage(), named: "uno.png")

    let outcome = await ActionRunner.convert([one], to: .jpeg)

    #expect(outcome.message == "1 immagine convertita in JPEG")
    // Il file nuovo è sul disco: lo si toglie per non lasciare tracce nel Cestino del test.
    if case .discard(let urls)? = outcome.undo {
      for url in urls { try? FileManager.default.removeItem(at: url) }
    }
  }

  @MainActor
  @Test("Se alcuni file sono saltati, l'esito lo dice")
  func skippedInMessage() async throws {
    let image = try writeImage(makeImage(), named: "foto.png")
    let text = directory.appendingPathComponent("nota.txt")
    try "ciao".write(to: text, atomically: true, encoding: .utf8)

    let outcome = await ActionRunner.convert([image, text], to: .jpeg)

    #expect(outcome.message == "1 immagine convertita in JPEG, 1 saltato")
  }

  @MainActor
  @Test("Se non c'è nessuna immagine lo dice, senza offrire di annullare")
  func nothingToConvert() async throws {
    let text = directory.appendingPathComponent("nota.txt")
    try "ciao".write(to: text, atomically: true, encoding: .utf8)

    let outcome = await ActionRunner.convert([text], to: .jpeg)

    #expect(outcome.message == "Il file non è un'immagine da convertire in JPEG")
    #expect(outcome.undo == nil)
  }

  @MainActor
  @Test("Le voci di Converti in sono i formati disponibili, con sigla e descrizione")
  func convertOptions() {
    let options = OrbisOption.convertOptions(formats: [.png, .jpeg])

    #expect(options.map(\.title) == ["PNG", "JPEG"])
    #expect(options.map(\.glyphText) == ["PNG", "JPEG"])
    #expect(options.allSatisfy { $0.subtitle?.isEmpty == false })
    #expect(options.map(\.format) == [.png, .jpeg])
    #expect(Set(options.map(\.id)).count == 2)
  }
}
