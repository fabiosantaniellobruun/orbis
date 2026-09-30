import AppKit
import os

let log = Logger(subsystem: "it.geckosoft.Radial", category: "radial")

final class AppDelegate: NSObject, NSApplicationDelegate {
  private(set) var controller: RadialController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = RadialController()
    controller.start()
    self.controller = controller

    // Avvio con `--preview` per vedere il menu senza trascinare nulla.
    if CommandLine.arguments.contains("--preview") {
      controller.showPreview()
    }
  }
}
