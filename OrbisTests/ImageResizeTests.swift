import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Orbis

/// Ogni test lavora in una cartella temporanea sua, rimossa alla fine.
@MainActor
final class ImageResizeTests {
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

  private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

  /// Metà sinistra rossa e metà destra blu, oppure un quadrato rosso nell'angolo in basso a
  /// sinistra su fondo trasparente.
  private func makeImage(width: Int, height: Int, transparent: Bool = false) throws -> CGImage {
    let info = transparent ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
    let context = try #require(CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: Self.sRGB, bitmapInfo: info.rawValue
    ))
    context.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1))
    if transparent {
      context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
    } else {
      context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
      context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.9, alpha: 1))
      context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
    }
    return try #require(context.makeImage())
  }

  /// Pixel a caso (ma sempre gli stessi): comprimono male, e il peso dipende davvero dalla qualità.
  private func makeNoise(width: Int, height: Int) throws -> CGImage {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    var seed: UInt32 = 12345
    for index in bytes.indices {
      seed = seed &* 1_664_525 &+ 1_013_904_223
      bytes[index] = index % 4 == 3 ? 255 : UInt8(truncatingIfNeeded: seed >> 24)
    }
    let context = try #require(CGContext(
      data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
      space: Self.sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ))
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

  private func properties(of url: URL) throws -> [CFString: Any] {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
  }

  private func size(of url: URL) throws -> PixelSize {
    let properties = try properties(of: url)
    return PixelSize(
      width: properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
      height: properties[kCGImagePropertyPixelHeight] as? Int ?? 0
    )
  }

  /// Il colore di un pixel (0, 0 è l'angolo in alto a sinistra), senza applicare l'orientamento.
  private func pixel(of url: URL, x: Int, y: Int) throws -> (r: Int, g: Int, b: Int) {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = try #require(CGContext(
      data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: Self.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
  }

  private func isRed(_ color: (r: Int, g: Int, b: Int)) -> Bool { color.r > 180 && color.b < 90 }
  private func isBlue(_ color: (r: Int, g: Int, b: Int)) -> Bool { color.b > 180 && color.r < 90 }

  private func names() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
  }

  private func request(_ urls: [URL], _ configure: (inout ResizeOptions) -> Void = { _ in }) -> ResizeRequest {
    var options = ResizeOptions()
    configure(&options)
    return ResizePlan.make(sources: urls.map { ResizeSource(url: $0) }, options: options).request
  }

  // MARK: Lettura

  @Test("Le dimensioni lette tengono conto dell'orientamento")
  func infoAppliesOrientation() throws {
    let url = try writeImage(makeImage(width: 40, height: 20), named: "foto.jpg", as: .jpeg, properties: [kCGImagePropertyOrientation: 6])

    let info = try #require(ImageInfo.read(url))

    #expect(info.size == PixelSize(width: 20, height: 40))
    #expect(info.type == UTType.jpeg.identifier)
    #expect(info.frameCount == 1)
    #expect((info.byteCount ?? 0) > 0)
  }

  @Test("Un file che non è un'immagine non ha informazioni")
  func infoOfNonImage() throws {
    let url = directory.appendingPathComponent("note.txt")
    try "ciao".write(to: url, atomically: true, encoding: .utf8)
    #expect(ImageInfo.read(url) == nil)
  }

  // MARK: Ridimensionamento

  @Test("Una PNG ridotta in larghezza: nuovo file accanto, stesso formato, proporzioni mantenute")
  func resizesByWidth() async throws {
    let source = try writeImage(makeImage(width: 400, height: 300), named: "foto.png")

    let result = await FileOperations.resize(request([source]) { $0.width = 100 })

    #expect(result.failed == 0)
    let created = try #require(result.done.first)
    #expect(created.url.lastPathComponent == "foto ridimensionata.png")
    #expect(created.reachedTarget)
    #expect(try size(of: created.url) == PixelSize(width: 100, height: 75))
    #expect(ImageInfo.read(created.url)?.type == UTType.png.identifier)
    // I colori restano al loro posto.
    #expect(isRed(try pixel(of: created.url, x: 10, y: 30)))
    #expect(isBlue(try pixel(of: created.url, x: 90, y: 30)))
    #expect(try names() == ["foto ridimensionata.png", "foto.png"])
  }

  @Test("Una foto ruotata esce dritta, senza orientamento da riapplicare")
  func orientationIsApplied() async throws {
    // Orientamento 6: da vedere ruotata di un quarto di giro in senso orario.
    let source = try writeImage(makeImage(width: 40, height: 20), named: "foto.jpg", as: .jpeg, properties: [kCGImagePropertyOrientation: 6])

    let result = await FileOperations.resize(request([source]) { $0.mode = .percent; $0.percent = 50 })

    let created = try #require(result.done.first).url
    #expect(try size(of: created) == PixelSize(width: 10, height: 20))
    let orientation = try properties(of: created)[kCGImagePropertyOrientation] as? Int
    #expect(orientation == nil || orientation == 1)
    // La metà rossa (a sinistra) finisce in alto.
    #expect(isRed(try pixel(of: created, x: 5, y: 3)))
    #expect(isBlue(try pixel(of: created, x: 5, y: 17)))
  }

  @Test("Il ritaglio al quadrato tiene il centro")
  func cropsToSquare() async throws {
    let source = try writeImage(makeImage(width: 400, height: 200), named: "banner.png")

    let result = await FileOperations.resize(request([source]) {
      $0.mode = .ratio
      $0.ratio = AspectRatio(width: 1, height: 1)
    })

    let created = try #require(result.done.first).url
    #expect(try size(of: created) == PixelSize(width: 200, height: 200))
    // Del centro, metà è rossa e metà blu.
    #expect(isRed(try pixel(of: created, x: 20, y: 100)))
    #expect(isBlue(try pixel(of: created, x: 180, y: 100)))
  }

  @Test("Stirata alla misura esatta")
  func stretches() async throws {
    let source = try writeImage(makeImage(width: 400, height: 200), named: "banner.png")

    let result = await FileOperations.resize(request([source]) {
      $0.keepsProportions = false
      $0.width = 100
      $0.height = 100
    })

    #expect(try size(of: try #require(result.done.first).url) == PixelSize(width: 100, height: 100))
  }

  @Test("Ingrandita, se richiesto")
  func enlarges() async throws {
    let source = try writeImage(makeImage(width: 40, height: 20), named: "icona.png")

    let result = await FileOperations.resize(request([source]) { $0.mode = .percent; $0.percent = 200 })

    #expect(try size(of: try #require(result.done.first).url) == PixelSize(width: 80, height: 40))
  }

  @Test("Cambiando formato cambia anche l'estensione, e la trasparenza in JPEG va su bianco")
  func changesFormat() async throws {
    let source = try writeImage(makeImage(width: 40, height: 40, transparent: true), named: "logo.png")

    let result = await FileOperations.resize(request([source]) { $0.format = .jpeg })

    let created = try #require(result.done.first).url
    #expect(created.lastPathComponent == "logo ridimensionata.jpg")
    #expect(ImageInfo.read(created)?.type == UTType.jpeg.identifier)
    let corner = try pixel(of: created, x: 35, y: 5)
    #expect(corner.r > 235 && corner.g > 235 && corner.b > 235, "era \(corner)")
  }

  @Test("Se il formato non cambia, l'estensione resta quella dell'originale")
  func keepsOriginalExtension() async throws {
    let source = try writeImage(makeImage(width: 40, height: 30), named: "Scatto.JPEG", as: .jpeg)

    let result = await FileOperations.resize(request([source]) { $0.width = 20 })

    #expect(try #require(result.done.first).url.lastPathComponent == "Scatto ridimensionata.JPEG")
  }

  @Test("Non sovrascrive: la seconda volta arriva un file nuovo")
  func neverOverwrites() async throws {
    let source = try writeImage(makeImage(width: 40, height: 30), named: "foto.png")

    _ = await FileOperations.resize(request([source]) { $0.width = 20 })
    let second = await FileOperations.resize(request([source]) { $0.width = 10 })

    #expect(try #require(second.done.first).url.lastPathComponent == "foto ridimensionata 2.png")
    #expect(try size(of: directory.appendingPathComponent("foto ridimensionata.png")).width == 20)
  }

  @Test("I metadati restano, tranne le misure vecchie")
  func keepsMetadata() async throws {
    let exif: [CFString: Any] = [
      kCGImagePropertyExifDateTimeOriginal: "2024:05:01 10:20:30",
      kCGImagePropertyExifPixelXDimension: 400,
      kCGImagePropertyExifPixelYDimension: 300,
    ]
    let source = try writeImage(makeImage(width: 400, height: 300), named: "foto.jpg", as: .jpeg, properties: [kCGImagePropertyExifDictionary: exif])

    let result = await FileOperations.resize(request([source]) { $0.width = 100 })

    let created = try #require(result.done.first).url
    let written = try #require(try properties(of: created)[kCGImagePropertyExifDictionary] as? [CFString: Any])
    #expect(written[kCGImagePropertyExifDateTimeOriginal] as? String == "2024:05:01 10:20:30")
    #expect(written[kCGImagePropertyExifPixelXDimension] as? Int != 400)
  }

  // MARK: Qualità e peso

  @Test("Una qualità più bassa pesa meno")
  func qualityChangesWeight() throws {
    let source = try writeImage(makeNoise(width: 300, height: 200), named: "rumore.png")
    let geometry = ResizeGeometry(output: PixelSize(width: 300, height: 200))

    let high = try ImageResizer.render(source, geometry: geometry, format: .jpeg, quality: 0.95)
    let low = try ImageResizer.render(source, geometry: geometry, format: .jpeg, quality: 0.3)

    #expect(low.data.count < high.data.count)
    #expect(high.quality == 0.95)
  }

  @Test("Con un peso massimo si trova una qualità che lo rispetta")
  func reachesTargetWeight() throws {
    let source = try writeImage(makeNoise(width: 300, height: 200), named: "rumore.png")
    let geometry = ResizeGeometry(output: PixelSize(width: 300, height: 200))
    let full = try ImageResizer.render(source, geometry: geometry, format: .jpeg, quality: 0.95).data.count
    let target = full / 2

    let rendered = try ImageResizer.render(source, geometry: geometry, format: .jpeg, quality: 0.95, maxBytes: target)

    #expect(rendered.reachedTarget)
    #expect(rendered.data.count <= target)
    #expect((rendered.quality ?? 1) < 0.95)
  }

  @Test("Se il peso non si raggiunge, si dice")
  func unreachableTargetWeight() async throws {
    let source = try writeImage(makeNoise(width: 300, height: 200), named: "rumore.png")

    let result = await FileOperations.resize(request([source]) {
      $0.format = .jpeg
      $0.limitsWeight = true
      $0.weight = 1
    })

    let created = try #require(result.done.first)
    #expect(!created.reachedTarget)

    let outcome = await ActionRunner.resize(request([source]) {
      $0.format = .jpeg
      $0.limitsWeight = true
      $0.weight = 1
    })
    #expect(outcome.message == "1 immagine ridimensionata, 1 resta sopra il peso richiesto")
  }

  // MARK: Piano

  @Test("Si saltano i file che non sono immagini e quelle animate")
  func skipsNonImagesAndAnimations() throws {
    let text = directory.appendingPathComponent("note.txt")
    try "ciao".write(to: text, atomically: true, encoding: .utf8)
    let gif = directory.appendingPathComponent("animata.gif")
    let destination = try #require(CGImageDestinationCreateWithURL(gif as CFURL, UTType.gif.identifier as CFString, 2, nil))
    CGImageDestinationAddImage(destination, try makeImage(width: 20, height: 10), nil)
    CGImageDestinationAddImage(destination, try makeImage(width: 20, height: 10), nil)
    try #require(CGImageDestinationFinalize(destination))
    let photo = try writeImage(makeImage(width: 40, height: 30), named: "foto.png")

    var options = ResizeOptions()
    options.width = 20
    let plan = ResizePlan.make(sources: [text, gif, photo].map { ResizeSource(url: $0) }, options: options)

    #expect(plan.rows.map(\.status) == [
      .skipped(.notAnImage),
      .skipped(.animated),
      .ready(ResizeJob(url: photo, geometry: ResizeGeometry(output: PixelSize(width: 20, height: 15)), format: .png, fileExtension: "png")),
    ])
    #expect(plan.canApply)
    #expect(plan.request.skipped == 2)
  }

  @Test("Una PNG alle stesse misure e nello stesso formato non si riscrive; una JPEG si ricomprime")
  func unchangedLosslessIsSkipped() throws {
    let png = try writeImage(makeImage(width: 40, height: 30), named: "foto.png")
    let jpeg = try writeImage(makeImage(width: 40, height: 30), named: "foto.jpg", as: .jpeg)

    let plan = ResizePlan.make(sources: [png, jpeg].map { ResizeSource(url: $0) }, options: ResizeOptions())

    #expect(plan.rows.first?.status == .skipped(.unchanged))
    #expect(plan.jobs.map(\.url) == [jpeg])

    // Cambiando formato, invece, c'è qualcosa da fare.
    var converting = ResizeOptions()
    converting.format = .heic
    #expect(ResizePlan.make(sources: [ResizeSource(url: png)], options: converting).jobs.count == 1)
  }

  @Test("Un formato che il Mac non sa scrivere va cambiato")
  func unwritableFormat() throws {
    let photo = try writeImage(makeImage(width: 40, height: 30), named: "foto.png")
    let sources = [ResizeSource(url: photo)]

    let keeping = ResizePlan.make(sources: sources, options: ResizeOptions(), writable: [.jpeg])
    #expect(keeping.rows.first?.status == .skipped(.unwritableFormat))
    #expect(!keeping.canApply)

    var converting = ResizeOptions()
    converting.format = .jpeg
    let converted = ResizePlan.make(sources: sources, options: converting, writable: [.jpeg])
    #expect(converted.jobs.first?.format == .jpeg)
    #expect(converted.jobs.first?.fileExtension == "jpg")
  }

  @Test("Con opzioni sbagliate non si applica")
  func invalidOptionsBlockApply() throws {
    let photo = try writeImage(makeImage(width: 40, height: 30), named: "foto.png")
    var options = ResizeOptions()
    options.width = 0

    #expect(!ResizePlan.make(sources: [ResizeSource(url: photo)], options: options).canApply)
  }

  // MARK: Esito e annullamento

  @Test("L'esito dice quante immagini e quante saltate, e l'annullamento sa quali file togliere")
  func outcomeAndUndo() async throws {
    let photos = try [writeImage(makeImage(width: 40, height: 30), named: "a.png"), writeImage(makeImage(width: 40, height: 30), named: "b.png")]
    let text = directory.appendingPathComponent("note.txt")
    try "ciao".write(to: text, atomically: true, encoding: .utf8)

    let outcome = await ActionRunner.resize(request(photos + [text]) { $0.width = 20 })

    #expect(outcome.message == "2 immagini ridimensionate, 1 saltato")
    guard case .discard(let created) = outcome.undo else {
      Issue.record("Ridimensiona deve potersi annullare togliendo i file nuovi")
      return
    }
    #expect(created.map(\.lastPathComponent).sorted() == ["a ridimensionata.png", "b ridimensionata.png"])
  }
}
