import AppKit

/// Apre il pannello di Rinomina e restituisce ciò che l'utente ha deciso.
final class RenameController {
  private let host = FormPanelHost()
  private var model: RenameModel?

  /// - Parameter onApply: riceve i rinomini da eseguire; il pannello si chiude prima.
  func present(_ urls: [URL], near point: NSPoint, onApply: @escaping ([RenameEntry]) -> Void) {
    close()

    let model = RenameModel(urls: urls)
    model.onApply = { [weak self] entries in
      self?.close()
      onApply(entries)
    }
    model.onCancel = { [weak self] in
      self?.close()
    }

    host.present(RenameView(model: model), cardSize: RenameView.cardSize, near: point) { [weak self] in
      self?.close()
    }
    self.model = model
  }

  func close() {
    host.close()
    model = nil
  }
}
