import Foundation

/// Una voce del menu radiale. Cosa fa sta in `ActionRunner`.
struct RadialAction: Identifiable, Hashable {
  enum ID: String {
    case rename, clone, convert, move, resize, compress, copyPath, trash
  }

  let id: ID
  let title: String
  let symbol: String

  static let all: [RadialAction] = [
    RadialAction(id: .rename, title: "Rinomina", symbol: "character.cursor.ibeam"),
    RadialAction(id: .clone, title: "Clona", symbol: "plus.square.on.square"),
    RadialAction(id: .convert, title: "Converti in", symbol: "arrow.triangle.2.circlepath"),
    RadialAction(id: .move, title: "Sposta", symbol: "folder"),
    RadialAction(id: .resize, title: "Ridimensiona", symbol: "arrow.up.left.and.arrow.down.right"),
    RadialAction(id: .compress, title: "Comprimi", symbol: "archivebox"),
    RadialAction(id: .copyPath, title: "Copia percorso", symbol: "link"),
    RadialAction(id: .trash, title: "Cestina", symbol: "trash"),
  ]
}
