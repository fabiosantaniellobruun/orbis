import Foundation
import Observation

@Observable
final class ResizeModel {
  let sources: [ResizeSource]
  var options = ResizeOptions()

  /// Il peso stimato dei file nuovi, per i primi file: si scrive davvero l'immagine, in memoria.
  private(set) var estimatedBytes: [URL: Int] = [:]

  var onApply: ((ResizeRequest) -> Void)?
  var onCancel: (() -> Void)?

  private var estimateTask: Task<Void, Never>?

  /// Quanti file si stimano: ogni stima decodifica e scrive un'immagine.
  private static let estimateLimit = 4

  init(urls: [URL]) {
    self.sources = urls.map { ResizeSource(url: $0) }
    #if DEBUG
    // Per fotografare il pannello in un modo preciso (vedi `Snapshot`).
    if let mode = ProcessInfo.processInfo.environment["ORBIS_RESIZE_MODE"].flatMap(ResizeOptions.Mode.init(rawValue:)) {
      options.mode = mode
      options.limitsWeight = true
    }
    #endif
    scheduleEstimates()
  }

  var hasImages: Bool { sources.contains { $0.info != nil } }

  var plan: ResizePlan {
    ResizePlan.make(sources: sources, options: options)
  }

  func apply(_ plan: ResizePlan) {
    guard plan.canApply else { return }
    onApply?(plan.request)
  }

  func stop() {
    estimateTask?.cancel()
  }

  // MARK: Stima del peso

  /// Da chiamare quando le opzioni cambiano: rifà la stima, dopo un attimo di quiete.
  func scheduleEstimates() {
    estimateTask?.cancel()
    estimatedBytes = [:]

    let plan = self.plan
    guard options.problem == nil else { return }
    let jobs = Array(plan.jobs.prefix(Self.estimateLimit))
    guard !jobs.isEmpty else { return }
    let quality = options.quality
    let maxBytes = options.maxBytes

    estimateTask = Task {
      // Niente lavoro finché si sta ancora scrivendo.
      try? await Task.sleep(for: .milliseconds(300))
      for job in jobs {
        guard !Task.isCancelled else { return }
        guard let bytes = await Self.estimate(job, quality: quality, maxBytes: maxBytes) else { continue }
        guard !Task.isCancelled else { return }
        estimatedBytes[job.url] = bytes
      }
    }
  }

  @concurrent
  private static func estimate(_ job: ResizeJob, quality: Double, maxBytes: Int?) async -> Int? {
    try? ImageResizer.render(job.url, geometry: job.geometry, format: job.format, quality: quality, maxBytes: maxBytes).data.count
  }
}
