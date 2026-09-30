import SwiftUI

/// L'onda che parte dal bottone quando ci si rilasciano sopra i file: una lente di vetro che si
/// allarga deformando ciò che sta sotto, con due anelli iridescenti sul bordo.
struct HoloRipple: View {
  let startDiameter: CGFloat
  /// Di quanto si allarga il raggio.
  let spread: CGFloat

  @State private var isExpanded = false

  // L'espansione parte veloce e rallenta; la dissolvenza va per conto suo, così l'anello resta
  // visibile mentre rallenta invece di sparire nei primi istanti.
  private static let expansion = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.6)
  private static let fade = Animation.linear(duration: 0.4).delay(0.12)

  var body: some View {
    ZStack {
      wave(delay: 0, strength: 1, hasLens: true)
      wave(delay: 0.09, strength: 0.6, hasLens: false)
    }
    .allowsHitTesting(false)
    .onAppear { isExpanded = true }
  }

  private func wave(delay: Double, strength: Double, hasLens: Bool) -> some View {
    HoloRing(
      progress: isExpanded ? 1 : 0,
      startDiameter: startDiameter,
      spread: spread,
      hasLens: hasLens
    )
      .animation(Self.expansion.delay(delay), value: isExpanded)
      .opacity(isExpanded ? 0 : strength)
      .animation(Self.fade.delay(delay), value: isExpanded)
  }
}

private struct HoloRing: View, Animatable {
  var progress: CGFloat
  let startDiameter: CGFloat
  let spread: CGFloat
  let hasLens: Bool

  var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  private static let foil: [Color] = [
    Color(red: 0.40, green: 0.93, blue: 1.00),
    Color(red: 0.60, green: 0.52, blue: 1.00),
    Color(red: 1.00, green: 0.50, blue: 0.84),
    Color(red: 1.00, green: 0.85, blue: 0.50),
    Color(red: 0.50, green: 1.00, blue: 0.76),
    Color(red: 0.40, green: 0.93, blue: 1.00),
  ]

  var body: some View {
    let diameter = startDiameter + 2 * spread * progress
    // I colori ruotano mentre l'onda si allarga, come una pellicola olografica che cambia
    // con l'angolo.
    let foil = AngularGradient(colors: Self.foil, center: .center, angle: .degrees(140 * progress))

    ZStack {
      if hasLens {
        Color.clear
          .glassEffect(.clear, in: .circle)
      }
      Circle()
        .strokeBorder(foil, lineWidth: 12)
        .blur(radius: 9)
        .opacity(0.6)
      Circle()
        .strokeBorder(foil, lineWidth: 2.5 - 1.5 * progress)
    }
    .frame(width: diameter, height: diameter)
  }
}
