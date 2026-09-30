import Foundation

/// Un file da ridimensionare. `info` è `nil` se il sistema non lo legge come immagine.
nonisolated struct ResizeSource: Sendable, Equatable, Identifiable {
  let url: URL
  let info: ImageInfo?

  var id: URL { url }
  var name: String { url.lastPathComponent }

  init(url: URL) {
    self.url = url
    self.info = ImageInfo.read(url)
  }

  init(url: URL, info: ImageInfo?) {
    self.url = url
    self.info = info
  }
}

/// Un'immagine, con ciò che va fatto: si può eseguire senza ricalcolare nulla.
nonisolated struct ResizeJob: Sendable, Equatable {
  let url: URL
  let geometry: ResizeGeometry
  let format: ImageFormat
  /// L'estensione del file nuovo: quella dell'originale se il formato non cambia.
  let fileExtension: String
}

/// Tutto ciò che serve a eseguire il ridimensionamento.
nonisolated struct ResizeRequest: Sendable, Equatable {
  let jobs: [ResizeJob]
  let quality: Double
  let maxBytes: Int?
  /// I file che non si ridimensionano (non sono immagini, sono animati…).
  let skipped: Int
}

/// Il risultato di applicare le opzioni ai file: per ognuno cosa ne verrebbe fuori, oppure perché
/// lo si salta. Non tocca il disco: si può ricalcolare a ogni tasto.
nonisolated struct ResizePlan: Sendable, Equatable {
  enum Skip: Sendable, Equatable {
    case notAnImage
    case animated
    case unwritableFormat
    case unchanged

    var message: String {
      switch self {
      case .notAnImage: "Non è un'immagine"
      case .animated: "Ha più immagini: non si ridimensiona"
      case .unwritableFormat: "Il Mac non sa scrivere questo formato: sceglierne un altro"
      case .unchanged: "Stesse misure e stesso formato: niente da fare"
      }
    }
  }

  struct Row: Sendable, Equatable, Identifiable {
    enum Status: Sendable, Equatable {
      case ready(ResizeJob)
      case skipped(Skip)
    }

    let source: ResizeSource
    let status: Status

    var id: URL { source.id }

    var job: ResizeJob? {
      if case .ready(let job) = status { job } else { nil }
    }
  }

  let rows: [Row]
  let options: ResizeOptions

  var jobs: [ResizeJob] { rows.compactMap(\.job) }
  var skippedCount: Int { rows.count - jobs.count }

  var canApply: Bool { options.problem == nil && !jobs.isEmpty }

  var request: ResizeRequest {
    ResizeRequest(jobs: jobs, quality: options.quality, maxBytes: options.maxBytes, skipped: skippedCount)
  }

  /// - Parameter writable: i formati che questo Mac sa scrivere.
  static func make(
    sources: [ResizeSource],
    options: ResizeOptions,
    writable: [ImageFormat] = ImageFormat.available
  ) -> ResizePlan {
    let rows = sources.map { source in
      Row(source: source, status: status(for: source, options: options, writable: writable))
    }
    return ResizePlan(rows: rows, options: options)
  }

  private static func status(for source: ResizeSource, options: ResizeOptions, writable: [ImageFormat]) -> Row.Status {
    guard let info = source.info else { return .skipped(.notAnImage) }
    guard info.frameCount == 1 else { return .skipped(.animated) }

    let format: ImageFormat
    if let chosen = options.format {
      format = chosen
    } else if let original = ImageFormat(typeIdentifier: info.type), writable.contains(original) {
      format = original
    } else {
      return .skipped(.unwritableFormat)
    }

    let keepsFormat = format.typeIdentifier == info.type
    let geometry = options.geometry(for: info.size)
    // Senza perdita, alle stesse misure e nello stesso formato, verrebbe fuori la stessa immagine
    // (spesso più pesante, se l'originale era stato ottimizzato). Con perdita si ricomprime.
    if keepsFormat, format.defaultQuality == nil, geometry == ResizeGeometry(output: info.size) {
      return .skipped(.unchanged)
    }

    let original = source.url.pathExtension
    let fileExtension = keepsFormat && !original.isEmpty ? original : format.fileExtension

    return .ready(ResizeJob(
      url: source.url,
      geometry: geometry,
      format: format,
      fileExtension: fileExtension
    ))
  }
}
