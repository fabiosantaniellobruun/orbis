import SwiftUI

@main
struct OrbisClipApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    MenuBarExtra("Orbis Clip", systemImage: "paperclip") {
      MenuContent(appDelegate: appDelegate)
    }

    Window("Elementi di Orbis Clip", id: Self.libraryID) {
      LibraryView(store: appDelegate.store) {
        appDelegate.addFromClipboard()
      }
    }
    .defaultSize(width: 760, height: 520)
    // `--library` apre la finestra all'avvio, per provarla.
    .defaultLaunchBehavior(CommandLine.arguments.contains("--library") ? .presented : .suppressed)

    Settings {
      ClipSettingsView { appDelegate.controller.reloadTrigger() }
    }
  }

  static let libraryID = "library"
}

private struct MenuContent: View {
  let appDelegate: AppDelegate

  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings
  // Per rileggere la combinazione quando cambia nelle impostazioni.
  @AppStorage(ClipTrigger.storageKey) private var storedTrigger = Data()

  var body: some View {
    if appDelegate.controller.hasAccessibility {
      Text("\(((try? JSONDecoder().decode(ClipTrigger.self, from: storedTrigger)) ?? .standard).displayString) apre il pannello")
    } else {
      Text("Serve il permesso Accessibilità")
      Button("Apri Privacy e sicurezza…") {
        NSWorkspace.shared.open(Accessibility.settingsURL)
      }
    }
    Divider()
    Button("Elementi…") {
      // Un'app senza icona nel Dock non è mai in primo piano: senza attivarla, la finestra
      // si aprirebbe dietro le altre.
      NSApp.activate()
      openWindow(id: OrbisClipApp.libraryID)
    }
    .keyboardShortcut("e")
    Button("Aggiungi dagli appunti…") {
      appDelegate.addFromClipboard()
    }
    Button("Mostra pannello di prova") {
      appDelegate.controller.showPreview()
    }
    Button("Impostazioni…") {
      NSApp.activate()
      openSettings()
    }
    .keyboardShortcut(",")
    Divider()
    Button("Esci da Orbis Clip") {
      NSApp.terminate(nil)
    }
    .keyboardShortcut("q")
  }
}
