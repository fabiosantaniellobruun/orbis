import AppKit

/// Apre il pannello di Ridimensiona e restituisce ciò che l'utente ha deciso.
final class ResizeController {
  private let host = FormPanelHost()
  private var model: ResizeModel?

  /// - Returns: `false` se tra i file non c'è nessuna immagine e il pannello non si apre.
  /// - Parameter onApply: riceve il lavoro da eseguire; il pannello si chiude prima.
  @discardableResult
  func present(_ urls: [URL], near point: NSPoint, onApply: @escaping (ResizeRequest) -> Void) -> Bool {
    close()

    let model = ResizeModel(urls: urls)
    guard model.hasImages else {
      model.stop()
      return false
    }
    model.onApply = { [weak self] request in
      self?.close()
      onApply(request)
    }
    model.onCancel = { [weak self] in
      self?.close()
    }

    host.present(ResizeView(model: model), cardSize: ResizeView.cardSize, near: point) { [weak self] in
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
