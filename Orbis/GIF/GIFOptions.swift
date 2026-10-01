import Foundation

/// Come trasformare un video in GIF: quale parte, a che velocità, quanto grande, con quanti
/// fotogrammi e colori.
nonisolated struct GIFOptions: Sendable, Equatable {
  enum Loop: String, CaseIterable, Identifiable, Sendable {
    case forever, once, times

    var id: String { rawValue }

    var title: String {
      switch self {
      case .forever: "Sempre"
      case .once: "Una volta"
      case .times: "Più volte"
      }
    }
  }

  static let fpsRange = 5...30
  static let speeds: [Double] = [0.5, 1, 1.5, 2, 3, 4]
  static let colorChoices = [16, 32, 64, 128, 256]
  static let ratios = [
    AspectRatio(width: 1, height: 1),
    AspectRatio(width: 4, height: 3),
    AspectRatio(width: 16, height: 9),
    AspectRatio(width: 9, height: 16),
    AspectRatio(width: 4, height: 5),
  ]
  /// Oltre, il GIF pesa troppo per qualunque uso, e scriverlo richiede minuti.
  static let maxFrames = 1_500
  static let maxSide = 4_000
  /// All'apertura si propongono al massimo i primi secondi: un GIF è quasi sempre breve.
  static let initialDuration = 10.0

  /// Da dove a dove, in secondi del video.
  var start = 0.0
  var end = 0.0
  var speed = 1.0
  var fps = 15
  /// La scatola in cui sta il GIF, in pixel; un lato vuoto non pone limiti. Non si ingrandisce.
  var width: Int? = 480
  var height: Int?
  /// Un ritaglio al centro; `nil` per tenere il fotogramma intero.
  var ratio: AspectRatio?
  var colors = 256
  var dithering = GIFDithering.diffusion
  var optimizes = true
  var loop = Loop.forever
  /// Quante volte si vede in tutto, con `Loop.times`.
  var plays = 3
  var limitsWeight = false
  var weight = 5
  var weightUnit = ResizeOptions.WeightUnit.megabytes

  init() {}

  /// Le opzioni di partenza per un video: i primi secondi.
  init(duration: Double) {
    end = min(max(duration, 0), Self.initialDuration)
  }

  var maxBytes: Int? { limitsWeight && weight > 0 ? weight * weightUnit.bytes : nil }

  /// Le sole opzioni che cambiano l'aspetto dell'anteprima: ripetizioni e peso massimo no.
  var previewKey: GIFOptions {
    var key = self
    key.loop = .forever
    key.plays = 3
    key.limitsWeight = false
    key.weight = 5
    key.weightUnit = .megabytes
    return key
  }

  /// Quanto dura il GIF, tenuto conto della velocità.
  var outputDuration: Double { max(0, end - start) / speed }

  var frameCount: Int { max(1, Int((outputDuration * Double(fps) + 1e-6).rounded(.down))) }

  /// L'istante del video mostrato da ogni fotogramma.
  func frameTimes() -> [Double] {
    (0..<frameCount).map { start + Double($0) * speed / Double(fps) }
  }

  /// Un pezzo di circa due secondi dal mezzo dell'intervallo, per l'anteprima e la stima del peso.
  func sampleTimes() -> [Double] {
    let times = frameTimes()
    let length = min(times.count, max(2, fps * 2))
    let first = max(0, (times.count - length) / 2)
    return Array(times[first..<(first + length)])
  }

  /// Quanto resta a schermo ogni fotogramma, in centesimi di secondo: il GIF non sa fare di meglio,
  /// e gli arrotondamenti si compensano perché il totale resti giusto.
  static func delays(count: Int, fps: Int) -> [Int] {
    (0..<count).map { index in
      let from = (Double(index) * 100 / Double(fps)).rounded()
      let to = (Double(index + 1) * 100 / Double(fps)).rounded()
      return Int(to - from)
    }
  }

  func geometry(for source: PixelSize) -> ResizeGeometry {
    let crop = ratio.map { source.centeredCrop(ratio: $0) }
    let base = crop.map { PixelSize(width: $0.width, height: $0.height) } ?? source
    let output = base.fitted(width: width, height: height, neverEnlarges: true)
    let keepsWholeFrame = crop.map { $0.width == source.width && $0.height == source.height } ?? true
    return ResizeGeometry(crop: keepsWholeFrame ? nil : crop, output: output)
  }

  var settings: GIFSettings {
    let repeats: Int? = switch loop {
    case .forever: 0
    case .once: nil
    case .times: max(1, plays - 1)
    }
    return GIFSettings(dithering: dithering, optimizes: optimizes, repeats: repeats)
  }

  /// Cosa impedisce di creare il GIF, se c'è qualcosa.
  var problem: String? {
    let sides = [width, height].compactMap { $0 }
    if sides.contains(where: { $0 < 1 }) { return "Le misure devono essere almeno 1 pixel" }
    if sides.contains(where: { $0 > Self.maxSide }) { return "Le misure non possono superare \(Self.maxSide) pixel" }
    if end - start < 0.05 { return "Scegli un intervallo più lungo" }
    if !Self.fpsRange.contains(fps) { return "I fotogrammi al secondo vanno da 5 a 30" }
    if frameCount > Self.maxFrames {
      return "Troppi fotogrammi (\(frameCount)): accorcia l'intervallo o abbassa i fotogrammi al secondo"
    }
    if loop == .times, plays < 2 { return "Per ripeterlo servono almeno 2 volte" }
    return nil
  }
}
