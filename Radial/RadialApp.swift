import SwiftUI

@main
struct RadialApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra("Radial", systemImage: "circle.hexagongrid.circle") {
      MenuContent(appDelegate: appDelegate)
    }

    Settings {
      SettingsView()
    }
  }
}

private struct MenuContent: View {
  let appDelegate: AppDelegate

  @Environment(\.openSettings) private var openSettings
  @AppStorage(TriggerShortcut.storageKey) private var storedShortcut = Data()

  private var shortcut: TriggerShortcut {
    (try? JSONDecoder().decode(TriggerShortcut.self, from: storedShortcut)) ?? .standard
  }

  var body: some View {
    Text("Trascina dei file e tieni premuto \(shortcut.displayString)")
    Divider()
    Button("Mostra menu di prova") {
      appDelegate.controller?.showPreview()
    }
    Button("Impostazioni…") {
      // Un'app senza icona nel Dock non è mai in primo piano: senza attivarla, la finestra
      // si aprirebbe dietro le altre.
      NSApp.activate()
      openSettings()
    }
    .keyboardShortcut(",")
    Button("Come si usa…") {
      appDelegate.showWelcome()
    }
    Divider()
    Button("Esci da Radial") {
      NSApp.terminate(nil)
    }
    .keyboardShortcut("q")
  }
}
