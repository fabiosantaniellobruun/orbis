import AppKit
import SwiftUI

/// Il servizio "Aggiungi a Orbis Clip" del menu contestuale, dichiarato in Info.plist: macOS lo
/// propone sui testi selezionati, sui link e sui file nel Finder.
final class ServiceProvider: NSObject {
  var onReceive: ((NSPasteboard) -> Void)?

  @objc func addToOrbisClip(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
    onReceive?(pasteboard)
  }
}

/// La finestra in cui si dà un nome a ciò che si aggiunge, una scorciatoia e se è un preferito.
final class AddItemWindowController {
  private var window: NSWindow?

  func show(_ draft: ClipDraft, onSave: @escaping (ClipItem) -> Void) {
    // Chiusa con il pulsante rosso, la copia resta nella cartella fino al prossimo avvio, che la
    // toglie.
    window?.close()
    let view = AddItemView(
      draft: draft,
      onSave: { [weak self] item in
        onSave(item)
        self?.close()
      },
      onCancel: { [weak self] in
        draft.discard()
        self?.close()
      }
    )
    let window = NSWindow(contentViewController: NSHostingController(rootView: view))
    window.title = "Aggiungi a Orbis Clip"
    window.styleMask = [.titled, .closable]
    window.isReleasedWhenClosed = false
    window.center()
    // Un'app senza icona nel Dock non è mai in primo piano: senza attivarla, la finestra si
    // aprirebbe dietro le altre.
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
    self.window = window
  }

  private func close() {
    window?.close()
    window = nil
  }
}

private struct AddItemView: View {
  let draft: ClipDraft
  var onSave: (ClipItem) -> Void
  var onCancel: () -> Void

  @State private var name: String
  @State private var shortcut = ""
  @State private var isFavorite = true

  init(draft: ClipDraft, onSave: @escaping (ClipItem) -> Void, onCancel: @escaping () -> Void) {
    self.draft = draft
    self.onSave = onSave
    self.onCancel = onCancel
    _name = State(initialValue: draft.suggestedName)
  }

  private var item: ClipItem {
    let name = name.trimmingCharacters(in: .whitespaces)
    let shortcut = shortcut.trimmingCharacters(in: .whitespaces)
    return ClipItem(
      name: name.isEmpty ? draft.suggestedName : name,
      shortcut: shortcut.isEmpty ? nil : shortcut,
      isFavorite: isFavorite,
      content: draft.content
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      ClipCard(item: item)
        .padding(.top, 20)
      Form {
        TextField("Nome", text: $name)
        TextField("Scorciatoia", text: $shortcut, prompt: Text("per esempio lin"))
        Toggle("Tra i preferiti", isOn: $isFavorite)
      }
      .formStyle(.grouped)
      .scrollDisabled(true)
      HStack {
        Spacer()
        Button("Annulla", role: .cancel, action: onCancel)
          .keyboardShortcut(.cancelAction)
        Button("Aggiungi") { onSave(item) }
          .keyboardShortcut(.defaultAction)
      }
      .padding([.horizontal, .bottom], 20)
    }
    .frame(width: 380)
    .fixedSize(horizontal: false, vertical: true)
  }
}
