import Foundation

nonisolated struct GIFOutput: Sendable {
  let data: Data
  /// I fotogrammi scritti: quelli identici al precedente si fondono con lui.
  let frameCount: Int
  let size: PixelSize
  /// `false` se era stato chiesto un peso massimo e non è stato raggiunto.
  let reachedTarget: Bool
}

nonisolated struct GIFSample: Sendable {
  let data: Data
  let size: PixelSize
  /// Il peso stimato del GIF intero, dal peso del campione.
  let estimatedBytes: Int
}

/// Trasforma un video in GIF: due passaggi sul video, il primo per scegliere la palette su un
/// campione di fotogrammi, il secondo per scriverli. Nessun fotogramma resta in memoria.
nonisolated enum GIFMaker {
  /// Quanti tentativi, riducendo le dimensioni, per stare sotto il peso massimo.
  private static let attempts = 4

  @concurrent
  static func make(
    _ url: URL,
    info: VideoInfo,
    options: GIFOptions,
    progress: @escaping @Sendable (Double) -> Void = { _ in }
  ) async throws -> GIFOutput {
    let base = options.geometry(for: info.size)
    var size = base.output

    for attempt in 0..<attempts {
      let geometry = ResizeGeometry(crop: base.crop, output: size)
      let (data, frames) = try await encode(url, times: options.frameTimes(), geometry: geometry, options: options) { fraction in
        progress((Double(attempt) + fraction) / Double(options.maxBytes == nil ? 1 : attempts))
      }
      guard let maxBytes = options.maxBytes, data.count > maxBytes else {
        return GIFOutput(data: data, frameCount: frames, size: size, reachedTarget: true)
      }
      // Il peso va circa con il numero di pixel: si riduce il lato di conseguenza, con un margine.
      let smaller = size.scaled(by: (Double(maxBytes) / Double(data.count)).squareRoot() * 0.92)
      if attempt == attempts - 1 || min(smaller.width, smaller.height) < 16 {
        return GIFOutput(data: data, frameCount: frames, size: size, reachedTarget: false)
      }
      size = smaller
    }
    throw VideoError.cannotRead
  }

  /// Un pezzo di circa due secondi, per vedere come verrà e stimarne il peso.
  @concurrent
  static func sample(_ url: URL, info: VideoInfo, options: GIFOptions) async throws -> GIFSample {
    var options = options
    // L'anteprima gira sempre, qualunque sia la scelta per il file.
    options.loop = .forever
    let geometry = options.geometry(for: info.size)
    let times = options.sampleTimes()
    let (data, _) = try await encode(url, times: times, geometry: geometry, options: options) { _ in }
    let total = options.frameCount
    // Intestazione e palette si pagano una volta sola.
    let header = 800
    let perFrame = Double(max(0, data.count - header)) / Double(max(1, times.count))
    return GIFSample(data: data, size: geometry.output, estimatedBytes: header + Int(perFrame * Double(total)))
  }

  static func encode(
    _ url: URL,
    times: [Double],
    geometry: ResizeGeometry,
    options: GIFOptions,
    progress: (Double) -> Void
  ) async throws -> (data: Data, frames: Int) {
    // Palette: da una cinquantina di fotogrammi presi a intervalli regolari, e da un campione di
    // pixel di ciascuno.
    var histogram = ColorHistogram()
    let paletteStep = max(1, times.count / 50)
    let paletteTimes = stride(from: 0, to: times.count, by: paletteStep).map { times[$0] }
    let pixelStep = max(1, geometry.output.width * geometry.output.height / 60_000)
    try await VideoReader.readFrames(of: url, at: paletteTimes, geometry: geometry) { index, frame in
      histogram.add(frame, step: pixelStep)
      progress(0.2 * Double(index + 1) / Double(paletteTimes.count))
    }

    let colors = options.optimizes ? min(options.colors, 255) : options.colors
    let palette = GIFPalette.make(from: histogram, count: colors)
    let writer = GIFWriter(
      width: geometry.output.width,
      height: geometry.output.height,
      palette: palette,
      settings: options.settings
    )
    let delays = GIFOptions.delays(count: times.count, fps: options.fps)
    try await VideoReader.readFrames(of: url, at: times, geometry: geometry) { index, frame in
      writer.add(frame, delay: delays[index])
      progress(0.2 + 0.8 * Double(index + 1) / Double(times.count))
    }
    let data = writer.finish()
    return (data, writer.frameCount)
  }
}

/// Un video da trasformare, con le sue opzioni (l'intervallo è suo).
nonisolated struct GIFJob: Sendable, Equatable {
  let url: URL
  let info: VideoInfo
  let options: GIFOptions
}

nonisolated struct GIFRequest: Sendable, Equatable {
  let jobs: [GIFJob]
  /// I file trascinati che non sono video.
  let skipped: Int
}
