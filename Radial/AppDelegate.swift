import AppKit
import os

nonisolated let log = Logger(subsystem: "it.fabiosbruun.Radial", category: "radial")

final class AppDelegate: NSObject, NSApplicationDelegate {
  private(set) var controller: RadialController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = RadialController()
    controller.start()
    self.controller = controller

    // Avvio con `--preview` per vedere il menu senza trascinare nulla.
    let arguments = CommandLine.arguments
    if arguments.contains("--preview") {
      controller.showPreview()
    }

    #if DEBUG
    // `--run <azione> <percorsi…>` esegue un'azione senza passare dal menu, per provarla
    // da riga di comando. Va messo per ultimo: tutto ciò che segue l'azione è un percorso.
    if let flag = arguments.firstIndex(of: "--run"),
       let id = arguments.dropFirst(flag + 1).first.flatMap(RadialAction.ID.init(rawValue:)) {
      controller.run(id, on: arguments.dropFirst(flag + 2).map { URL(filePath: $0) })
    }
    #endif
  }
}
