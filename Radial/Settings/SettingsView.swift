import AppKit
import SwiftUI

struct SettingsView: View {
  @State private var favorites: [URL?] = DestinationStore().favoriteSlots
  @State private var recents: [URL] = DestinationStore().recents

  var body: some View {
    Form {
      Section {
        ForEach(0..<DestinationStore.favoriteSlotCount, id: \.self) { slot in
          FavoriteRow(
            slot: slot,
            url: favorites[slot],
            choose: { choose(for: slot) },
            clear: { set(nil, slot: slot) }
          )
          .dropDestination(for: URL.self) { urls, _ in
            guard let folder = urls.first(where: DestinationStore.folderExists) else { return false }
            set(folder, slot: slot)
            return true
          }
        }
      } header: {
        Text("Cartelle preferite")
      } footer: {
        Text("Compaiono nel secondo anello di Sposta, dopo le due cartelle usate più di recente. Puoi anche trascinare una cartella su una riga.")
      }

      Section("Ultime cartelle usate") {
        if recents.isEmpty {
          Text("Nessuna, per ora")
            .foregroundStyle(.secondary)
        } else {
          ForEach(recents, id: \.self) { url in
            FolderLabel(url: url)
          }
          Button("Svuota l'elenco") {
            DestinationStore().clearRecents()
            recents = []
          }
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 540, height: 520)
    // Le recenti cambiano mentre l'app lavora: si rileggono ogni volta che la finestra torna in primo piano.
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
      recents = DestinationStore().recents
    }
  }

  private func set(_ url: URL?, slot: Int) {
    DestinationStore().setFavorite(url, slot: slot)
    favorites = DestinationStore().favoriteSlots
  }

  private func choose(for slot: Int) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "Scegli"
    panel.message = "Scegli una cartella preferita"
    panel.directoryURL = favorites[slot]
    Task {
      guard await panel.begin() == .OK, let url = panel.url else { return }
      set(url, slot: slot)
    }
  }
}

private struct FavoriteRow: View {
  let slot: Int
  let url: URL?
  let choose: () -> Void
  let clear: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Text("\(slot + 1)")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 16)

      if let url {
        FolderLabel(url: url)
      } else {
        Text("Vuota")
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 8)

      Button(url == nil ? "Scegli…" : "Cambia…", action: choose)
      if url != nil {
        Button(action: clear) {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("Svuota questa casella")
      }
    }
  }
}

/// Icona, nome e percorso completo di una cartella. Una cartella sparita si segnala.
private struct FolderLabel: View {
  let url: URL

  private var path: String { url.path(percentEncoded: false) }
  private var exists: Bool { DestinationStore.folderExists(url) }

  var body: some View {
    HStack(spacing: 8) {
      Image(nsImage: NSWorkspace.shared.icon(forFile: path))
        .resizable()
        .frame(width: 26, height: 26)
        .opacity(exists ? 1 : 0.4)

      VStack(alignment: .leading, spacing: 1) {
        Text(FileManager.default.displayName(atPath: path))
          .lineLimit(1)
        Text(exists ? RadialOption.displayPath(url) : "Non trovata · \(RadialOption.displayPath(url))")
          .font(.system(size: 11))
          .foregroundStyle(exists ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
          .lineLimit(1)
          .truncationMode(.middle)
      }
    }
  }
}
