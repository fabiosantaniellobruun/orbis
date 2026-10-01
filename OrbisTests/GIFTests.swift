import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Orbis

// MARK: - LZW

struct LZWTests {
  /// Un decodificatore scritto a parte, come quello di un browser: se legge ciò che scrive
  /// l'encoder, lunghezze dei codici e azzeramenti sono giusti.
  private func decode(_ bytes: [UInt8], minimumCodeSize: Int) -> (values: [UInt8], sawEnd: Bool) {
    let clear = 1 << minimumCodeSize
    let end = clear + 1
    let initial: [[UInt8]] = (0..<clear).map { [UInt8($0)] } + [[], []]
    var dictionary = initial
    var codeSize = minimumCodeSize + 1
    var previous: [UInt8]?
    var output: [UInt8] = []
    var position = 0

    while position + codeSize <= bytes.count * 8 {
      var code = 0
      for bit in 0..<codeSize {
        let index = position + bit
        code |= Int((bytes[index / 8] >> (index % 8)) & 1) << bit
      }
      position += codeSize

      if code == clear {
        dictionary = initial
        codeSize = minimumCodeSize + 1
        previous = nil
        continue
      }
      if code == end { return (output, true) }

      let entry: [UInt8]
      if code < dictionary.count {
        entry = dictionary[code]
      } else if let previous, code == dictionary.count {
        entry = previous + [previous[0]]
      } else {
        return (output, false)
      }
      output += entry
      if let previous, dictionary.count < 4096 {
        dictionary.append(previous + [entry[0]])
      }
      if dictionary.count == (1 << codeSize), codeSize < 12 {
        codeSize += 1
      }
      previous = entry
    }
    return (output, false)
  }

  private func values(count: Int, below limit: Int, seed: UInt32) -> [UInt8] {
    var state = seed
    return (0..<count).map { _ in
      state = state &* 1_664_525 &+ 1_013_904_223
      return UInt8(Int(state >> 16) % limit)
    }
  }

  @Test("Quello che si comprime si decomprime uguale", arguments: [2, 3, 4, 8])
  func roundTrip(minimumCodeSize: Int) {
    // Abbastanza lungo da riempire la tabella dei codici più volte.
    let input = values(count: 30_000, below: 1 << minimumCodeSize, seed: UInt32(minimumCodeSize))
    let decoded = decode(LZW.encode(input, minimumCodeSize: minimumCodeSize), minimumCodeSize: minimumCodeSize)
    #expect(decoded.sawEnd)
    #expect(decoded.values == input)
  }

  @Test("Anche con lunghe ripetizioni, e con lunghezze vicine ai cambi di codice")
  func repetitive() {
    for length in [1, 2, 3, 5, 6, 7, 8, 9, 13, 250, 251, 252, 253, 254, 4_000, 20_000] {
      let input = [UInt8](repeating: 1, count: length) + values(count: length / 3, below: 4, seed: 7)
      let decoded = decode(LZW.encode(input, minimumCodeSize: 2), minimumCodeSize: 2)
      #expect(decoded.sawEnd, "lunghezza \(length)")
      #expect(decoded.values == input, "lunghezza \(length)")
    }
  }
}

// MARK: - Palette, opzioni e scrittura

@MainActor
final class GIFWriterTests {
  private static let red: [UInt8] = [220, 30, 30, 255]
  private static let blue: [UInt8] = [30, 30, 220, 255]
  private static let green: [UInt8] = [30, 200, 60, 255]

  /// Metà sinistra rossa, metà destra blu, e un quadrato verde di 4 pixel in `square`.
  private func frame(width: Int = 20, height: Int = 10, square: (x: Int, y: Int)? = nil) -> RGBAFrame {
    var pixels: [UInt8] = []
    for y in 0..<height {
      for x in 0..<width {
        if let square, (square.x..<square.x + 4).contains(x), (square.y..<square.y + 4).contains(y) {
          pixels += Self.green
        } else {
          pixels += x < width / 2 ? Self.red : Self.blue
        }
      }
    }
    return RGBAFrame(width: width, height: height, pixels: pixels)
  }

  private func palette(for frames: [RGBAFrame], colors: Int = 256) -> [SIMD3<UInt8>] {
    var histogram = ColorHistogram()
    for frame in frames { histogram.add(frame) }
    return GIFPalette.make(from: histogram, count: colors)
  }

  private func pixel(_ image: CGImage, x: Int, y: Int) throws -> (r: Int, g: Int, b: Int) {
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = try #require(CGContext(
      data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
  }

  private func isClose(_ color: (r: Int, g: Int, b: Int), to expected: [UInt8]) -> Bool {
    abs(color.r - Int(expected[0])) < 30 && abs(color.g - Int(expected[1])) < 30 && abs(color.b - Int(expected[2])) < 30
  }

  @Test("Con pochi colori la palette è esattamente quelli")
  func exactPalette() {
    let colors = Set(palette(for: [frame(square: (2, 2))]).map { [$0.x, $0.y, $0.z] })
    #expect(colors == [[220, 30, 30], [30, 30, 220], [30, 200, 60]])
  }

  @Test("Con tanti colori la palette ne tiene al massimo quanti richiesti, sparsi su tutta la gamma")
  func reducedPalette() {
    var pixels: [UInt8] = []
    for y in 0..<64 {
      for x in 0..<64 {
        pixels += [UInt8(x * 4), UInt8(y * 4), UInt8((x + y) * 2), 255]
      }
    }
    let colors = palette(for: [RGBAFrame(width: 64, height: 64, pixels: pixels)], colors: 16)
    #expect(colors.count == 16)
    #expect(Set(colors.map { [$0.x, $0.y, $0.z] }).count == 16)
    #expect(colors.contains { $0.x < 64 } && colors.contains { $0.x > 192 })
  }

  @Test("Il GIF si rilegge: fotogrammi, tempi, colori e ripetizioni", arguments: GIFDithering.allCases)
  func writesReadableGIF(dithering: GIFDithering) throws {
    let frames = [frame(), frame(square: (3, 3)), frame(square: (3, 3)), frame(square: (12, 4))]
    let settings = GIFSettings(dithering: dithering, optimizes: true, repeats: 0)
    let writer = GIFWriter(width: 20, height: 10, palette: palette(for: frames), settings: settings)
    for frame in frames { writer.add(frame, delay: 10) }
    let data = writer.finish()

    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    // Il terzo è uguale al secondo: si fonde con lui, che resta a schermo il doppio.
    #expect(CGImageSourceGetCount(source) == 3)
    #expect(writer.frameCount == 3)
    let delays = (0..<3).map { index in
      let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
      let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
      return gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0
    }
    #expect(delays == [0.1, 0.2, 0.1])

    let file = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
    let loop = (file?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFLoopCount] as? Int
    #expect(loop == 0)

    // Ogni fotogramma, ricomposto, ha i colori giusti al posto giusto.
    let first = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(isClose(try pixel(first, x: 1, y: 1), to: Self.red))
    #expect(isClose(try pixel(first, x: 18, y: 8), to: Self.blue))
    let second = try #require(CGImageSourceCreateImageAtIndex(source, 1, nil))
    #expect(isClose(try pixel(second, x: 4, y: 4), to: Self.green))
    #expect(isClose(try pixel(second, x: 18, y: 8), to: Self.blue))
    let third = try #require(CGImageSourceCreateImageAtIndex(source, 2, nil))
    // Il quadrato si è spostato: dove era torna il rosso, dove arriva c'è il verde.
    #expect(isClose(try pixel(third, x: 4, y: 4), to: Self.red))
    #expect(isClose(try pixel(third, x: 13, y: 5), to: Self.green))
  }

  @Test("L'ottimizzazione scrive meno byte a parità di fotogrammi")
  func optimizationSavesBytes() {
    let frames = (0..<10).map { index in frame(width: 80, height: 40, square: (index * 4, 10)) }
    let colors = palette(for: frames)
    func size(optimizes: Bool) -> Int {
      let writer = GIFWriter(width: 80, height: 40, palette: colors, settings: GIFSettings(dithering: .none, optimizes: optimizes, repeats: 0))
      for frame in frames { writer.add(frame, delay: 5) }
      return writer.finish().count
    }
    #expect(size(optimizes: true) < size(optimizes: false))
  }

  @Test("Le ripetizioni: sempre, una volta sola, un numero di volte")
  func loopCount() throws {
    func loop(_ settings: GIFSettings) throws -> Int? {
      let writer = GIFWriter(width: 20, height: 10, palette: palette(for: [frame()]), settings: settings)
      writer.add(frame(), delay: 10)
      writer.add(frame(square: (1, 1)), delay: 10)
      let source = try #require(CGImageSourceCreateWithData(writer.finish() as CFData, nil))
      let file = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
      return (file?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFLoopCount] as? Int
    }
    // ImageIO conta le riproduzioni in tutto: le ripetizioni scritte nel file più la prima.
    #expect(try loop(GIFSettings(repeats: 0)) == 0)
    #expect(try loop(GIFSettings(repeats: 2)) == 3)
    // Senza l'estensione NETSCAPE il GIF si vede una volta sola.
    #expect(try loop(GIFSettings(repeats: nil)) == 1)
  }
}

struct GIFOptionsTests {
  @Test("I fotogrammi coprono l'intervallo, alla velocità scelta")
  func frameTimes() {
    var options = GIFOptions()
    options.start = 2
    options.end = 4
    options.fps = 10
    #expect(options.frameCount == 20)
    #expect(options.frameTimes().first == 2)
    #expect(abs((options.frameTimes().last ?? 0) - 3.9) < 1e-9)

    options.speed = 2
    #expect(options.outputDuration == 1)
    #expect(options.frameCount == 10)
    #expect(abs((options.frameTimes().last ?? 0) - 3.8) < 1e-9)
  }

  @Test("I tempi in centesimi si compensano: il totale è giusto", arguments: [5, 12, 15, 24, 30])
  func delays(fps: Int) {
    let delays = GIFOptions.delays(count: fps * 3, fps: fps)
    #expect(delays.reduce(0, +) == 300)
    #expect(delays.allSatisfy { $0 >= 3 })
  }

  @Test("Si parte dai primi dieci secondi")
  func initialRange() {
    #expect(GIFOptions(duration: 4).end == 4)
    #expect(GIFOptions(duration: 90).end == 10)
  }

  @Test("Ritaglio e misura: il GIF sta nella larghezza e non si ingrandisce")
  func geometry() {
    var options = GIFOptions()
    options.width = 480
    #expect(options.geometry(for: PixelSize(width: 1920, height: 1080)) == ResizeGeometry(output: PixelSize(width: 480, height: 270)))
    #expect(options.geometry(for: PixelSize(width: 320, height: 240)).output == PixelSize(width: 320, height: 240))

    options.ratio = AspectRatio(width: 1, height: 1)
    let square = options.geometry(for: PixelSize(width: 1920, height: 1080))
    #expect(square.crop == PixelRect(x: 420, y: 0, width: 1080, height: 1080))
    #expect(square.output == PixelSize(width: 480, height: 480))
  }

  @Test("Le opzioni che non hanno senso lo dicono")
  func problems() {
    var options = GIFOptions(duration: 5)
    #expect(options.problem == nil)
    options.end = options.start
    #expect(options.problem != nil)

    options = GIFOptions(duration: 5)
    options.width = 0
    #expect(options.problem != nil)

    options = GIFOptions(duration: 200)
    options.end = 200
    options.fps = 30
    #expect(options.problem != nil)
  }

  @Test("Le ripetizioni diventano il contatore del GIF")
  func repeats() {
    var options = GIFOptions()
    #expect(options.settings.repeats == 0)
    options.loop = .once
    #expect(options.settings.repeats == nil)
    options.loop = .times
    options.plays = 3
    #expect(options.settings.repeats == 2)
  }
}

// MARK: - Video

/// Video veri, scritti al volo: nel primo secondo quattro quadranti (rosso, verde, blu, bianco in
/// senso orario dall'alto a sinistra), nel secondo gli stessi colori al contrario.
@MainActor
final class VideoGIFTests {
  let directory: URL

  init() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("OrbisTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: directory)
  }

  private static let red: [UInt8] = [230, 20, 20]
  private static let green: [UInt8] = [20, 200, 40]
  private static let blue: [UInt8] = [20, 20, 230]
  private static let white: [UInt8] = [240, 240, 240]

  private func makeVideo(named name: String, rotated: Bool = false) async throws -> URL {
    let url = directory.appendingPathComponent(name)
    let width = 128, height = 96, fps = 30
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
    ])
    if rotated { input.transform = CGAffineTransform(rotationAngle: .pi / 2) }
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: width,
      kCVPixelBufferHeightKey as String: height,
    ])
    writer.add(input)
    try #require(writer.startWriting())
    writer.startSession(atSourceTime: .zero)

    for index in 0..<(fps * 2) {
      while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
      let pool = try #require(adaptor.pixelBufferPool)
      var buffer: CVPixelBuffer?
      CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
      let pixelBuffer = try #require(buffer)
      CVPixelBufferLockBaseAddress(pixelBuffer, [])
      let context = try #require(CGContext(
        data: CVPixelBufferGetBaseAddress(pixelBuffer), width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
      ))
      let colors = index < fps ? [Self.red, Self.green, Self.blue, Self.white] : [Self.white, Self.blue, Self.green, Self.red]
      // In alto a sinistra, in alto a destra, in basso a destra, in basso a sinistra (CG ha l'origine in basso).
      let rects = [
        CGRect(x: 0, y: height / 2, width: width / 2, height: height / 2),
        CGRect(x: width / 2, y: height / 2, width: width / 2, height: height / 2),
        CGRect(x: width / 2, y: 0, width: width / 2, height: height / 2),
        CGRect(x: 0, y: 0, width: width / 2, height: height / 2),
      ]
      for (color, rect) in zip(colors, rects) {
        context.setFillColor(CGColor(srgbRed: CGFloat(color[0]) / 255, green: CGFloat(color[1]) / 255, blue: CGFloat(color[2]) / 255, alpha: 1))
        context.fill(rect)
      }
      CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
      adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps)))
    }
    input.markAsFinished()
    await writer.finishWriting()
    try #require(writer.status == .completed, "\(String(describing: writer.error))")
    return url
  }

  private func color(_ frame: RGBAFrame, x: Int, y: Int) -> [Int] {
    let offset = (y * frame.width + x) * 4
    return [Int(frame.pixels[offset]), Int(frame.pixels[offset + 1]), Int(frame.pixels[offset + 2])]
  }

  /// Il colore di riferimento più vicino è quello atteso: la codifica H.264 sposta un po' i colori
  /// saturi (il verde esce più chiaro), ma non li confonde tra loro.
  private func isClose(_ color: [Int], to expected: [UInt8]) -> Bool {
    let references = [Self.red, Self.green, Self.blue, Self.white]
    let nearest = references.min { a, b in
      zip(color, a).reduce(0) { $0 + ($1.0 - Int($1.1)) * ($1.0 - Int($1.1)) }
        < zip(color, b).reduce(0) { $0 + ($1.0 - Int($1.1)) * ($1.0 - Int($1.1)) }
    }
    return nearest == expected
  }

  /// I quattro quadranti di un fotogramma, in senso orario dall'alto a sinistra.
  private func quadrants(_ frame: RGBAFrame) -> [[Int]] {
    let w = frame.width, h = frame.height
    return [
      color(frame, x: w / 4, y: h / 4),
      color(frame, x: 3 * w / 4, y: h / 4),
      color(frame, x: 3 * w / 4, y: 3 * h / 4),
      color(frame, x: w / 4, y: 3 * h / 4),
    ]
  }

  private func frames(of url: URL, at times: [Double], output: PixelSize, crop: PixelRect? = nil) async throws -> [RGBAFrame] {
    var result: [RGBAFrame] = []
    try await VideoReader.readFrames(of: url, at: times, geometry: ResizeGeometry(crop: crop, output: output)) { _, frame in
      result.append(frame)
    }
    return result
  }

  @Test("Un file video si riconosce e se ne leggono durata e misure")
  func info() async throws {
    let url = try await makeVideo(named: "prova.mov")

    #expect(VideoReader.isVideo(url))
    let info = try await VideoReader.info(of: url)
    #expect(abs(info.duration - 2) < 0.05)
    #expect(info.size == PixelSize(width: 128, height: 96))
  }

  @Test("I fotogrammi arrivano dritti, al momento giusto e alla misura chiesta")
  func readsFrames() async throws {
    let url = try await makeVideo(named: "prova.mov")

    let result = try await frames(of: url, at: [0.5, 1.5], output: PixelSize(width: 32, height: 24))

    #expect(result.count == 2)
    #expect(result[0].width == 32 && result[0].height == 24)
    let first = quadrants(result[0])
    #expect(isClose(first[0], to: Self.red), "\(first)")
    #expect(isClose(first[1], to: Self.green), "\(first)")
    #expect(isClose(first[2], to: Self.blue), "\(first)")
    #expect(isClose(first[3], to: Self.white), "\(first)")
    let second = quadrants(result[1])
    #expect(isClose(second[0], to: Self.white), "\(second)")
    #expect(isClose(second[2], to: Self.green), "\(second)")
  }

  @Test("Un video girato in verticale si legge ruotato come va visto")
  func rotatedVideo() async throws {
    let url = try await makeVideo(named: "verticale.mov", rotated: true)

    let info = try await VideoReader.info(of: url)
    #expect(info.size == PixelSize(width: 96, height: 128))

    let result = try await frames(of: url, at: [0.5], output: PixelSize(width: 24, height: 32))
    // Un quarto di giro in senso orario: il rosso (in alto a sinistra) va in alto a destra.
    let colors = quadrants(try #require(result.first))
    #expect(isClose(colors[0], to: Self.white), "\(colors)")
    #expect(isClose(colors[1], to: Self.red), "\(colors)")
    #expect(isClose(colors[2], to: Self.green), "\(colors)")
    #expect(isClose(colors[3], to: Self.blue), "\(colors)")
  }

  @Test("Il ritaglio prende la parte giusta del fotogramma")
  func cropsFrames() async throws {
    let url = try await makeVideo(named: "prova.mov")

    // La metà destra: verde sopra, blu sotto.
    let result = try await frames(of: url, at: [0.5], output: PixelSize(width: 16, height: 24), crop: PixelRect(x: 64, y: 0, width: 64, height: 96))

    let frame = try #require(result.first)
    #expect(isClose(color(frame, x: 8, y: 4), to: Self.green))
    #expect(isClose(color(frame, x: 8, y: 20), to: Self.blue))
  }

  @Test("Dal video al GIF: si rilegge, con i fotogrammi fusi dove il video è fermo")
  func makesGIF() async throws {
    let url = try await makeVideo(named: "prova.mov")
    let info = try await VideoReader.info(of: url)
    var options = GIFOptions(duration: info.duration)
    options.width = 64
    options.fps = 10

    let output = try await GIFMaker.make(url, info: info, options: options)

    #expect(output.reachedTarget)
    #expect(output.size == PixelSize(width: 64, height: 48))
    let source = try #require(CGImageSourceCreateWithData(output.data as CFData, nil))
    // Due secondi, due immagini ferme: bastano due fotogrammi.
    #expect(CGImageSourceGetCount(source) == 2)
    #expect(output.frameCount == 2)
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    #expect(properties?[kCGImagePropertyPixelWidth] as? Int == 64)
  }

  @Test("Con un peso massimo il GIF si rimpicciolisce finché ci sta")
  func reachesWeight() async throws {
    let url = try await makeVideo(named: "prova.mov")
    let info = try await VideoReader.info(of: url)
    var options = GIFOptions(duration: info.duration)
    options.width = nil
    options.dithering = .diffusion
    let full = try await GIFMaker.make(url, info: info, options: options)
    options.limitsWeight = true
    options.weightUnit = .kilobytes
    options.weight = max(1, full.data.count / 2 / 1_000)

    let limited = try await GIFMaker.make(url, info: info, options: options)

    #expect(limited.data.count <= options.maxBytes ?? 0)
    #expect(limited.size.width < full.size.width)
  }

  @Test("Il GIF arriva accanto al video, con il messaggio e l'annullamento giusti")
  func actionOutcome() async throws {
    let url = try await makeVideo(named: "clip.mov")
    let info = try await VideoReader.info(of: url)
    var options = GIFOptions(duration: info.duration)
    options.width = 64
    let request = GIFRequest(jobs: [GIFJob(url: url, info: info, options: options)], skipped: 1)

    let outcome = await ActionRunner.makeGIFs(request)

    #expect(outcome.message.hasPrefix("clip.gif creato, "))
    #expect(outcome.message.hasSuffix(", 1 saltato"))
    guard case .discard(let created) = outcome.undo else {
      Issue.record("Il GIF deve potersi annullare togliendolo")
      return
    }
    #expect(created.map(\.lastPathComponent) == ["clip.gif"])
    #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))

    // La seconda volta non sovrascrive.
    let again = await FileOperations.makeGIFs(request)
    #expect(again.done.first?.url.lastPathComponent == "clip 2.gif")
  }

  @Test("Nel secondo anello di Converti in, il GIF compare per i video e i formati per il resto")
  func convertOptions() async throws {
    let video = try await makeVideo(named: "clip.mov")
    let image = directory.appendingPathComponent("foto.png")
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: image)

    let formats: [ImageFormat] = [.png, .jpeg]
    #expect(OrbisOption.convertOptions(for: [video], formats: formats).map(\.id) == ["gif"])
    #expect(OrbisOption.convertOptions(for: [image], formats: formats).map(\.id) == ["format:png", "format:jpeg"])
    #expect(OrbisOption.convertOptions(for: [video, image], formats: formats).map(\.id) == ["gif", "format:png", "format:jpeg"])
    #expect(OrbisOption.convertOptions(for: [], formats: formats).count == 3)
  }

  @Test("Con più video ognuno va per intero, fino al massimo di fotogrammi")
  func multipleVideos() async throws {
    let first = try await makeVideo(named: "uno.mov")
    let second = try await makeVideo(named: "due.mov")
    let model = GIFModel(videos: [first, second], skipped: 0)
    model.load()
    for _ in 0..<200 where model.infos.count < 2 {
      try await Task.sleep(for: .milliseconds(20))
    }
    model.options.start = 0.5
    model.options.end = 1

    let jobs = model.request.jobs
    #expect(jobs.count == 2)
    #expect(jobs.allSatisfy { $0.options.start == 0 && abs($0.options.end - 2) < 0.05 })
    model.stop()
  }

  @Test("Il campione stima il peso dell'intero GIF")
  func sampleEstimate() async throws {
    let url = try await makeVideo(named: "prova.mov")
    let info = try await VideoReader.info(of: url)
    var options = GIFOptions(duration: info.duration)
    options.width = 64

    let sample = try await GIFMaker.sample(url, info: info, options: options)

    #expect(CGImageSourceCreateWithData(sample.data as CFData, nil).map(CGImageSourceGetCount) ?? 0 >= 1)
    #expect(sample.estimatedBytes > 0)
  }
}
