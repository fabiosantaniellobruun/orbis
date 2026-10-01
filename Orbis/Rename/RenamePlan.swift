import Foundation

nonisolated enum RenameProblem: Sendable, Equatable {
  case empty
  case invalidCharacters
  case tooLong
  case duplicate
  case alreadyExists

  var message: String {
    switch self {
    case .empty: "Il nome è vuoto"
    case .invalidCharacters: "Contiene caratteri non validi (/ o :)"
    case .tooLong: "Il nome è troppo lungo"
    case .duplicate: "Due elementi avrebbero lo stesso nome"
    case .alreadyExists: "Esiste già un elemento con questo nome"
    }
  }
}

/// Il risultato di applicare le opzioni agli elementi: un nuovo nome per ognuno, con l'eventuale
/// problema che ne impedirebbe l'uso. Non tocca il disco: si può ricalcolare a ogni tasto.
nonisolated struct RenamePlan: Sendable, Equatable {
  struct Row: Sendable, Equatable, Identifiable {
    enum Status: Sendable, Equatable {
      case ready
      case unchanged
      case problem(RenameProblem)
    }

    let source: RenameSource
    let newName: String
    let status: Status

    var id: URL { source.id }
  }

  let rows: [Row]

  var pending: [Row] { rows.filter { $0.status == .ready } }

  var problemCount: Int {
    rows.count { if case .problem = $0.status { true } else { false } }
  }

  var canApply: Bool { problemCount == 0 && !pending.isEmpty }

  var entries: [RenameEntry] {
    pending.map { RenameEntry(source: $0.source.url, newName: $0.newName) }
  }

  /// - Parameter directoryListings: i nomi presenti in ogni cartella (chiave: `directoryKey`),
  ///   già normalizzati con `nameKey`, per accorgersi di chi occuperebbe un nome esistente.
  static func make(
    sources: [RenameSource],
    options: RenameOptions,
    directoryListings: [String: Set<String>],
    now: Date = .now
  ) -> RenamePlan {
    let numbersItems = options.mode == .name && options.addsNumber
    let ordered = numbersItems ? sorted(sources, by: options.order) : sources
    let names = ordered.enumerated().map { index, source in
      fullName(for: source, index: index, options: options, now: now)
    }

    // Chi cambia nome libera il vecchio: quel nome si può riusare, anche da un altro elemento.
    let sourceKeys = Set(sources.map { key(directory: $0.directoryKey, name: $0.currentName) })
    var uses: [String: Int] = [:]
    for (source, name) in zip(ordered, names) {
      uses[key(directory: source.directoryKey, name: name), default: 0] += 1
    }

    let rows = zip(ordered, names).map { source, name -> Row in
      let targetKey = key(directory: source.directoryKey, name: name)
      let ownKey = key(directory: source.directoryKey, name: source.currentName)

      let status: Row.Status
      if let problem = validate(name) {
        status = .problem(problem)
      } else if uses[targetKey, default: 0] > 1 {
        status = .problem(.duplicate)
      } else if name == source.currentName {
        status = .unchanged
      } else if targetKey != ownKey,
                !sourceKeys.contains(targetKey),
                directoryListings[source.directoryKey]?.contains(nameKey(name)) == true {
        status = .problem(.alreadyExists)
      } else {
        status = .ready
      }
      return Row(source: source, newName: name, status: status)
    }
    return RenamePlan(rows: rows)
  }

  /// Un nome come lo confronta il disco: senza differenza di maiuscole né di accenti composti.
  static func nameKey(_ name: String) -> String {
    name.precomposedStringWithCanonicalMapping.lowercased()
  }

  // MARK: Nomi

  private static func fullName(for source: RenameSource, index: Int, options: RenameOptions, now: Date) -> String {
    let stem = newStem(for: source, index: index, options: options, now: now)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    // Senza un nome, con la sola estensione uscirebbe un file nascosto: lo si segnala come vuoto.
    guard !stem.isEmpty else { return "" }
    return source.ext.isEmpty ? stem : "\(stem).\(source.ext)"
  }

  private static func newStem(for source: RenameSource, index: Int, options: RenameOptions, now: Date) -> String {
    switch options.mode {
    case .name:
      let base = options.baseName.isEmpty ? source.stem : options.baseName
      guard options.addsNumber else { return base }
      let number = String(options.start + index)
      let padded = String(repeating: "0", count: max(0, options.digits - number.count)) + number
      return options.numberFirst
        ? padded + options.separator + base
        : base + options.separator + padded

    case .replace:
      guard !options.find.isEmpty else { return source.stem }
      return source.stem.replacingOccurrences(
        of: options.find,
        with: options.replacement,
        options: options.matchCase ? [] : [.caseInsensitive]
      )

    case .add:
      return options.prefix + source.stem + options.suffix

    case .date:
      let date: Date = switch options.dateSource {
      case .created: source.created ?? now
      case .modified: source.modified ?? now
      case .today: now
      }
      let text = formatted(date, as: options.dateFormat)
      return options.dateFirst
        ? text + options.dateSeparator + source.stem
        : source.stem + options.dateSeparator + text
    }
  }

  private static func formatted(_ date: Date, as format: RenameOptions.DateFormat) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = format.pattern
    return formatter.string(from: date)
  }

  private static func sorted(_ sources: [RenameSource], by order: RenameOptions.Order) -> [RenameSource] {
    let indexed = Array(sources.enumerated())
    let byName: (RenameSource, RenameSource) -> ComparisonResult = {
      $0.currentName.localizedStandardCompare($1.currentName)
    }
    let byDate: (KeyPath<RenameSource, Date?>) -> (RenameSource, RenameSource) -> ComparisonResult = { keyPath in
      { left, right in
        switch (left[keyPath: keyPath], right[keyPath: keyPath]) {
        case let (l?, r?): l.compare(r)
        case (nil, _?): .orderedDescending
        case (_?, nil): .orderedAscending
        case (nil, nil): .orderedSame
        }
      }
    }

    let compare: ((RenameSource, RenameSource) -> ComparisonResult)? = switch order {
    case .original: nil
    case .name: byName
    case .created: byDate(\.created)
    case .modified: byDate(\.modified)
    }
    guard let compare else { return sources }

    // A parità di criterio resta l'ordine di partenza.
    return indexed.sorted { left, right in
      let result = compare(left.element, right.element)
      return result == .orderedSame ? left.offset < right.offset : result == .orderedAscending
    }.map(\.element)
  }

  private static func validate(_ name: String) -> RenameProblem? {
    if name.isEmpty { return .empty }
    if name.contains(where: { $0 == "/" || $0 == ":" || $0 == "\0" }) || name == "." || name == ".." {
      return .invalidCharacters
    }
    if name.utf8.count > 255 { return .tooLong }
    return nil
  }

  // MARK: Chiavi

  private static func key(directory: String, name: String) -> String {
    directory + "\u{0}" + nameKey(name)
  }
}
