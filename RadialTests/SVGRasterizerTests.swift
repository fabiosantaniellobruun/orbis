import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Radial

/// Ogni test lavora in una cartella temporanea sua, rimossa alla fine.
@MainActor
final class SVGRasterizerTests {
  let directory: URL

  init() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("RadialTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: directory)
  }

  /// 40×30 punti: metà sinistra rossa, in alto a destra blu, trasparente in basso a destra.
  private static let twoColors = """
    <svg xmlns="http://www.w3.org/2000/svg" width="40" height="30" viewBox="0 0 40 30">
      <rect width="20" height="30" fill="#e53935"/>
      <rect x="20" width="20" height="20" fill="#1e88e5"/>
    </svg>
    """

  private func write(_ text: String, named name: String) throws -> URL {
    let url = directory.appendingPathComponent(name)
    try text.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  private func properties(of url: URL) throws -> [CFString: Any] {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
  }

  private func size(of url: URL) throws -> (width: Int, height: Int) {
    let properties = try properties(of: url)
    return (properties[kCGImagePropertyPixelWidth] as? Int ?? 0, properties[kCGImagePropertyPixelHeight] as? Int ?? 0)
  }

  /// Colore e opacità di un pixel (0, 0 è l'angolo in alto a sinistra).
  private func pixel(of url: URL, x: Int, y: Int) throws -> (r: Int, g: Int, b: Int, a: Int) {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = try #require(CGContext(
      data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]), Int(bytes[3]))
  }

  private func names() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)).sorted()
  }

  // MARK: Riconoscimento e misura

  @Test("Un SVG si riconosce, e la sua misura è quella dichiarata, o quella del viewBox")
  func recognizesSVG() throws {
    let declared = try write(Self.twoColors, named: "logo.svg")
    let viewBoxOnly = try write(##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 32"><rect width="64" height="32" fill="#43a047"/></svg>"##, named: "badge.svg")
    let text = try write("ciao", named: "note.txt")

    #expect(SVGRasterizer.isSVG(declared))
    #expect(!SVGRasterizer.isSVG(text))
    #expect(SVGRasterizer.size(of: declared) == CGSize(width: 40, height: 30))
    #expect(SVGRasterizer.size(of: viewBoxOnly) == CGSize(width: 64, height: 32))
  }

  @Test("I nomi seguono la convenzione di Apple")
  func scaleNames() {
    #expect(SVGRasterizer.stem("logo", scale: 1) == "logo")
    #expect(SVGRasterizer.stem("logo", scale: 2) == "logo@2x")
    #expect(SVGRasterizer.stem("logo", scale: 4) == "logo@4x")
  }

  // MARK: Esportazione

  @Test("Ogni scala ha i pixel giusti, nitidi e con la trasparenza", arguments: [1, 2, 3, 4])
  func rasterizes(scale: Int) async throws {
    let svg = try write(Self.twoColors, named: "logo.svg")

    let result = await FileOperations.rasterizeSVGs([svg], scales: [scale])

    #expect(result.failed == 0)
    let png = try #require(result.done.first)
    #expect(png.lastPathComponent == (scale == 1 ? "logo.png" : "logo@\(scale)x.png"))
    let dimensions = try size(of: png)
    #expect(dimensions.width == 40 * scale && dimensions.height == 30 * scale)

    let red = try pixel(of: png, x: 2 * scale, y: 15 * scale)
    #expect(red.r > 200 && red.b < 80 && red.a == 255, "era \(red)")
    let blue = try pixel(of: png, x: 38 * scale, y: 2 * scale)
    #expect(blue.b > 200 && blue.r < 60, "era \(blue)")
    // In basso a destra l'SVG non disegna nulla.
    #expect(try pixel(of: png, x: 38 * scale, y: 28 * scale).a == 0)
    // Il bordo tra i due colori resta netto anche ingrandito.
    #expect(try pixel(of: png, x: 20 * scale - 1, y: 5 * scale).r > 200)
    #expect(try pixel(of: png, x: 20 * scale, y: 5 * scale).b > 200)

    #expect(try properties(of: png)[kCGImagePropertyDPIWidth] as? Int == 72 * scale)
  }

  @Test("Tutte e quattro le scale insieme, accanto all'originale")
  func allScales() async throws {
    let svg = try write(Self.twoColors, named: "Icona app.svg")

    let result = await FileOperations.rasterizeSVGs([svg], scales: SVGRasterizer.scales)

    #expect(result.done.count == 4)
    #expect(try names() == ["Icona app.png", "Icona app.svg", "Icona app@2x.png", "Icona app@3x.png", "Icona app@4x.png"])
  }

  @Test("Non sovrascrive: la seconda volta arriva un file nuovo")
  func neverOverwrites() async throws {
    let svg = try write(Self.twoColors, named: "logo.svg")

    _ = await FileOperations.rasterizeSVGs([svg], scales: [2])
    let second = await FileOperations.rasterizeSVGs([svg], scales: [2])

    #expect(second.done.first?.lastPathComponent == "logo@2x 2.png")
  }

  @Test("Chi non è un SVG si salta; un SVG rotto non riesce")
  func skipsAndFails() async throws {
    let text = try write("ciao", named: "note.txt")
    let broken = try write("<svg nope", named: "rotto.svg")

    let result = await FileOperations.rasterizeSVGs([text, broken], scales: [1])

    #expect(result.done.isEmpty)
    #expect(result.skipped == 1)
    #expect(result.failed == 1)
  }

  // MARK: Esito e menu

  @Test("I messaggi dicono cosa è stato creato, e l'annullamento sa cosa togliere")
  func outcome() async throws {
    let svg = try write(Self.twoColors, named: "logo.svg")
    let text = try write("ciao", named: "note.txt")

    let single = await ActionRunner.rasterizeSVGs([svg], scales: [2])
    #expect(single.message == "logo@2x.png creato")

    let all = await ActionRunner.rasterizeSVGs([svg, text], scales: SVGRasterizer.scales)
    #expect(all.message == "4 PNG creati (1x–4x), 1 saltato")
    guard case .discard(let created) = all.undo else {
      Issue.record("La conversione deve potersi annullare togliendo i PNG")
      return
    }
    #expect(created.count == 4)

    let nothing = await ActionRunner.rasterizeSVGs([text], scales: [1])
    #expect(nothing.message == "Il file non è un SVG")
    #expect(nothing.undo == nil)
  }

  @Test("Nel secondo anello gli SVG hanno le scale PNG, e non i formati che non saprebbero leggere")
  func convertOptions() throws {
    let svg = try write(Self.twoColors, named: "logo.svg")
    let image = directory.appendingPathComponent("foto.png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: image)
    let formats: [ImageFormat] = [.png, .jpeg]
    let scales = ["svg:1", "svg:2", "svg:3", "svg:4", "svg:all"]

    #expect(RadialOption.convertOptions(for: [svg], formats: formats).map(\.id) == scales)
    #expect(RadialOption.convertOptions(for: [svg, image], formats: formats).map(\.id) == scales + ["format:png", "format:jpeg"])
    // Il menu di prova resta com'era.
    #expect(!RadialOption.convertOptions(for: [], formats: formats).contains { $0.id.hasPrefix("svg:") })
    #expect(RadialOption.svgOptions.last?.svgScales == [1, 2, 3, 4])
  }
}
