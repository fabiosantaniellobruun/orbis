import SwiftUI

@main
struct RadialApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra("Radial", systemImage: "circle.hexagongrid.circle") {
      Text("Trascina dei file e tieni premuto ⇧")
      Divider()
      Button("Mostra menu di prova") {
        appDelegate.controller?.showPreview()
      }
      Divider()
      Button("Esci da Radial") {
        NSApp.terminate(nil)
      }
      .keyboardShortcut("q")
    }
  }
}
