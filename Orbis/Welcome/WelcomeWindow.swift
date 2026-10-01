import AppKit
import SwiftUI

/// La finestra che spiega come si usa Orbis. Compare al primo avvio e si riapre dal menu:
/// l'app non ha icona nel Dock, quindi senza una spiegazione chi la apre la prima volta non
/// saprebbe che è partita né cosa fare.
final class WelcomeWindowController {
  private static let shownKey = "didShowWelcome"

  private var window: NSWindow?

  /// Si mostra da sola una volta sola, al primo avvio.
  var isFirstLaunch: Bool {
    !UserDefaults.standard.bool(forKey: Self.shownKey)
  }

  func show() {
    UserDefaults.standard.set(true, forKey: Self.shownKey)

    if let window {
      NSApp.activate()
      window.makeKeyAndOrderFront(nil)
      return
    }

    let hostingView = NSHostingView(rootView: WelcomeView(
      close: { [weak self] in self?.window?.close() },
      openSettings: { [weak self] in
        self?.window?.close()
        NSApp.activate()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
      }
    ))
    // Alta quanto il contenuto: con un'altezza fissa i testi lunghi si troncano.
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    window.contentView = hostingView
    window.center()
    self.window = window

    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
  }
}

private struct WelcomeView: View {
  let close: () -> Void
  let openSettings: () -> Void

  @AppStorage(TriggerShortcut.storageKey) private var storedShortcut = Data()

  private var shortcut: TriggerShortcut {
    (try? JSONDecoder().decode(TriggerShortcut.self, from: storedShortcut)) ?? .standard
  }

  var body: some View {
    VStack(spacing: 22) {
      VStack(spacing: 10) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .frame(width: 84, height: 84)
        Text("Benvenuto in Orbis")
          .font(.system(size: 24, weight: .semibold))
        Text("Azioni rapide sui file, con un gesto solo.")
          .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 16) {
        Step(number: 1, title: "Trascina dei file", detail: "Uno o più, dal Finder o dalla Scrivania. Tieni premuto il mouse.")
        Step(
          number: 2,
          title: "Tieni premuto \(shortcut.displayString)",
          detail: "Attorno al puntatore compare un anello di bottoni. Lo cambi nelle impostazioni."
        )
        Step(number: 3, title: "Rilascia su un'azione", detail: "Rinomina, Clona, Sposta, Converti, Comprimi… Su Sposta e Converti in si apre un secondo anello; per i video, Converti in propone il GIF.")
      }

      Label {
        Text("Orbis vive nella barra dei menu, in alto a destra. Non chiede nessun permesso, non usa la rete e non legge i tuoi file finché non rilasci qualcosa su un'azione.")
          .fixedSize(horizontal: false, vertical: true)
      } icon: {
        Image(systemName: "lock.shield")
      }
      .font(.system(size: 12))
      .foregroundStyle(.secondary)
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

      HStack {
        Button("Impostazioni…", action: openSettings)
        Spacer()
        Button("Ho capito", action: close)
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
      }
      .controlSize(.large)
    }
    .padding(.horizontal, 32)
    .padding(.top, 36)
    .padding(.bottom, 24)
    .frame(width: 480)
  }
}

private struct Step: View {
  let number: Int
  let title: String
  let detail: String

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Text("\(number)")
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .frame(width: 26, height: 26)
        .background(Color.accentColor.opacity(0.18), in: Circle())
        .foregroundStyle(Color.accentColor)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 14, weight: .semibold))
        Text(detail)
          .font(.system(size: 12.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}
