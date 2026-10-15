import AppKit
import SwiftUI

/// La finestra degli elementi: a sinistra l'elenco, con la ricerca; a destra l'elemento scelto,
/// per cambiarne nome, scorciatoia e preferito, o eliminarlo.
struct LibraryView: View {
  let store: ClipStore
  var addFromClipboard: () -> Void

  @State private var selection: ClipItem.ID?
  @State private var query = ""

  /// Prima i preferiti, poi gli altri; in ciascun gruppo i più recenti in alto.
  private var shownItems: [ClipItem] {
    let sorted = store.items.sorted { lhs, rhs in
      lhs.isFavorite != rhs.isFavorite ? lhs.isFavorite : lhs.addedAt > rhs.addedAt
    }
    guard !query.isEmpty else { return sorted }
    return sorted.filter { $0.score(for: query) > 0 }
  }

  var body: some View {
    NavigationSplitView {
      List(shownItems, selection: $selection) { item in
        LibraryRow(item: item)
      }
      .searchable(text: $query, placement: .sidebar, prompt: "Cerca")
      .navigationSplitViewColumnWidth(min: 220, ideal: 260)
      .overlay {
        if store.items.isEmpty {
          ContentUnavailableView {
            Label("Nessun elemento", systemImage: "paperclip")
          } description: {
            Text("Seleziona un testo, un link o un file e scegli Servizi → Aggiungi a Orbis Clip dal menu contestuale, oppure aggiungi ciò che hai negli appunti.")
          }
        }
      }
    } detail: {
      if let selection, let item = store.item(selection) {
        ItemEditor(store: store, item: item)
          .id(selection)
      } else {
        Text(store.items.isEmpty ? "" : "Scegli un elemento")
          .foregroundStyle(.secondary)
      }
    }
    .toolbar {
      Button("Aggiungi dagli appunti", systemImage: "plus", action: addFromClipboard)
        .help("Aggiungi ciò che c'è negli appunti")
    }
    .onDeleteCommand {
      if let selection { store.remove(selection) }
    }
    .frame(minWidth: 620, minHeight: 420)
    #if DEBUG
    .onAppear {
      // Con `--library` si apre già sul primo elemento, per provare la finestra.
      if CommandLine.arguments.contains("--library") { selection = shownItems.first?.id }
    }
    #endif
  }
}

private struct LibraryRow: View {
  let item: ClipItem

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: symbol)
        .foregroundStyle(.secondary)
        .frame(width: 18)
      Text(item.name)
        .lineLimit(1)
      Spacer(minLength: 4)
      if let shortcut = item.shortcut {
        Text(shortcut)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
      }
      if item.isFavorite {
        Image(systemName: "star.fill")
          .font(.caption)
          .foregroundStyle(.yellow)
      }
    }
  }

  private var symbol: String {
    switch item.content {
    case .text: "text.alignleft"
    case .link: "link"
    case .image: "photo"
    case .file: "doc"
    case .password: "key"
    }
  }
}

/// Le modifiche si salvano mentre si scrive, come nelle impostazioni di sistema.
private struct ItemEditor: View {
  let store: ClipStore
  @State var item: ClipItem
  @State private var isConfirmingDelete = false

  var body: some View {
    Form {
      Section {
        ClipCard(item: item)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 6)
      }
      Section {
        TextField("Nome", text: $item.name)
        TextField("Scorciatoia", text: shortcut, prompt: Text("per esempio lin"))
        Toggle("Tra i preferiti", isOn: $item.isFavorite)
      } footer: {
        Text("Nel pannello compaiono gli ultimi \(ClipStore.favoriteCount) preferiti aggiunti. La scorciatoia si scrive nella ricerca e porta l'elemento al primo posto.")
          .foregroundStyle(.secondary)
      }
      Section("Contenuto") {
        ContentDetail(item: $item)
      }
      Section {
        Button("Elimina elemento", role: .destructive) { isConfirmingDelete = true }
      }
    }
    .formStyle(.grouped)
    .onChange(of: item) { store.update(item) }
    .confirmationDialog("Eliminare «\(item.name)»?", isPresented: $isConfirmingDelete) {
      Button("Elimina", role: .destructive) { store.remove(item.id) }
    }
  }

  private var shortcut: Binding<String> {
    Binding(
      get: { item.shortcut ?? "" },
      set: { item.shortcut = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
    )
  }
}

private struct ContentDetail: View {
  @Binding var item: ClipItem

  var body: some View {
    switch item.content {
    case .text(let text, let rtf):
      if rtf == nil {
        // Il testo semplice si può correggere; quello formattato no, perché la formattazione
        // andrebbe persa.
        TextEditor(text: Binding(get: { text }, set: { item.content = .text($0, rtf: nil) }))
          .font(.body)
          .frame(minHeight: 80)
      } else {
        Text(text)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text("Testo formattato: si incolla con la sua formattazione.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    case .link(let url):
      LabeledContent("Indirizzo") {
        Link(url.absoluteString, destination: url)
          .lineLimit(1)
          .truncationMode(.middle)
      }
    case .image(let blob), .file(let blob):
      LabeledContent("File", value: blob.name)
      LabeledContent("Dimensione", value: ByteCountFormatter.string(
        fromByteCount: Int64(ClipStorage.size(of: blob.url)), countStyle: .file
      ))
      Button("Mostra nel Finder") {
        NSWorkspace.shared.activateFileViewerSelecting([blob.url])
      }
    case .password:
      Text("Le password arriveranno con il Portachiavi.")
        .foregroundStyle(.secondary)
    }
  }
}
