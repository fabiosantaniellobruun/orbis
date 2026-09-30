import Foundation
import Observation

@Observable
final class RenameModel {
  let sources: [RenameSource]
  var options: RenameOptions

  /// I nomi presenti nelle cartelle di partenza, fotografati all'apertura: l'anteprima si
  /// ricalcola a ogni tasto e non deve rileggere il disco ogni volta.
  private let directoryListings: [String: Set<String>]

  var onApply: (([RenameEntry]) -> Void)?
  var onCancel: (() -> Void)?

  init(urls: [URL]) {
    let sources = urls.map(RenameSource.init(url:))
    self.sources = sources
    self.options = .initial(for: sources)

    var listings: [String: Set<String>] = [:]
    for source in sources where listings[source.directoryKey] == nil {
      let names = (try? FileManager.default.contentsOfDirectory(atPath: source.directoryKey)) ?? []
      listings[source.directoryKey] = Set(names.map(RenamePlan.nameKey))
    }
    self.directoryListings = listings
  }

  var plan: RenamePlan {
    RenamePlan.make(sources: sources, options: options, directoryListings: directoryListings)
  }

  func apply(_ plan: RenamePlan) {
    guard plan.canApply else { return }
    onApply?(plan.entries)
  }
}
