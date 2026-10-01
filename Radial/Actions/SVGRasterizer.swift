import AppKit
import ImageIO
import UniformTypeIdentifiers

nonisolated enum SVGRasterizerError: Error {
  case unreadable
  case tooLarge
  case cannotEncode
}

/// Esporta gli SVG in PNG a 1x, 2x, 3x e 4x. ImageIO non legge gli SVG: li disegna AppKit
/// (`NSImage` li apre come immagini vettoriali), quindi a ogni scala il disegno resta nitido.
nonisolated enum SVGRasterizer {
  static let scales = [1, 2, 3, 4]
  /// Oltre questa misura per lato il PNG non serve a nessuno e la memoria sì.
  static let maxPixels = 16_384

  static func isSVG(_ url: URL) -> Bool {
    if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
      return type.conforms(to: .svg)
    }
    return url.pathExtension.lowercased() == "svg"
  }

  /// Il nome del PNG a quella scala, alla maniera di Apple: "logo", "logo@2x", "logo@3x".
  static func stem(_ stem: String, scale: Int) -> String {
    scale == 1 ? stem : "\(stem)@\(scale)x"
  }

  /// La misura a 1x, in punti, come la dichiara l'SVG (larghezza e altezza, o il viewBox).
  static func size(of url: URL) -> CGSize? {
    guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else { return nil }
    return image.size
  }

  /// Il PNG dell'SVG a quella scala, trasparente dove l'SVG non disegna. La risoluzione
  /// dichiarata è 72 dpi per scala (144 a 2x), come per le risorse @2x.
  static func png(_ url: URL, scale: Int) throws -> Data {
    guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else {
      throw SVGRasterizerError.unreadable
    }
    let factor = CGFloat(scale)
    let width = Int((image.size.width * factor).rounded())
    let height = Int((image.size.height * factor).rounded())
    guard width > 0, height > 0, width <= maxPixels, height <= maxPixels else { throw SVGRasterizerError.tooLarge }

    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else { throw SVGRasterizerError.cannotEncode }

    // Il disegno è vettoriale: ingrandire il contesto lo ridisegna a quella risoluzione.
    context.scaleBy(x: factor, y: factor)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    image.draw(in: CGRect(origin: .zero, size: image.size))
    NSGraphicsContext.restoreGraphicsState()

    guard let rendered = context.makeImage() else { throw SVGRasterizerError.cannotEncode }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
      throw SVGRasterizerError.cannotEncode
    }
    let properties: [CFString: Any] = [
      kCGImagePropertyDPIWidth: 72 * scale,
      kCGImagePropertyDPIHeight: 72 * scale,
    ]
    CGImageDestinationAddImage(destination, rendered, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw SVGRasterizerError.cannotEncode }
    return data as Data
  }
}
