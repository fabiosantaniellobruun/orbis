import Foundation
import Testing
@testable import Orbis

struct RenamePlanTests {
  static let folder = URL(filePath: "/tmp/prova", directoryHint: .isDirectory)

  func source(_ name: String, created: Date? = nil, modified: Date? = nil) -> RenameSource {
    let url = Self.folder.appendingPathComponent(name)
    let stem: String
    let ext: String
    if let dot = name.lastIndex(of: "."), dot != name.startIndex {
      stem = String(name[..<dot])
      ext = String(name[name.index(after: dot)...])
    } else {
      stem = name
      ext = ""
    }
    return RenameSource(url: url, stem: stem, ext: ext, created: created, modified: modified)
  }

  /// I nomi finali, nell'ordine dell'anteprima.
  func names(
    _ sources: [RenameSource],
    _ options: RenameOptions,
    existing: [String] = [],
    now: Date = Date(timeIntervalSince1970: 0)
  ) -> [String] {
    plan(sources, options, existing: existing, now: now).rows.map(\.newName)
  }

  func plan(
    _ sources: [RenameSource],
    _ options: RenameOptions,
    existing: [String] = [],
    now: Date = Date(timeIntervalSince1970: 0)
  ) -> RenamePlan {
    let listing = Set((sources.map(\.currentName) + existing).map(RenamePlan.nameKey))
    return RenamePlan.make(
      sources: sources,
      options: options,
      directoryListings: [Self.folder.standardizedFileURL.path(percentEncoded: false): listing],
      now: now
    )
  }

  func date(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso + "T12:00:00Z")!
  }

  // MARK: Nome e numero

  @Test("Con un nome base i file si numerano, con zeri a sinistra")
  func numbersWithBaseName() {
    var options = RenameOptions()
    options.baseName = "Vacanza"
    options.digits = 2

    let result = names([source("a.jpg"), source("b.jpg"), source("c.png")], options)

    #expect(result == ["Vacanza 01.jpg", "Vacanza 02.jpg", "Vacanza 03.png"])
  }

  @Test("Senza nome base restano i nomi originali, con il numero accanto")
  func numbersKeepOriginalNames() {
    var options = RenameOptions()
    options.start = 5
    options.digits = 1
    options.separator = "_"

    let result = names([source("uno.txt"), source("due.txt")], options)

    #expect(result == ["uno_5.txt", "due_6.txt"])
  }

  @Test("Il numero può andare davanti al nome")
  func numberFirst() {
    var options = RenameOptions()
    options.baseName = "Foto"
    options.numberFirst = true
    options.separator = "-"

    #expect(names([source("a.jpg"), source("b.jpg")], options) == ["01-Foto.jpg", "02-Foto.jpg"])
  }

  @Test("Le cifre non troncano i numeri più lunghi")
  func digitsDoNotTruncate() {
    var options = RenameOptions()
    options.baseName = "x"
    options.start = 99
    options.digits = 2

    #expect(names([source("a.txt"), source("b.txt")], options) == ["x 99.txt", "x 100.txt"])
  }

  @Test("Un elemento solo, senza numero, prende il nome scelto")
  func singleItemWithoutNumber() {
    var options = RenameOptions()
    options.baseName = "Nuovo"
    options.addsNumber = false

    #expect(names([source("vecchio.pdf")], options) == ["Nuovo.pdf"])
  }

  @Test("Le impostazioni di partenza per un elemento solo mostrano il suo nome")
  func initialOptionsForSingleItem() {
    let options = RenameOptions.initial(for: [source("relazione.docx")])

    #expect(options.baseName == "relazione")
    #expect(options.addsNumber == false)
  }

  @Test("Le impostazioni di partenza per più elementi numerano")
  func initialOptionsForSeveralItems() {
    let options = RenameOptions.initial(for: [source("a.txt"), source("b.txt")])

    #expect(options.baseName.isEmpty)
    #expect(options.addsNumber)
  }

  @Test("L'ordine per nome è quello naturale: 2 viene prima di 10")
  func orderByNameIsNatural() {
    var options = RenameOptions()
    options.baseName = "Foto"
    options.order = .name

    let result = plan([source("img10.jpg"), source("img2.jpg"), source("img1.jpg")], options)

    #expect(result.rows.map(\.source.currentName) == ["img1.jpg", "img2.jpg", "img10.jpg"])
    #expect(result.rows.map(\.newName) == ["Foto 01.jpg", "Foto 02.jpg", "Foto 03.jpg"])
  }

  @Test("L'ordine per data di creazione mette prima i più vecchi, e senza data per ultimi")
  func orderByCreationDate() {
    var options = RenameOptions()
    options.baseName = "Foto"
    options.order = .created

    let result = plan([
      source("nuovo.jpg", created: date("2026-03-01")),
      source("senza.jpg"),
      source("vecchio.jpg", created: date("2024-01-01")),
    ], options)

    #expect(result.rows.map(\.source.currentName) == ["vecchio.jpg", "nuovo.jpg", "senza.jpg"])
  }

  @Test("Con la stessa data resta l'ordine di partenza")
  func orderIsStable() {
    var options = RenameOptions()
    options.baseName = "Foto"
    options.order = .modified

    let same = date("2025-05-05")
    let result = plan([
      source("c.jpg", modified: same), source("a.jpg", modified: same), source("b.jpg", modified: same),
    ], options)

    #expect(result.rows.map(\.source.currentName) == ["c.jpg", "a.jpg", "b.jpg"])
  }

  @Test("L'ordine vale solo quando si numera")
  func orderIgnoredWithoutNumbers() {
    var options = RenameOptions()
    options.mode = .add
    options.suffix = "!"
    options.order = .name

    let result = plan([source("b.txt"), source("a.txt")], options)

    #expect(result.rows.map(\.source.currentName) == ["b.txt", "a.txt"])
  }

  // MARK: Sostituisci

  @Test("Sostituisci cambia il nome e lascia stare l'estensione")
  func replaceLeavesExtension() {
    var options = RenameOptions()
    options.mode = .replace
    options.find = "txt"
    options.replacement = "doc"

    #expect(names([source("txt-prova.txt")], options) == ["doc-prova.txt"])
  }

  @Test("Sostituisci ignora le maiuscole, salvo richiesta")
  func replaceCaseSensitivity() {
    var options = RenameOptions()
    options.mode = .replace
    options.find = "foto"
    options.replacement = "Immagine"

    #expect(names([source("FOTO 1.jpg")], options) == ["Immagine 1.jpg"])

    options.matchCase = true
    #expect(plan([source("FOTO 1.jpg")], options).rows.first?.status == .unchanged)
  }

  @Test("Sostituire con niente toglie il testo")
  func replaceWithNothing() {
    var options = RenameOptions()
    options.mode = .replace
    options.find = " copia"

    #expect(names([source("foto copia.jpg")], options, existing: []) == ["foto.jpg"])
  }

  @Test("Senza niente da cercare non cambia nulla")
  func replaceWithEmptyFind() {
    var options = RenameOptions()
    options.mode = .replace

    let result = plan([source("a.txt"), source("b.txt")], options)

    #expect(result.rows.allSatisfy { $0.status == .unchanged })
    #expect(!result.canApply)
  }

  // MARK: Aggiungi

  @Test("Aggiungi mette testo prima e dopo il nome, prima dell'estensione")
  func addPrefixAndSuffix() {
    var options = RenameOptions()
    options.mode = .add
    options.prefix = "2026 - "
    options.suffix = " (finale)"

    #expect(names([source("relazione.pdf")], options) == ["2026 - relazione (finale).pdf"])
  }

  // MARK: Data

  @Test("La data di creazione va davanti al nome")
  func dateFromCreation() {
    var options = RenameOptions()
    options.mode = .date

    let result = names([source("foto.jpg", created: date("2025-12-31"))], options)

    #expect(result == ["2025-12-31 foto.jpg"])
  }

  @Test("La data può stare dopo il nome, con un altro formato e separatore")
  func dateAfterWithOtherFormat() {
    var options = RenameOptions()
    options.mode = .date
    options.dateSource = .modified
    options.dateFormat = .european
    options.dateFirst = false
    options.dateSeparator = "_"

    let result = names([source("foto.jpg", modified: date("2025-12-31"))], options)

    #expect(result == ["foto_31-12-2025.jpg"])
  }

  @Test("Oggi usa la data del momento, uguale per tutti")
  func dateToday() {
    var options = RenameOptions()
    options.mode = .date
    options.dateSource = .today
    options.dateFormat = .compact

    let result = names([source("a.txt"), source("b.txt")], options, now: date("2026-09-30"))

    #expect(result == ["20260930 a.txt", "20260930 b.txt"])
  }

  // MARK: Estensioni e cartelle

  @Test("Un file senza estensione resta senza")
  func noExtension() {
    var options = RenameOptions()
    options.mode = .add
    options.suffix = "2"

    #expect(names([source("Makefile")], options) == ["Makefile2"])
  }

  @Test("Un file nascosto senza altro nome non perde il punto")
  func hiddenFile() {
    var options = RenameOptions()
    options.mode = .add
    options.suffix = "-old"

    #expect(names([source(".gitignore")], options) == [".gitignore-old"])
  }

  // MARK: Problemi

  @Test("Un nome vuoto è un problema e non un file nascosto")
  func emptyName() {
    var options = RenameOptions()
    options.baseName = "   "
    options.addsNumber = false

    let result = plan([source("a.txt")], options)

    #expect(result.rows.first?.status == .problem(.empty))
    #expect(!result.canApply)
  }

  @Test("Barra e due punti non sono ammessi", arguments: ["a/b", "a:b"])
  func invalidCharacters(name: String) {
    var options = RenameOptions()
    options.baseName = name
    options.addsNumber = false

    #expect(plan([source("x.txt")], options).rows.first?.status == .problem(.invalidCharacters))
  }

  @Test("Un nome oltre i 255 byte è troppo lungo")
  func tooLong() {
    var options = RenameOptions()
    options.baseName = String(repeating: "a", count: 300)
    options.addsNumber = false

    #expect(plan([source("x.txt")], options).rows.first?.status == .problem(.tooLong))
  }

  @Test("Due elementi con lo stesso nome finale sono segnalati entrambi")
  func duplicates() {
    var options = RenameOptions()
    options.baseName = "Uguale"
    options.addsNumber = false

    let result = plan([source("a.txt"), source("b.txt")], options)

    #expect(result.rows.map(\.status) == [.problem(.duplicate), .problem(.duplicate)])
    #expect(result.problemCount == 2)
  }

  @Test("Le maiuscole non bastano a distinguere due nomi")
  func duplicatesIgnoreCase() {
    var options = RenameOptions()
    options.mode = .replace
    options.find = "x"
    options.replacement = "A"

    let result = plan([source("xa.txt"), source("Aa.txt")], options)

    #expect(result.problemCount == 2)
  }

  @Test("Un nome già occupato da un altro elemento è un problema")
  func alreadyExists() {
    var options = RenameOptions()
    options.baseName = "esistente"
    options.addsNumber = false

    let result = plan([source("a.txt")], options, existing: ["esistente.txt"])

    #expect(result.rows.first?.status == .problem(.alreadyExists))
  }

  @Test("Occupare il nome di un elemento del gruppo che se ne va non è un problema")
  func nameFreedByAnotherItem() {
    var options = RenameOptions()
    options.baseName = "f"
    options.start = 1
    options.digits = 1
    options.separator = ""

    // f1 → f2, f2 → f3: ogni nome nuovo è il vecchio nome di un altro.
    let result = plan([source("f1.txt"), source("f2.txt")], options)

    #expect(result.rows.map(\.newName) == ["f1.txt", "f2.txt"])
    #expect(result.rows.allSatisfy { $0.status == .unchanged })

    options.start = 2
    let shifted = plan([source("f1.txt"), source("f2.txt")], options)
    #expect(shifted.rows.map(\.newName) == ["f2.txt", "f3.txt"])
    #expect(shifted.canApply)
  }

  @Test("Cambiare solo le maiuscole non è un conflitto con sé stessi")
  func caseOnlyChange() {
    var options = RenameOptions()
    options.baseName = "FOTO"
    options.addsNumber = false

    let result = plan([source("foto.jpg")], options)

    #expect(result.rows.first?.newName == "FOTO.jpg")
    #expect(result.rows.first?.status == .ready)
  }

  @Test("Chi non cambia è segnato come invariato e non finisce tra i rinomini")
  func unchangedRowsAreSkipped() {
    var options = RenameOptions()
    options.mode = .replace
    options.find = "vecchio"
    options.replacement = "nuovo"

    let result = plan([source("vecchio.txt"), source("altro.txt")], options)

    #expect(result.rows.map(\.status) == [.ready, .unchanged])
    #expect(result.entries.map(\.newName) == ["nuovo.txt"])
    #expect(result.canApply)
  }

  @Test("Un solo problema blocca tutto")
  func oneProblemBlocksApply() {
    var options = RenameOptions()
    options.mode = .replace
    options.find = "a"
    options.replacement = "/"

    let result = plan([source("ab.txt"), source("cd.txt")], options)

    #expect(result.problemCount == 1)
    #expect(!result.canApply)
  }
}
