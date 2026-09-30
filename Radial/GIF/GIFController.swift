import AppKit

/// Apre il pannello del GIF e restituisce ciò che l'utente ha deciso.
final class GIFController {
  private let host = FormPanelHost()
  private var model: GIFModel?

  /// - Returns: `false` se tra i file non c'è nessun video e il pannello non si apre.
  /// - Parameter onApply: riceve il lavoro da eseguire; il pannello si chiude prima.
  @discardableResult
  func present(_ urls: [URL], near point: NSPoint, onApply: @escaping (GIFRequest) -> Void) -> Bool {
    close()

    let videos = urls.filter(VideoReader.isVideo)
    guard !videos.isEmpty else { return false }

    let model = GIFModel(videos: videos, skipped: urls.count - videos.count)
    model.onApply = { [weak self] request in
      self?.close()
      onApply(request)
    }
    model.onCancel = { [weak self] in
      self?.close()
    }
    model.load()

    host.present(GIFView(model: model), cardSize: GIFView.cardSize, near: point) { [weak self] in
      self?.close()
    }
    self.model = model
    return true
  }

  func close() {
    model?.stop()
    host.close()
    model = nil
  }
}
