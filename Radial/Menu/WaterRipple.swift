import SwiftUI

/// L'onda al rilascio come un sasso che cade nell'acqua: creste di vetro che si allargano dal
/// bordo del bottone, una dietro l'altra, e si spengono. Il vetro del sistema rifrange ciò che c'è
/// sotto (finestre, scrivania) senza che Radial debba leggere lo schermo: per deformarlo con uno
/// shader servirebbe il permesso di registrazione dello schermo. Su ogni cresta un filo rosso e
/// uno azzurro, appena sfasati, danno l'aberrazione cromatica dell'icona.
///
/// I valori sono quelli scelti per la landing (src/scripts/radial/water.ts nel repo del sito):
/// lunghezza d'onda 30, velocità 290 punti al secondo, vita 0,3 s.
struct WaterRipple: View {
  let startDiameter: CGFloat

  @State private var start = Date.now

  private static let speed: CGFloat = 290
  private static let wavelength: CGFloat = 30
  private static let life: Double = 0.3
  private static let crests = 3
  /// Dopo questo tempo una cresta non si vede più (e^-2,3 ≈ 10%).
  private static let duration: Double = 0.7
  private static let thickness: CGFloat = 11
  private static let aberration: CGFloat = 1.8
  private static let light: Double = 0.35

  private var largest: CGFloat { startDiameter + 2 * Self.speed * Self.duration + Self.thickness * 2 }

  var body: some View {
    TimelineView(.animation) { context in
      let elapsed = context.date.timeIntervalSince(start)
      ZStack {
        ForEach(0..<Self.crests, id: \.self) { index in
          // Le creste sono separate da una lunghezza d'onda: la seconda parte quando la prima ne ha
          // percorsa una.
          crest(age: elapsed - Double(index) * Double(Self.wavelength / Self.speed), rank: index)
        }
      }
    }
    .frame(width: largest, height: largest)
    .allowsHitTesting(false)
  }

  @ViewBuilder
  private func crest(age: Double, rank: Int) -> some View {
    if age > 0, age < Self.duration {
      let strength = exp(-age / Self.life) * (1 - Double(rank) * 0.22)
      let radius = startDiameter / 2 + Self.speed * age
      let thickness = Self.thickness * (0.55 + 0.45 * strength)
      ZStack {
        // La cresta: un anello di vetro, che piega ciò che ha dietro.
        Color.clear
          .glassEffect(.clear, in: Annulus(thickness: thickness))
          .frame(width: radius * 2, height: radius * 2)
          .opacity(strength)

        // L'aberrazione: il rosso un po' fuori, l'azzurro un po' dentro.
        Circle()
          .stroke(Color(red: 1, green: 0.32, blue: 0.48), lineWidth: 1.4)
          .frame(width: (radius + Self.aberration) * 2, height: (radius + Self.aberration) * 2)
          .opacity(0.75 * strength)
          .blendMode(.plusLighter)
        Circle()
          .stroke(Color(red: 0.3, green: 0.82, blue: 1), lineWidth: 1.4)
          .frame(width: (radius - thickness - Self.aberration) * 2, height: (radius - thickness - Self.aberration) * 2)
          .opacity(0.75 * strength)
          .blendMode(.plusLighter)

        // La luce sulla cresta.
        Circle()
          .stroke(.white, lineWidth: 1)
          .frame(width: (radius - thickness / 2) * 2, height: (radius - thickness / 2) * 2)
          .opacity(Self.light * strength)
          .blendMode(.plusLighter)
      }
    }
  }
}

/// Un anello: il cerchio esterno in un verso e quello interno nell'altro, così dentro resta vuoto
/// qualunque sia la regola di riempimento di chi lo disegna (il vetro compreso).
nonisolated struct Annulus: Shape {
  var thickness: CGFloat

  func path(in rect: CGRect) -> Path {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let outer = min(rect.width, rect.height) / 2
    let inner = max(0, outer - thickness)
    var path = Path()
    path.move(to: CGPoint(x: center.x + outer, y: center.y))
    path.addArc(center: center, radius: outer, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
    path.closeSubpath()
    path.move(to: CGPoint(x: center.x + inner, y: center.y))
    path.addArc(center: center, radius: inner, startAngle: .zero, endAngle: .degrees(-360), clockwise: true)
    path.closeSubpath()
    return path
  }
}
