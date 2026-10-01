import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// I formati in cui Orbis converte le immagini: quelli che il sistema sa scrivere da solo, senza
/// programmi aggiuntivi.
nonisolated enum ImageFormat: String, CaseIterable, Sendable {
  case png, jpeg, heic, avif, tiff

  init?(typeIdentifier: String) {
    guard let format = Self.allCases.first(where: { $0.typeIdentifier == typeIdentifier }) else { return nil }
    self = format
  }

  var title: String {
    switch self {
    case .png: "PNG"
    case .jpeg: "JPEG"
    case .heic: "HEIC"
    case .avif: "AVIF"
    case .tiff: "TIFF"
    }
  }

  /// Due parole per scegliere: a cosa serve.
  var detail: String {
    switch self {
    case .png: "Senza perdita, con trasparenza"
    case .jpeg: "Foto, il più compatibile"
    case .heic: "Compatto, per i dispositivi Apple"
    case .avif: "Il più compatto, per il web"
    case .tiff: "Senza perdita, per la stampa"
    }
  }

  var typeIdentifier: String {
    switch self {
    case .png: UTType.png.identifier
    case .jpeg: UTType.jpeg.identifier
    case .heic: UTType.heic.identifier
    case .avif: "public.avif"
    case .tiff: UTType.tiff.identifier
    }
  }

  var fileExtension: String {
    switch self {
    case .png: "png"
    case .jpeg: "jpg"
    case .heic: "heic"
    case .avif: "avif"
    case .tiff: "tiff"
    }
  }

  var supportsTransparency: Bool { self != .jpeg }

  /// La qualità di partenza dei formati con perdita; gli altri non ne hanno.
  var defaultQuality: Double? {
    switch self {
    case .jpeg: 0.85
    case .heic: 0.8
    case .avif: 0.7
    case .png, .tiff: nil
    }
  }

  /// I formati che questo Mac sa davvero scrivere: non si propone ciò che poi non riesce.
  static let available: [ImageFormat] = {
    let writable = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
    return allCases.filter { writable.contains($0.typeIdentifier) }
  }()
}

nonisolated enum ImageConversionError: Error {
  case unreadable
  case cannotEncode
}

nonisolated enum ImageConverter {
  /// Il tipo dell'immagine, se il sistema sa leggere il file come immagine.
  static func imageType(of url: URL) -> String? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          CGImageSourceGetCount(source) > 0
    else { return nil }
    return CGImageSourceGetType(source) as String?
  }

  /// Scrive `destination` nel formato richiesto, con i metadati (data di scatto, posizione,
  /// orientamento) dell'originale. Di un'immagine animata si prende il primo fotogramma.
  static func convert(_ url: URL, to format: ImageFormat, destination: URL, quality: Double? = nil) throws {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
      throw ImageConversionError.unreadable
    }
    guard let output = CGImageDestinationCreateWithURL(destination as CFURL, format.typeIdentifier as CFString, 1, nil) else {
      throw ImageConversionError.cannotEncode
    }

    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    var options: [CFString: Any] = [:]
    if let quality = quality ?? format.defaultQuality {
      options[kCGImageDestinationLossyCompressionQuality] = quality
    }

    let hasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool ?? false
    if hasAlpha, !format.supportsTransparency, let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
      // JPEG non ha trasparenza: il fondo trasparente diventerebbe nero. Si appoggia su bianco.
      for (key, value) in properties where !Self.derivedKeys.contains(key) {
        options[key] = value
      }
      CGImageDestinationAddImage(output, flattenedOnWhite(image), options as CFDictionary)
    } else {
      CGImageDestinationAddImageFromSource(output, source, 0, options as CFDictionary)
    }

    guard CGImageDestinationFinalize(output) else {
      try? FileManager.default.removeItem(at: destination)
      throw ImageConversionError.cannotEncode
    }
  }

  /// Le proprietà che descrivono l'immagine com'era e che il nuovo file ricalcola da sé.
  static var derivedKeys: Set<CFString> {
    [
      kCGImagePropertyHasAlpha, kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight,
      kCGImagePropertyDepth, kCGImagePropertyColorModel, kCGImagePropertyIsIndexed,
      kCGImagePropertyIsFloat, kCGImagePropertyPNGDictionary, kCGImagePropertyGIFDictionary,
    ]
  }

  /// L'immagine appoggiata su un fondo bianco, senza trasparenza.
  static func flattenedOnWhite(_ image: CGImage) -> CGImage {
    let width = image.width
    let height = image.height
    let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) ?? CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return image }

    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(rect)
    context.draw(image, in: rect)
    return context.makeImage() ?? image
  }
}
