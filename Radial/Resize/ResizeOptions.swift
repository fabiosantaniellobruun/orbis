import Foundation

nonisolated struct PixelSize: Sendable, Equatable {
  var width: Int
  var height: Int

  /// Le stesse proporzioni, moltiplicate: mai sotto un pixel per lato.
  func scaled(by factor: Double) -> PixelSize {
    PixelSize(
      width: max(1, Int((Double(width) * factor).rounded())),
      height: max(1, Int((Double(height) * factor).rounded()))
    )
  }
}

nonisolated struct PixelRect: Sendable, Equatable {
  var x: Int
  var y: Int
  var width: Int
  var height: Int
}

/// Cosa fare a un'immagine: l'eventuale ritaglio e la misura finale.
nonisolated struct ResizeGeometry: Sendable, Equatable {
  /// Una parte dell'immagine da tenere, nelle sue coordinate; `nil` per tenerla tutta.
  var crop: PixelRect?
  var output: PixelSize
}

/// Un rapporto tra larghezza e altezza, come 16:9.
nonisolated struct AspectRatio: Sendable, Equatable, Hashable, Identifiable {
  var width: Int
  var height: Int

  var id: String { title }
  var title: String { "\(width):\(height)" }
  var isValid: Bool { width > 0 && height > 0 }

  /// Quelli che si usano davvero: quadrato, foto, schermo, social.
  static let presets = [
    AspectRatio(width: 1, height: 1),
    AspectRatio(width: 4, height: 3),
    AspectRatio(width: 3, height: 2),
    AspectRatio(width: 16, height: 9),
    AspectRatio(width: 5, height: 4),
  ]

  /// Col lato lungo in orizzontale (16:9) o in verticale (9:16).
  func oriented(landscape: Bool) -> AspectRatio {
    let long = max(width, height)
    let short = min(width, height)
    return landscape ? AspectRatio(width: long, height: short) : AspectRatio(width: short, height: long)
  }
}

/// Come ridimensionare: i tre modi, la compressione e il formato. Non dipende da nessuna immagine
/// in particolare: `geometry(for:)` lo applica a ognuna.
nonisolated struct ResizeOptions: Sendable, Equatable {
  enum Mode: String, CaseIterable, Identifiable, Sendable {
    case dimensions, percent, ratio

    var id: String { rawValue }

    var title: String {
      switch self {
      case .dimensions: "Dimensioni"
      case .percent: "Percentuale"
      case .ratio: "Proporzioni"
      }
    }
  }

  enum WeightUnit: String, CaseIterable, Identifiable, Sendable {
    case kilobytes, megabytes

    var id: String { rawValue }
    var title: String { self == .kilobytes ? "KB" : "MB" }
    var bytes: Int { self == .kilobytes ? 1_000 : 1_000_000 }
  }

  /// Oltre questo un lato è quasi certamente un errore di battitura (e un'immagine ingestibile).
  static let maxPixels = 30_000
  static let percentRange = 1...500
  static let qualityRange = 0.1...1.0

  var mode = Mode.dimensions

  // Dimensioni
  /// Larghezza e altezza in pixel; vuote, non pongono limiti.
  var width: Int?
  var height: Int?
  /// Con le proporzioni mantenute larghezza e altezza sono una scatola in cui far stare
  /// l'immagine; senza, l'immagine viene stirata fino a riempirla.
  var keepsProportions = true
  /// Le immagini già piccole non vengono ingrandite.
  var neverEnlarges = true

  // Percentuale
  var percent = 50

  // Proporzioni
  var ratio = AspectRatio.presets[1]
  var usesCustomRatio = false
  var customRatio = AspectRatio(width: 2, height: 1)
  /// Un'immagine in verticale prende il rapporto in verticale (9:16 invece di 16:9).
  var followsOrientation = true
  /// Il lato più lungo non supera questo valore, dopo il ritaglio.
  var longSide: Int?

  // Compressione
  /// `nil`: lo stesso formato dell'originale.
  var format: ImageFormat?
  var quality = 0.85
  var limitsWeight = false
  var weight = 500
  var weightUnit = WeightUnit.kilobytes

  var effectiveRatio: AspectRatio { usesCustomRatio ? customRatio : ratio }

  /// Il peso da non superare, in byte.
  var maxBytes: Int? { limitsWeight && weight > 0 ? weight * weightUnit.bytes : nil }

  /// Cosa impedisce di applicare queste opzioni, se c'è qualcosa.
  var problem: String? {
    // Contano solo i campi del modo in uso: un valore rimasto in un altro modo non si vede.
    let sides = switch mode {
    case .dimensions: [width, height].compactMap { $0 }
    case .percent: [Int]()
    case .ratio: [longSide].compactMap { $0 }
    }
    if sides.contains(where: { $0 < 1 }) { return "Le misure devono essere almeno 1 pixel" }
    if sides.contains(where: { $0 > Self.maxPixels }) { return "Le misure non possono superare \(Self.maxPixels) pixel" }
    if mode == .dimensions, !keepsProportions, width == nil || height == nil {
      return "Senza proporzioni bloccate servono larghezza e altezza"
    }
    if mode == .percent, !Self.percentRange.contains(percent) { return "La percentuale va da 1 a 500" }
    if mode == .ratio, !effectiveRatio.isValid { return "Il rapporto non è valido" }
    return nil
  }

  // MARK: Misure

  /// Ritaglio e misura finale per un'immagine di queste dimensioni (con l'orientamento già
  /// applicato, cioè com'è vista).
  func geometry(for source: PixelSize) -> ResizeGeometry {
    switch mode {
    case .dimensions: dimensionsGeometry(for: source)
    case .percent: ResizeGeometry(output: source.scaled(by: Double(percent) / 100))
    case .ratio: ratioGeometry(for: source)
    }
  }

  private func dimensionsGeometry(for source: PixelSize) -> ResizeGeometry {
    guard keepsProportions else {
      var output = PixelSize(width: width ?? source.width, height: height ?? source.height)
      if neverEnlarges {
        output.width = min(output.width, source.width)
        output.height = min(output.height, source.height)
      }
      return ResizeGeometry(output: PixelSize(width: max(1, output.width), height: max(1, output.height)))
    }

    var factor = Double.infinity
    if let width { factor = min(factor, Double(width) / Double(source.width)) }
    if let height { factor = min(factor, Double(height) / Double(source.height)) }
    if factor == .infinity { factor = 1 }
    if neverEnlarges { factor = min(factor, 1) }

    // L'arrotondamento non deve far uscire l'immagine dalla scatola.
    var output = source.scaled(by: factor)
    if let width { output.width = max(1, min(output.width, width)) }
    if let height { output.height = max(1, min(output.height, height)) }
    return ResizeGeometry(output: output)
  }

  private func ratioGeometry(for source: PixelSize) -> ResizeGeometry {
    var target = effectiveRatio
    if followsOrientation, target.width != target.height {
      target = target.oriented(landscape: source.width >= source.height)
    }

    // Il ritaglio più grande possibile, al centro.
    var crop = PixelRect(x: 0, y: 0, width: source.width, height: source.height)
    if source.width * target.height > source.height * target.width {
      crop.width = min(source.width, max(1, Int((Double(source.height) * Double(target.width) / Double(target.height)).rounded())))
      crop.x = (source.width - crop.width) / 2
    } else {
      crop.height = min(source.height, max(1, Int((Double(source.width) * Double(target.height) / Double(target.width)).rounded())))
      crop.y = (source.height - crop.height) / 2
    }

    var output = PixelSize(width: crop.width, height: crop.height)
    if let longSide, max(output.width, output.height) > longSide {
      output = output.scaled(by: Double(longSide) / Double(max(output.width, output.height)))
    }

    let keepsWholeImage = crop.width == source.width && crop.height == source.height
    return ResizeGeometry(crop: keepsWholeImage ? nil : crop, output: output)
  }
}
