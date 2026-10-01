import Foundation

/// Una voce del menu radiale. Cosa fa sta in `ActionRunner`.
nonisolated struct OrbisAction: Identifiable, Hashable {
  enum ID: String {
    case rename, clone, convert, move, resize, compress, copyPath, trash
  }

  let id: ID
  let title: String
  let symbol: String

  private static let definitions: [ID: OrbisAction] = Dictionary(
    uniqueKeysWithValues: [
      OrbisAction(id: .rename, title: "Rinomina", symbol: "character.cursor.ibeam"),
      OrbisAction(id: .clone, title: "Clona", symbol: "plus.square.on.square"),
      OrbisAction(id: .convert, title: "Converti in", symbol: "arrow.triangle.2.circlepath"),
      OrbisAction(id: .move, title: "Sposta", symbol: "folder"),
      OrbisAction(id: .resize, title: "Ridimensiona", symbol: "arrow.up.left.and.arrow.down.right"),
      OrbisAction(id: .compress, title: "Comprimi", symbol: "archivebox"),
      OrbisAction(id: .copyPath, title: "Copia percorso", symbol: "link"),
      OrbisAction(id: .trash, title: "Cestina", symbol: "trash"),
    ].map { ($0.id, $0) }
  )

  private static func ordered(_ ids: [ID]) -> [OrbisAction] {
    ids.compactMap { definitions[$0] }
  }

  // MARK: Disposizioni

  // Nell'ordine dell'anello, in senso orario dall'alto. Le voci con un secondo anello (Converti in,
  // Sposta) hanno bisogno di posto ai lati per le etichette; Cestina sta lontana da tutte e due,
  // perché non si finisca lì passando.

  /// La disposizione di base: Converti in a destra, Sposta a sinistra.
  static let all = ordered([.rename, .clone, .convert, .copyPath, .trash, .resize, .move, .compress])

  /// Per quando a sinistra non c'è posto: le due voci con secondo anello stanno a destra.
  static let rightHanded = ordered([.rename, .convert, .clone, .move, .resize, .compress, .trash, .copyPath])

  /// Per quando a destra non c'è posto: le due voci con secondo anello stanno a sinistra.
  static let leftHanded = ordered([.rename, .copyPath, .trash, .compress, .resize, .move, .clone, .convert])

  /// La disposizione adatta a dove compare il menu: vicino a un bordo dello schermo le voci con
  /// secondo anello passano dalla parte che ha posto per le etichette, invece di finire fuori
  /// dallo schermo.
  static func layout(roomLeft: CGFloat, roomRight: CGFloat) -> [OrbisAction] {
    let needed = SubRingGeometry.reach
    if roomLeft >= needed && roomRight >= needed { return all }
    return roomRight >= roomLeft ? rightHanded : leftHanded
  }
}
