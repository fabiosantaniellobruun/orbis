import SwiftUI

/// La combinazione che apre il pannello (tasti e tasto del mouse) e l'avvio al login.
struct ClipSettingsView: View {
  /// Chiamato dopo ogni modifica della combinazione, perché valga subito.
  var onTriggerChange: () -> Void

  @AppStorage(ClipTrigger.storageKey) private var storedTrigger = Data()

  private var trigger: ClipTrigger {
    (try? JSONDecoder().decode(ClipTrigger.self, from: storedTrigger)) ?? .standard
  }

  private func binding<Value>(_ keyPath: WritableKeyPath<ClipTrigger, Value>) -> Binding<Value> {
    Binding(
      get: { trigger[keyPath: keyPath] },
      set: { value in
        var changed = trigger
        changed[keyPath: keyPath] = value
        // Tornare alla combinazione di base cancella la scelta invece di salvarla.
        storedTrigger = changed == .standard ? Data() : ((try? JSONEncoder().encode(changed)) ?? Data())
        onTriggerChange()
      }
    )
  }

  var body: some View {
    Form {
      Section {
        LabeledContent("Tasti da tenere premuti") {
          ShortcutRecorder(shortcut: binding(\.keys))
        }
        Picker("Tasto del mouse", selection: binding(\.mouseButton)) {
          Text("Destro").tag(Int64(1))
          Text("Centrale").tag(Int64(2))
          Text("Laterale indietro").tag(Int64(3))
          Text("Laterale avanti").tag(Int64(4))
          Text("Sinistro").tag(Int64(0))
        }
      } header: {
        Text("Pannello")
      } footer: {
        VStack(alignment: .leading, spacing: 6) {
          Text("Tieni premuti i tasti e fai clic: \(trigger.displayString). Clicca il campo e premi la combinazione; Esc annulla, ⌫ ripristina ⇧.")
          if trigger.mouseButton == 0 {
            Text("Con il clic sinistro i tasti hanno spesso già un significato (⇧ estende la selezione, ⌘ apre in un'altra finestra): quel clic non arriverà più alle app.")
              .foregroundStyle(.orange)
          }
        }
      }

      LanguageSection()
      LoginItemSection(appName: "Orbis Clip")
    }
    .formStyle(.grouped)
    .frame(width: 520)
    .fixedSize(horizontal: false, vertical: true)
  }
}
