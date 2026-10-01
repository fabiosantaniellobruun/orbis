#if DEBUG
import AppKit

/// Fotografa le finestre visibili di Orbis, dall'interno: serve a controllare l'impaginazione
/// dei pannelli senza permessi di registrazione dello schermo. Il vetro esce piatto, perché è
/// il sistema a comporlo con ciò che sta dietro.
enum Snapshot {
  /// Scrive `<base>-1.png`, `<base>-2.png`… una per finestra visibile.
  static func writeVisibleWindows(to base: URL) {
    let windows = NSApp.windows.filter { $0.isVisible && $0.contentView != nil }
    for (index, window) in windows.enumerated() {
      guard let view = window.contentView,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
      else { continue }
      view.cacheDisplay(in: view.bounds, to: rep)
      let url = base.deletingPathExtension().appendingPathExtension("\(index + 1).png")
      try? rep.representation(using: .png, properties: [:])?.write(to: url)
      log.notice("Snapshot: \(url.path(percentEncoded: false), privacy: .public)")
    }
  }
}
#endif
