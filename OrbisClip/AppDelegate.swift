import AppKit
import os

nonisolated let log = Logger(subsystem: "it.fabiosbruun.OrbisClip", category: "clip")

final class AppDelegate: NSObject, NSApplicationDelegate {
  let store: ClipStore = {
    #if DEBUG
    // `--samples` prova il pannello con degli esempi, senza toccare gli elementi veri.
    if CommandLine.arguments.contains("--samples") { return .withSamples() }
    #endif
    return ClipStore()
  }()
  private(set) lazy var controller = ClipController(store: store)
  private let services = ServiceProvider()
  private let addWindow = AddItemWindowController()

  func applicationDidFinishLaunching(_ notification: Notification) {
    let arguments = CommandLine.arguments

    // Per le fotografie del pannello non serve intercettare il clic, né chiedere il permesso.
    if !arguments.contains("--snapshot") {
      controller.start()
    }
    Task { await store.loadMissingPreviews() }

    // "Aggiungi a Orbis Clip" nel menu contestuale, dichiarato in Info.plist.
    services.onReceive = { [weak self] pasteboard in self?.add(from: pasteboard) }
    NSApp.servicesProvider = services
    NSUpdateDynamicServices()

    // Avvio con `--preview` per vedere il pannello senza fare clic.
    if arguments.contains("--preview") {
      controller.showPreview()
    }

    #if DEBUG
    // `--add-preview` apre la finestra con cui si aggiunge un elemento, con un testo di prova.
    if arguments.contains("--add-preview") {
      add(ClipDraft(content: .text("Un saluto,\nFabio", rtf: nil), suggestedName: "Firma"))
    }

    // `--snapshot <percorso.png>` fotografa le finestre visibili dopo un attimo.
    if let flag = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(flag + 1) {
      let base = URL(filePath: arguments[flag + 1])
      Task {
        try? await Task.sleep(for: .seconds(2))
        Snapshot.writeVisibleWindows(to: base)
      }
    }
    #endif
  }

  /// Aggiunge ciò che c'è negli appunti: serve per le immagini copiate da un browser, che il menu
  /// Servizi non riceve.
  func addFromClipboard() {
    add(from: .general)
  }

  private func add(from pasteboard: NSPasteboard) {
    do {
      guard let draft = try ClipDraft(pasteboard: pasteboard) else {
        showError(String(localized: "Negli appunti non c'è niente che Orbis Clip sappia salvare: un testo, un link, un'immagine o un file."))
        return
      }
      add(draft)
    } catch {
      showError(error.localizedDescription)
    }
  }

  private func add(_ draft: ClipDraft) {
    addWindow.show(draft) { [store] item in
      store.add(item)
      Task { await store.loadMissingPreviews() }
      log.info("Aggiunto un elemento")
    }
  }

  private func showError(_ message: String) {
    NSApp.activate()
    let alert = NSAlert()
    alert.messageText = String(localized: "Non si può aggiungere")
    alert.informativeText = message
    alert.runModal()
  }
}
