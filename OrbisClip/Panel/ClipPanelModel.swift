import Foundation
import Observation

/// Lo stato del pannello aperto: cosa mostra, la ricerca, la scelta da tastiera e dove sta il
/// puntatore.
@Observable final class ClipPanelModel {
  /// Da che parte del puntatore si aprono gli elementi: a destra, o a sinistra se a destra non
  /// c'è posto.
  enum Side { case right, left }

  struct Section: Identifiable {
    let id: String
    let title: String
    let items: [ClipItem]
  }

  let store: ClipStore
  var query = ""
  var selectedID: ClipItem.ID?
  private(set) var side = Side.right
  /// L'altezza del puntatore nel pannello, dall'alto.
  private(set) var anchorY: CGFloat = 0
  private(set) var size = CGSize(width: 300, height: 640)
  /// Diventa `true` subito dopo l'apertura, per far entrare le schede una dopo l'altra.
  var hasAppeared = false

  init(store: ClipStore) {
    self.store = store
  }

  var isSearching: Bool { !query.isEmpty }

  var sections: [Section] {
    if isSearching {
      return [Section(id: "results", title: String(localized: "Risultati"), items: store.results(for: query))]
    }
    return [
      Section(id: "favorites", title: String(localized: "Preferiti"), items: store.favorites),
      Section(id: "recents", title: String(localized: "Usati di recente"), items: store.recents),
    ].filter { !$0.items.isEmpty }
  }

  var visibleItems: [ClipItem] { sections.flatMap(\.items) }

  /// L'elemento che Invio sceglie. Mentre si cerca è il primo risultato, finché non se ne sceglie
  /// un altro con le frecce o il puntatore.
  var selectedItem: ClipItem? {
    let items = visibleItems
    if let selectedID, let item = items.first(where: { $0.id == selectedID }) { return item }
    return isSearching ? items.first : nil
  }

  func moveSelection(by delta: Int) {
    let items = visibleItems
    guard !items.isEmpty else { return }
    let current = selectedItem.flatMap { item in items.firstIndex { $0.id == item.id } }
    let next = current.map { $0 + delta } ?? (delta > 0 ? 0 : items.count - 1)
    selectedID = items[min(max(next, 0), items.count - 1)].id
  }

  func reset(side: Side, anchorY: CGFloat, size: CGSize) {
    self.side = side
    self.anchorY = anchorY
    self.size = size
    query = ""
    selectedID = nil
    hasAppeared = false
  }
}
