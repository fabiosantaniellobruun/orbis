import AppKit
import SwiftUI

/// La lingua dell'app: quella del sistema, italiano o inglese. macOS la sceglie all'avvio dalle
/// preferenze dell'app (`AppleLanguages`), quindi per cambiarla l'app si riapre.
struct LanguageSection: View {
  private static let key = "AppleLanguages"

  @State private var choice = Self.saved
  @State private var needsRelaunch = false

  /// La lingua scelta per questa app, o `nil` se segue il sistema. Il valore di `standard` ricadrebbe
  /// su quello globale: conta solo quello dell'app.
  private static var saved: String? {
    let own = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) }
    return (own?[key] as? [String])?.first
  }

  var body: some View {
    Section {
      Picker("Lingua", selection: $choice) {
        Text("Come il sistema").tag(String?.none)
        Text(verbatim: "Italiano").tag(String?.some("it"))
        Text(verbatim: "English").tag(String?.some("en"))
      }
      .onChange(of: choice) {
        if let choice {
          UserDefaults.standard.set([choice], forKey: Self.key)
        } else {
          UserDefaults.standard.removeObject(forKey: Self.key)
        }
        needsRelaunch = true
      }
    } footer: {
      if needsRelaunch {
        HStack {
          Text("La nuova lingua vale dalla prossima apertura.")
            .foregroundStyle(.secondary)
          Spacer()
          Button("Riapri ora", action: Self.relaunch)
        }
      }
    }
  }

  private static func relaunch() {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
      Task { @MainActor in NSApp.terminate(nil) }
    }
  }
}
