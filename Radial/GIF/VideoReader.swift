import AVFoundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Ciò che serve sapere di un video prima di trasformarlo.
nonisolated struct VideoInfo: Sendable, Equatable {
  /// In secondi.
  let duration: Double
  /// Le dimensioni com'è visto il video: con la rotazione già applicata (i video girati col
  /// telefono in verticale sono salvati in orizzontale, con l'indicazione di ruotarli).
  let size: PixelSize
  let frameRate: Double
}

nonisolated enum VideoError: Error {
  case noVideoTrack
  case cannotRead
}

nonisolated enum VideoReader {
  static func isVideo(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .movie) == true
  }

  static func info(of url: URL) async throws -> VideoInfo {
    let asset = AVURLAsset(url: url)
    let duration = try await asset.load(.duration)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoError.noVideoTrack }
    let (naturalSize, transform, frameRate) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
    let displayed = CGRect(origin: .zero, size: naturalSize).applying(transform)
    return VideoInfo(
      duration: duration.seconds,
      size: PixelSize(width: Int(abs(displayed.width).rounded()), height: Int(abs(displayed.height).rounded())),
      frameRate: Double(frameRate)
    )
  }

  /// Qualche fotogramma a intervalli regolari, per la striscia dell'intervallo.
  static func thumbnails(of url: URL, count: Int, maxSize: CGSize) async -> [CGImage] {
    let asset = AVURLAsset(url: url)
    guard let duration = try? await asset.load(.duration), duration.seconds > 0, count > 0 else { return [] }
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = maxSize
    // Per una miniatura va bene il fotogramma chiave più vicino: è molto più veloce.
    generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
    generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

    var images: [CGImage] = []
    for index in 0..<count {
      guard !Task.isCancelled else { break }
      let seconds = duration.seconds * (Double(index) + 0.5) / Double(count)
      if let image = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image {
        images.append(image)
      }
    }
    return images
  }

  /// Decodifica il video in ordine e consegna, per ogni istante di `times` (in ordine crescente),
  /// il fotogramma che in quel momento è a schermo: ruotato come va visto, ritagliato e portato
  /// alla misura di `geometry`.
  static func readFrames(
    of url: URL,
    at times: [Double],
    geometry: ResizeGeometry,
    body: (Int, RGBAFrame) throws -> Void
  ) async throws {
    guard let first = times.first, let last = times.last else { return }
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw VideoError.noVideoTrack }
    let transform = try await track.load(.preferredTransform)

    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw VideoError.cannotRead }
    reader.add(output)
    // Un po' prima dell'inizio: serve il fotogramma che a quell'istante è già a schermo.
    let from = CMTime(seconds: max(0, first - 1), preferredTimescale: 600)
    let to = CMTime(seconds: last + 1, preferredTimescale: 600)
    reader.timeRange = CMTimeRange(start: from, end: to)
    guard reader.startReading() else { throw reader.error ?? VideoError.cannotRead }
    defer { if reader.status == .reading { reader.cancelReading() } }

    let renderer = FrameRenderer(orientation: orientation(of: transform), geometry: geometry)
    var index = 0
    var previous: CVPixelBuffer?

    while index < times.count, let sample = output.copyNextSampleBuffer() {
      try Task.checkCancellation()
      guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
      let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
      // Gli istanti prima di questo fotogramma mostrano quello di prima.
      while index < times.count, time > times[index] + 1e-4 {
        try body(index, try renderer.render(previous ?? buffer))
        index += 1
      }
      previous = buffer
    }
    if reader.status == .failed { throw reader.error ?? VideoError.cannotRead }

    // Gli ultimi istanti mostrano l'ultimo fotogramma.
    while index < times.count, let previous {
      try Task.checkCancellation()
      try body(index, try renderer.render(previous))
      index += 1
    }
    guard index > 0 else { throw VideoError.cannotRead }
  }

  /// Come va girata l'immagine per vederla dritta, secondo la trasformazione della traccia.
  static func orientation(of transform: CGAffineTransform) -> CGImagePropertyOrientation {
    switch (transform.a.rounded(), transform.b.rounded(), transform.c.rounded(), transform.d.rounded()) {
    case (0, 1, -1, 0): .right
    case (0, -1, 1, 0): .left
    case (-1, 0, 0, -1): .down
    case (-1, 0, 0, 1): .upMirrored
    case (1, 0, 0, -1): .downMirrored
    case (0, 1, 1, 0): .leftMirrored
    case (0, -1, -1, 0): .rightMirrored
    default: .up
    }
  }
}

/// Ruota, ritaglia e ridimensiona un fotogramma con Core Image (sulla GPU), e lo scrive in RGBA sRGB.
nonisolated private struct FrameRenderer {
  let orientation: CGImagePropertyOrientation
  let geometry: ResizeGeometry
  private let context: CIContext
  private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

  init(orientation: CGImagePropertyOrientation, geometry: ResizeGeometry) {
    self.orientation = orientation
    self.geometry = geometry
    self.context = CIContext(options: [
      .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
      .cacheIntermediates: false,
    ])
  }

  func render(_ buffer: CVPixelBuffer) throws -> RGBAFrame {
    var image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
    image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))

    if let crop = geometry.crop {
      // Core Image ha l'origine in basso: il ritaglio, misurato dall'alto, si capovolge.
      let rect = CGRect(
        x: CGFloat(crop.x),
        y: image.extent.height - CGFloat(crop.y + crop.height),
        width: CGFloat(crop.width),
        height: CGFloat(crop.height)
      )
      image = image.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
    }

    let output = geometry.output
    let bounds = CGRect(x: 0, y: 0, width: output.width, height: output.height)
    let scale = CGAffineTransform(
      scaleX: CGFloat(output.width) / image.extent.width,
      y: CGFloat(output.height) / image.extent.height
    )
    // Esteso oltre i bordi prima di ridurre: altrimenti i pixel del bordo si mescolano col vuoto.
    image = image.clampedToExtent().transformed(by: scale, highQualityDownsample: true).cropped(to: bounds)

    var pixels = [UInt8](repeating: 0, count: output.width * output.height * 4)
    pixels.withUnsafeMutableBytes { bytes in
      context.render(
        image,
        toBitmap: bytes.baseAddress!,
        rowBytes: output.width * 4,
        bounds: bounds,
        format: .RGBA8,
        colorSpace: colorSpace
      )
    }
    return RGBAFrame(width: output.width, height: output.height, pixels: pixels)
  }
}
