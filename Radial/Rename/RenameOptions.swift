import Foundation

/// Un elemento da rinominare, con nome ed estensione già separati.
nonisolated struct RenameSource: Sendable, Equatable, Identifiable {
  let url: URL
  let stem: String
  let ext: String
  let created: Date?
  let modified: Date?

  var id: URL { url }
  var currentName: String { url.lastPathComponent }

  /// La cartella che contiene l'elemento, come chiave per confrontare i nomi.
  var directoryKey: String {
    url.deletingLastPathComponent().standardizedFileURL.path(percentEncoded: false)
  }

  init(url: URL) {
    let parts = FileOperations.nameParts(of: url)
    let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
    self.init(
      url: url,
      stem: parts.stem,
      ext: parts.extension,
      created: values?.creationDate,
      modified: values?.contentModificationDate
    )
  }

  init(url: URL, stem: String, ext: String, created: Date? = nil, modified: Date? = nil) {
    self.url = url
    self.stem = stem
    self.ext = ext
    self.created = created
    self.modified = modified
  }
}

/// Come comporre i nuovi nomi. L'estensione non viene mai toccata.
nonisolated struct RenameOptions: Sendable, Equatable {
  enum Mode: String, CaseIterable, Identifiable, Sendable {
    case name, replace, add, date

    var id: Self { self }

    var title: String {
      switch self {
      case .name: "Nome"
      case .replace: "Sostituisci"
      case .add: "Aggiungi"
      case .date: "Data"
      }
    }
  }

  /// In che ordine numerare gli elementi.
  enum Order: String, CaseIterable, Identifiable, Sendable {
    case original, name, created, modified

    var id: Self { self }

    var title: String {
      switch self {
      case .original: "Come nel Finder"
      case .name: "Nome"
      case .created: "Data di creazione"
      case .modified: "Data di modifica"
      }
    }
  }

  enum DateSource: String, CaseIterable, Identifiable, Sendable {
    case created, modified, today

    var id: Self { self }

    var title: String {
      switch self {
      case .created: "Creazione"
      case .modified: "Modifica"
      case .today: "Oggi"
      }
    }
  }

  enum DateFormat: String, CaseIterable, Identifiable, Sendable {
    case iso, compact, european, isoTime

    var id: Self { self }

    var pattern: String {
      switch self {
      case .iso: "yyyy-MM-dd"
      case .compact: "yyyyMMdd"
      case .european: "dd-MM-yyyy"
      case .isoTime: "yyyy-MM-dd HH.mm"
      }
    }
  }

  var mode: Mode = .name
  var order: Order = .original

  // Nome
  var baseName = ""
  var addsNumber = true
  var start = 1
  var digits = 2
  var separator = " "
  var numberFirst = false

  // Sostituisci
  var find = ""
  var replacement = ""
  var matchCase = false

  // Aggiungi
  var prefix = ""
  var suffix = ""

  // Data
  var dateSource: DateSource = .created
  var dateFormat: DateFormat = .iso
  var dateFirst = true
  var dateSeparator = " "

  /// Le impostazioni di partenza: per un elemento solo si modifica il suo nome, per più elementi
  /// si numerano tenendo i nomi originali.
  static func initial(for sources: [RenameSource]) -> RenameOptions {
    var options = RenameOptions()
    if sources.count == 1, let only = sources.first {
      options.baseName = only.stem
      options.addsNumber = false
    }
    return options
  }
}
