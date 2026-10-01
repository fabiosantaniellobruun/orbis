import CoreGraphics
import Foundation
import Observation

@Observable
final class GIFModel {
  /// I video trascinati. Con uno solo si sceglie l'intervallo; con più di uno, ognuno va per intero.
  let videos: [URL]
  /// I file trascinati che non sono video.
  let skipped: Int
  var options = GIFOptions()

  private(set) var infos: [URL: VideoInfo] = [:]
  private(set) var thumbnails: [CGImage] = []
  private(set) var loadFailed = false
  private(set) var sample: GIFSample?
  private(set) var isSampling = false

  var onApply: ((GIFRequest) -> Void)?
  var onCancel: (() -> Void)?

  private var loadTask: Task<Void, Never>?
  private var sampleTask: Task<Void, Never>?

  init(videos: [URL], skipped: Int) {
    precondition(!videos.isEmpty, "Serve almeno un video")
    self.videos = videos
    self.skipped = skipped
  }

  var first: URL { videos[0] }
  var info: VideoInfo? { infos[first] }
  var isMultiple: Bool { videos.count > 1 }

  /// Legge durata e misure dei video, e prepara le miniature del primo.
  func load() {
    loadTask = Task {
      for url in videos {
        if let info = try? await VideoReader.info(of: url) {
          infos[url] = info
        }
      }
      guard let info else {
        loadFailed = true
        return
      }
      options = GIFOptions(duration: info.duration)
      scheduleSample()
      thumbnails = await VideoReader.thumbnails(of: first, count: 10, maxSize: CGSize(width: 160, height: 160))
    }
  }

  func stop() {
    loadTask?.cancel()
    sampleTask?.cancel()
  }

  // MARK: Lavoro

  /// Le opzioni per un video: con più video l'intervallo è il video intero, fino al massimo di
  /// fotogrammi.
  func job(for url: URL) -> GIFJob? {
    guard let info = infos[url] else { return nil }
    var options = options
    if isMultiple {
      options.start = 0
      options.end = min(info.duration, Double(GIFOptions.maxFrames) * options.speed / Double(options.fps))
    }
    return GIFJob(url: url, info: info, options: options)
  }

  var problem: String? { job(for: first)?.options.problem }

  var canApply: Bool { info != nil && problem == nil }

  var request: GIFRequest {
    let jobs = videos.compactMap(job(for:))
    return GIFRequest(jobs: jobs, skipped: skipped + videos.count - jobs.count)
  }

  func apply() {
    guard canApply else { return }
    onApply?(request)
  }

  // MARK: Anteprima

  /// Rifà l'anteprima (e la stima del peso) un attimo dopo che le opzioni smettono di cambiare.
  func scheduleSample() {
    sampleTask?.cancel()
    guard let job = job(for: first), job.options.problem == nil else {
      sample = nil
      isSampling = false
      return
    }
    isSampling = true
    sampleTask = Task {
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled else { return }
      let result = try? await GIFMaker.sample(job.url, info: job.info, options: job.options)
      guard !Task.isCancelled else { return }
      sample = result
      isSampling = false
    }
  }
}
