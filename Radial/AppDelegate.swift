import AppKit
import os

nonisolated let log = Logger(subsystem: "it.fabiosbruun.Radial", category: "radial")

final class AppDelegate: NSObject, NSApplicationDelegate {
  private(set) var controller: RadialController?
  private let welcome = WelcomeWindowController()

  func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = RadialController()
    controller.start()
    self.controller = controller

    let arguments = CommandLine.arguments

    // Al primo avvio si spiega come si usa: l'app non ha icona nel Dock.
    if welcome.isFirstLaunch || arguments.contains("--welcome") {
      welcome.show()
    }

    // Avvio con `--preview` per vedere il menu senza trascinare nulla.
    if arguments.contains("--preview") {
      controller.showPreview()
    }

    #if DEBUG
    // `--snapshot <percorso.png>` fotografa le finestre visibili dopo un attimo: va prima di `--run`.
    if let flag = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(flag + 1) {
      let base = URL(filePath: arguments[flag + 1])
      Task {
        try? await Task.sleep(for: .seconds(2))
        Snapshot.writeVisibleWindows(to: base)
      }
    }

    // `--run <azione> <percorsi…>` esegue un'azione senza passare dal menu, per provarla
    // da riga di comando. Va messo per ultimo: tutto ciò che segue l'azione è un percorso.
    if let flag = arguments.firstIndex(of: "--run"),
       let id = arguments.dropFirst(flag + 1).first.flatMap(RadialAction.ID.init(rawValue:)) {
      controller.run(id, on: arguments.dropFirst(flag + 2).map { URL(filePath: $0) })
    }

    // `--settings` apre subito la finestra delle impostazioni.
    if arguments.contains("--settings") {
      NSApp.activate()
      NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    #endif
  }

  func showWelcome() {
    welcome.show()
  }
}
