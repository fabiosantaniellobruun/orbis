import CoreGraphics
import Foundation
import ImageIO

/// Ciò che serve sapere di un'immagine prima di toccarla, letto senza decodificarla.
nonisolated struct ImageInfo: Sendable, Equatable {
  /// L'identificatore di tipo (`public.jpeg`…).
  let type: String
  /// Le dimensioni com'è vista l'immagine: con l'orientamento EXIF già applicato.
  let size: PixelSize
  let hasAlpha: Bool
  /// Più di uno per GIF animate, sequenze HEIC, TIFF a più pagine.
  let frameCount: Int
  let byteCount: Int?

  static func read(_ url: URL) -> ImageInfo? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          CGImageSourceGetCount(source) > 0,
          let type = CGImageSourceGetType(source) as String?,
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int
    else { return nil }

    // Le orientazioni da 5 a 8 sono ruotate di un quarto di giro: larghezza e altezza si scambiano.
    let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
    let size = (5...8).contains(orientation) ? PixelSize(width: height, height: width) : PixelSize(width: width, height: height)
    let bytes = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize

    return ImageInfo(
      type: type,
      size: size,
      hasAlpha: properties[kCGImagePropertyHasAlpha] as? Bool ?? false,
      frameCount: CGImageSourceGetCount(source),
      byteCount: bytes
    )
  }
}

nonisolated struct RenderedImage: Sendable {
  let data: Data
  /// La qualità con cui è stato scritto, per i formati che ne hanno una.
  let quality: Double?
  /// `false` se è stato chiesto un peso massimo e nemmeno la qualità più bassa l'ha raggiunto.
  let reachedTarget: Bool
}

nonisolated enum ImageResizeError: Error {
  case unreadable
  case cannotEncode
}

nonisolated enum ImageResizer {
  /// Sotto questa qualità un JPEG o un HEIC è inguardabile: meglio fermarsi e dirlo.
  static let lowestQuality = 0.1

  /// L'immagine ritagliata, ridimensionata e scritta nel formato richiesto, in memoria. Di un
  /// file a più immagini si prende la prima. Conserva i metadati (data di scatto, posizione,
  /// profilo colore) tranne l'orientamento, che è già applicato ai pixel.
  ///
  /// - Parameters:
  ///   - quality: per i formati con perdita (JPEG, HEIC, AVIF); gli altri la ignorano.
  ///   - maxBytes: un peso da non superare; si cerca la qualità più alta che lo rispetta.
  static func render(
    _ url: URL,
    geometry: ResizeGeometry,
    format: ImageFormat,
    quality: Double,
    maxBytes: Int? = nil
  ) throws -> RenderedImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          CGImageSourceGetCount(source) > 0,
          let info = ImageInfo.read(url)
    else { throw ImageResizeError.unreadable }

    var image = try scaledImage(from: source, info: info, geometry: geometry)
    if !format.supportsTransparency, image.hasAlpha {
      // JPEG non ha trasparenza: il fondo trasparente diventerebbe nero. Si appoggia su bianco.
      image = ImageConverter.flattenedOnWhite(image)
    }

    let properties = metadata(of: source)

    guard format.defaultQuality != nil else {
      return RenderedImage(data: try encode(image, as: format, quality: nil, properties: properties), quality: nil, reachedTarget: true)
    }

    let best = min(max(quality, lowestQuality), 1)
    let first = try encode(image, as: format, quality: best, properties: properties)
    guard let maxBytes, first.count > maxBytes else {
      return RenderedImage(data: first, quality: best, reachedTarget: true)
    }

    // Troppo pesante: si cerca la qualità più alta che sta sotto il limite.
    let floor = try encode(image, as: format, quality: lowestQuality, properties: properties)
    guard floor.count <= maxBytes else {
      return RenderedImage(data: floor, quality: lowestQuality, reachedTarget: false)
    }

    var low = lowestQuality
    var high = best
    var fitting = (data: floor, quality: lowestQuality)
    // AVIF è lento da scrivere: meno tentativi, e comunque basta la precisione di un punto.
    for _ in 0..<(format == .avif ? 4 : 7) where high - low > 0.01 && !Task.isCancelled {
      let middle = (low + high) / 2
      let candidate = try encode(image, as: format, quality: middle, properties: properties)
      if candidate.count <= maxBytes {
        fitting = (candidate, middle)
        low = middle
      } else {
        high = middle
      }
    }
    return RenderedImage(data: fitting.data, quality: fitting.quality, reachedTarget: true)
  }

  // MARK: Pixel

  /// L'immagine con l'orientamento applicato, ritagliata e portata alla misura finale.
  private static func scaledImage(from source: CGImageSource, info: ImageInfo, geometry: ResizeGeometry) throws -> CGImage {
    let output = geometry.output
    let isProportional = geometry.crop == nil && output.width <= info.size.width && output.height <= info.size.height
      && abs(Double(output.width) / Double(output.height) - Double(info.size.width) / Double(info.size.height)) < 0.02

    if isProportional {
      // Il sistema sa ridurre bene e senza caricare l'immagine intera.
      let longest = max(output.width, output.height)
      if let image = thumbnail(of: source, maxPixelSize: longest) {
        return image.width == output.width && image.height == output.height ? image : try draw(image, into: output)
      }
    }

    guard var image = thumbnail(of: source, maxPixelSize: max(info.size.width, info.size.height)) else {
      throw ImageResizeError.unreadable
    }
    var crop = geometry.crop
    if crop == nil, image.width == output.width, image.height == output.height { return image }
    // `thumbnail` può discostarsi di un pixel dalle dimensioni lette: il ritaglio sta dentro l'immagine.
    if var rect = crop {
      rect.x = min(rect.x, max(0, image.width - 1))
      rect.y = min(rect.y, max(0, image.height - 1))
      rect.width = min(rect.width, image.width - rect.x)
      rect.height = min(rect.height, image.height - rect.y)
      crop = rect
    }
    if let crop {
      guard let cropped = image.cropping(to: CGRect(x: crop.x, y: crop.y, width: crop.width, height: crop.height)) else {
        throw ImageResizeError.unreadable
      }
      image = cropped
      if image.width == output.width, image.height == output.height { return image }
    }
    return try draw(image, into: output)
  }

  private static func thumbnail(of source: CGImageSource, maxPixelSize: Int) -> CGImage? {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  private static func draw(_ image: CGImage, into size: PixelSize) throws -> CGImage {
    let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
    let alpha: CGImageAlphaInfo = image.hasAlpha ? .premultipliedLast : .noneSkipLast
    guard let context = CGContext(
      data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
      space: space, bitmapInfo: alpha.rawValue
    ) ?? CGContext(
      data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: alpha.rawValue
    ) else { throw ImageResizeError.cannotEncode }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
    guard let result = context.makeImage() else { throw ImageResizeError.cannotEncode }
    return result
  }

  // MARK: Scrittura

  /// I metadati dell'originale, meno ciò che il nuovo file ricalcola o che non è più vero:
  /// misure, e orientamento (i pixel sono già dritti: ruotarli ancora li girerebbe di nuovo).
  private static func metadata(of source: CGImageSource) -> [CFString: Any] {
    let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    var properties = original.filter { !ImageConverter.derivedKeys.contains($0.key) }
    properties[kCGImagePropertyOrientation] = nil

    if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
      exif[kCGImagePropertyExifPixelXDimension] = nil
      exif[kCGImagePropertyExifPixelYDimension] = nil
      properties[kCGImagePropertyExifDictionary] = exif
    }
    if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
      tiff[kCGImagePropertyTIFFOrientation] = nil
      properties[kCGImagePropertyTIFFDictionary] = tiff
    }
    if var iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
      iptc[kCGImagePropertyIPTCImageOrientation] = nil
      properties[kCGImagePropertyIPTCDictionary] = iptc
    }
    return properties
  }

  private static func encode(_ image: CGImage, as format: ImageFormat, quality: Double?, properties: [CFString: Any]) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, format.typeIdentifier as CFString, 1, nil) else {
      throw ImageResizeError.cannotEncode
    }
    var options = properties
    if let quality {
      options[kCGImageDestinationLossyCompressionQuality] = quality
    }
    CGImageDestinationAddImage(destination, image, options as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw ImageResizeError.cannotEncode }
    return data as Data
  }
}

nonisolated private extension CGImage {
  var hasAlpha: Bool {
    switch alphaInfo {
    case .none, .noneSkipFirst, .noneSkipLast: false
    default: true
    }
  }
}
