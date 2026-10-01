import AppKit
import SwiftUI

/// Il campo in cui si sceglie la combinazione: si clicca e si preme. Tenendo premuti solo dei
/// modificatori e rilasciandoli si sceglie quella combinazione di modificatori (⇧, ⌥⇧…); premendo
/// un tasto normale, quel tasto con i modificatori eventualmente tenuti. Esc annulla, ⌫ ripristina.
struct ShortcutRecorder: View {
  @Binding var shortcut: TriggerShortcut

  @State private var recorder = ShortcutRecorderState()

  var body: some View {
    HStack(spacing: 8) {
      Button {
        if recorder.isRecording {
          recorder.stop()
        } else {
          recorder.start { shortcut = $0 }
        }
      } label: {
        Text(label)
          .monospacedDigit()
          .frame(minWidth: 130)
      }
      .controlSize(.large)
      .buttonStyle(.bordered)
      // Mentre si sceglie il campo si accende, come un campo di testo in modifica.
      .tint(recorder.isRecording ? Color.accentColor : nil)

      if shortcut != .standard {
        Button("Ripristina") {
          recorder.stop()
          shortcut = .standard
        }
        .buttonStyle(.link)
      }
    }
    .onDisappear { recorder.stop() }
  }

  private var label: String {
    guard recorder.isRecording else { return shortcut.displayString }
    let live = TriggerShortcut(modifiers: recorder.liveModifiers).displayString
    return live.isEmpty ? "Premi la combinazione…" : live
  }
}

@Observable
final class ShortcutRecorderState {
  private(set) var isRecording = false
  /// I modificatori tenuti premuti adesso, per mostrarli mentre si sceglie.
  private(set) var liveModifiers: NSEvent.ModifierFlags = []

  private var peak: NSEvent.ModifierFlags = []
  private var monitor: Any?
  private var onCommit: ((TriggerShortcut) -> Void)?

  func start(onCommit: @escaping (TriggerShortcut) -> Void) {
    stop()
    self.onCommit = onCommit
    isRecording = true
    liveModifiers = []
    peak = []
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
      self?.handle(event)
    }
  }

  func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    isRecording = false
    liveModifiers = []
    peak = []
    onCommit = nil
  }

  /// Gli eventi arrivano alla finestra delle impostazioni: li si prende tutti, così non suonano
  /// e non fanno altro mentre si sceglie.
  private func handle(_ event: NSEvent) -> NSEvent? {
    let flags = event.modifierFlags.intersection(TriggerShortcut.relevantModifiers)

    switch event.type {
    case .flagsChanged:
      liveModifiers = flags
      if flags.isEmpty {
        // Tutti i modificatori sono stati rilasciati senza un tasto: vale quello che si è tenuto.
        if !peak.isEmpty { commit(TriggerShortcut(modifiers: peak)) }
        peak = []
      } else {
        peak.formUnion(flags)
      }

    case .keyDown:
      let plain = flags.subtracting(.function).isEmpty
      if event.keyCode == 53, plain {
        stop()
      } else if event.keyCode == 51, plain {
        commit(.standard)
      } else {
        // "fn" lo accende il sistema da solo con le frecce e i tasti funzione: non è una scelta.
        commit(TriggerShortcut(
          modifiers: flags.subtracting(.function),
          keyCode: event.keyCode,
          keyLabel: KeyNames.label(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers)
        ))
      }

    default:
      return event
    }
    return nil
  }

  private func commit(_ shortcut: TriggerShortcut) {
    let onCommit = self.onCommit
    stop()
    onCommit?(shortcut)
  }
}
