import AppKit
import ApplicationServices

/// Dove si incollerà: il punto del clic e che cosa c'era sotto, letto con le API di accessibilità.
struct PasteTarget {
  enum Kind: Equatable {
    /// Un campo di una riga: accetta solo testo, quindi di immagini e file si incolla il nome.
    case singleLineText
    /// Un'area di testo, anche di una pagina web: può accettare immagini e file.
    case richText
    /// Il Finder: l'elemento diventa un file sulla scrivania o nella cartella della finestra.
    case finder(desktop: Bool)
    /// Non un campo di testo: l'elemento finisce negli appunti.
    case other
  }

  /// In coordinate globali con l'origine in alto a sinistra.
  var point: CGPoint
  var kind: Kind
  /// Per il registro: il ruolo dell'elemento e l'app.
  var description: String
  var app: NSRunningApplication?

  /// Si chiama due volte: all'apertura del pannello, che chiede anche alle app basate su Chromium
  /// di pubblicare i loro campi, e di nuovo al momento di incollare, quando lo hanno fatto.
  static func inspect(at point: CGPoint) -> PasteTarget {
    guard let (pid, isDesktop) = windowOwner(at: point) else {
      return PasteTarget(point: point, kind: .other, description: "nessuna finestra", app: nil)
    }
    let app = NSRunningApplication(processIdentifier: pid)
    let appElement = AXUIElementCreateApplication(pid)
    // Un'app bloccata non deve bloccare il pannello.
    AXUIElementSetMessagingTimeout(appElement, 0.3)
    exposeWebContent(of: appElement, app: app)

    var found: AXUIElement?
    var element: AXUIElement?
    if AXUIElementCopyElementAtPosition(appElement, Float(point.x), Float(point.y), &found) == .success {
      element = found
    }
    let bundle = app?.bundleIdentifier ?? "pid \(pid)"

    if let element {
      if kind(of: element) != .other {
        return PasteTarget(point: point, kind: kind(of: element), description: "\(element.roleDescription) in \(bundle)", app: app)
      }
      if let editable = editableElement(near: element) {
        return PasteTarget(point: point, kind: kind(of: editable), description: "\(editable.roleDescription) vicino a \(element.roleDescription) in \(bundle)", app: app)
      }
    }
    // Se il campo sotto il clic ha già il focus (ci si stava scrivendo), lo dice l'app.
    if let focused = appElement.focusedElement, kind(of: focused) != .other, focused.frame?.contains(point) == true {
      return PasteTarget(point: point, kind: kind(of: focused), description: "\(focused.roleDescription) con il focus in \(bundle)", app: app)
    }
    // Nel Finder un campo di testo (rinomina, ricerca) resta un campo; tutto il resto è una cartella.
    let kind: Kind = bundle == "com.apple.finder" ? .finder(desktop: isDesktop) : .other
    return PasteTarget(point: point, kind: kind, description: "\(element?.roleDescription ?? "?") in \(bundle)", app: app)
  }

  private static func kind(of element: AXUIElement) -> Kind {
    switch element.string("AXRole") {
    case "AXTextField", "AXComboBox", "AXSearchField":
      return .singleLineText
    case "AXTextArea":
      return .richText
    default:
      // In una pagina web il clic cade spesso su un elemento dentro il campo modificabile.
      return element.attribute("AXEditableAncestor") != nil ? .richText : .other
    }
  }

  /// Il clic non sempre cade sul campo: sotto l'ultima riga di un testo corto cade sul contenitore
  /// che scorre (un `AXScrollArea` con dentro il testo), su un'etichetta dentro il campo, o su un
  /// gruppo che lo contiene. Si guarda dentro il contenitore e poi qualche livello più su.
  private static func editableElement(near element: AXUIElement) -> AXUIElement? {
    if element.string("AXRole") == "AXScrollArea",
       let child = element.children.first(where: { kind(of: $0) != .other }) {
      return child
    }
    var current = element.parent
    for _ in 0..<4 {
      guard let ancestor = current else { return nil }
      if kind(of: ancestor) != .other { return ancestor }
      current = ancestor.parent
    }
    return nil
  }

  /// Chrome, Edge, Brave, Arc e le app Electron (Slack, VS Code, Claude…) pubblicano i campi delle
  /// loro pagine solo se qualcuno lo chiede: Electron con `AXManualAccessibility`, i browser con
  /// `AXEnhancedUserInterface`. Il secondo cambia anche il comportamento di alcune app native
  /// (le finestre si animano diversamente), quindi solo per i browser basati su Chromium.
  private static func exposeWebContent(of appElement: AXUIElement, app: NSRunningApplication?) {
    AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    let bundle = app?.bundleIdentifier?.lowercased() ?? ""
    let chromium = ["com.google.chrome", "org.chromium", "com.microsoft.edgemac", "com.brave.browser",
                    "company.thebrowser", "com.vivaldi", "com.operasoftware"]
    if chromium.contains(where: bundle.hasPrefix) {
      AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }
  }

  /// L'app della finestra più in alto sotto il punto, senza contare Orbis Clip, o il Finder se sotto
  /// c'è la scrivania. Nomi e contenuto delle finestre richiederebbero un permesso; proprietario e
  /// posizione no.
  private static func windowOwner(at point: CGPoint) -> (pid: pid_t, isDesktop: Bool)? {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
    let me = ProcessInfo.processInfo.processIdentifier
    for window in windows {
      guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != me,
            // Le finestre normali e quelle fluttuanti, non barra dei menu, Dock o finestre invisibili.
            (window[kCGWindowLayer as String] as? Int ?? 0) <= 8,
            (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
            let bounds = window[kCGWindowBounds as String] as? NSDictionary,
            let rect = CGRect(dictionaryRepresentation: bounds),
            rect.contains(point)
      else { continue }
      return (pid, false)
    }
    let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
    return finder.map { ($0.processIdentifier, true) }
  }
}

private extension AXUIElement {
  func attribute(_ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success ? value : nil
  }

  func string(_ name: String) -> String? {
    attribute(name) as? String
  }

  func element(_ name: String) -> AXUIElement? {
    guard let value = attribute(name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
  }

  var parent: AXUIElement? { element("AXParent") }
  var focusedElement: AXUIElement? { element("AXFocusedUIElement") }

  var children: [AXUIElement] {
    attribute("AXChildren") as? [AXUIElement] ?? []
  }

  var roleDescription: String {
    [string("AXRole"), string("AXSubrole")].compactMap(\.self).joined(separator: "/")
  }

  /// Il rettangolo dell'elemento, in coordinate globali con l'origine in alto a sinistra.
  var frame: CGRect? {
    guard let position = attribute("AXPosition"), let size = attribute("AXSize"),
          CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
    else { return nil }
    var origin = CGPoint.zero
    var extent = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
          AXValueGetValue(size as! AXValue, .cgSize, &extent)
    else { return nil }
    return CGRect(origin: origin, size: extent)
  }
}
