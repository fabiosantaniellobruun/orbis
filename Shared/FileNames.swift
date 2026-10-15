import Foundation

/// Nomi di file che non sovrascrivono mai niente, come "Mantieni entrambi" del Finder.
nonisolated enum FileNames {
  /// Il primo nome libero nella cartella: "stem.ext", poi "stem 2.ext", "stem 3.ext"…
  static func availableURL(in directory: URL, stem: String, extension ext: String) -> URL {
    func candidate(_ number: Int) -> URL {
      let name = number == 1 ? stem : "\(stem) \(number)"
      let url = directory.appendingPathComponent(name)
      return ext.isEmpty ? url : url.appendingPathExtension(ext)
    }
    var number = 1
    while FileManager.default.fileExists(atPath: candidate(number).path(percentEncoded: false)) {
      number += 1
    }
    return candidate(number)
  }

  /// Nome ed estensione. Per le cartelle il punto fa parte del nome: "Progetto v1.2" non ha
  /// estensione. I pacchetti (come le app) si comportano invece come file.
  static func nameParts(of url: URL) -> (stem: String, extension: String) {
    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
    if values?.isDirectory == true, values?.isPackage != true {
      return (url.lastPathComponent, "")
    }
    return (url.deletingPathExtension().lastPathComponent, url.pathExtension)
  }
}
