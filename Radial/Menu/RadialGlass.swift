import SwiftUI

/// Il vetro di Radial, con un velo di colore tra il vetro e il contenuto.
struct RadialGlass<S: Shape>: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme

  let shape: S
  var isAccented = false

  func body(content: Content) -> some View {
    content
      .background { shape.fill(isAccented ? Color.fixedAccent.opacity(0.85) : veil) }
      .glassEffect(.regular, in: shape)
  }

  // Il colore di accento è un riempimento e non una tinta del vetro: i pannelli non sono mai la
  // finestra attiva, e il sistema toglie la tinta al vetro delle finestre non attive.
  //
  // Nel tema chiaro il vetro prende il tono di ciò che ha dietro: su uno sfondo scuro diventa
  // scuro e le icone scure non si leggono più. Un velo bianco lo tiene chiaro.
  private var veil: Color {
    colorScheme == .light ? .white.opacity(0.5) : .clear
  }
}

extension Color {
  /// Il colore di accento di sistema, fissato ai suoi componenti: quello dinamico diventa grigio
  /// nelle finestre non attive, e i pannelli non lo sono mai.
  static var fixedAccent: Color {
    guard let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return .accentColor }
    return Color(red: accent.redComponent, green: accent.greenComponent, blue: accent.blueComponent)
  }
}
