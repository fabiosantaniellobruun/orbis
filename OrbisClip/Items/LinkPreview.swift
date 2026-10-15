import ImageIO
import LinkPresentation
import UniformTypeIdentifiers

/// L'anteprima di un sito, con LinkPresentation: l'immagine che la pagina dichiara per la
/// condivisione (og:image) o, se non c'è, la sua icona.
nonisolated enum LinkPreview {
  static func png(for url: URL) async -> Data? {
    let provider = LPMetadataProvider()
    guard let metadata = try? await provider.startFetchingMetadata(for: url),
          let source = metadata.imageProvider ?? metadata.iconProvider,
          let data = await imageData(from: source)
    else { return nil }
    return thumbnailPNG(from: data)
  }

  private static func imageData(from provider: NSItemProvider) async -> Data? {
    await withCheckedContinuation { continuation in
      provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
        continuation.resume(returning: data)
      }
    }
  }

  /// Al massimo 240 pixel per lato: nel pannello la miniatura è di 40 punti.
  private static func thumbnailPNG(from data: Data) -> Data? {
    let options = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 240,
    ] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    else { return nil }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? output as Data : nil
  }
}
