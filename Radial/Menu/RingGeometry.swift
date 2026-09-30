import Foundation

/// Geometria dell'anello. Gli offset sono relativi al centro, con y verso il basso:
/// il primo bottone sta in alto e gli altri seguono in senso orario.
nonisolated struct RingGeometry: Sendable, Equatable {
  var count: Int
  var radius: CGFloat = 112
  var buttonSize: CGFloat = 56
  /// Sotto questa distanza dal centro non è selezionata nessuna azione.
  var deadZone: CGFloat = 40
  /// Oltre questa distanza il puntatore è fuori dal menu.
  var dismissRadius: CGFloat = 200

  enum Hit: Equatable {
    case center
    case sector(Int)
    case outside
  }

  private var step: CGFloat { 2 * .pi / CGFloat(count) }

  /// L'angolo del bottone, in radianti da "ore dodici" in senso orario.
  func angleFromTop(at index: Int) -> CGFloat {
    CGFloat(index) * step
  }

  func direction(at index: Int) -> CGVector {
    let angle = -CGFloat.pi / 2 + CGFloat(index) * step
    return CGVector(dx: cos(angle), dy: sin(angle))
  }

  func offset(at index: Int, radius: CGFloat? = nil) -> CGSize {
    let direction = direction(at: index)
    let radius = radius ?? self.radius
    return CGSize(width: direction.dx * radius, height: direction.dy * radius)
  }

  /// La selezione va per settore angolare: conta la direzione, non la mira sul bottone.
  func hit(_ offset: CGSize) -> Hit {
    let distance = hypot(offset.width, offset.height)
    if distance < deadZone { return .center }
    if distance > dismissRadius { return .outside }
    let angle = atan2(offset.height, offset.width) + .pi / 2
    let index = Int((angle / step).rounded())
    return .sector(((index % count) + count) % count)
  }
}

/// Il secondo anello: un arco di voci oltre l'anello principale, dal lato della voce che le apre.
/// Ogni voce ha la sua etichetta accanto, sul lato esterno, dove c'è posto per nome e percorso.
nonisolated struct SubRingGeometry: Sendable, Equatable {
  enum Side: Sendable, Equatable {
    case left
    case right
  }

  var count: Int
  var side: Side
  var radius: CGFloat = 224
  var buttonSize: CGFloat = 46
  /// La distanza angolare tra due voci: a questo raggio sono quasi 70 punti.
  var step: CGFloat = 18 * .pi / 180
  /// Da qui in fuori valgono le voci del secondo anello; più dentro, l'anello principale.
  var innerRadius: CGFloat = 165
  /// Oltre questa distanza il puntatore è fuori dal menu.
  var dismissRadius: CGFloat = 480

  static let labelWidth: CGFloat = 200
  static let labelGap: CGFloat = 8

  /// Quanto spazio serve in verticale, dal centro, per l'arco con sette voci e le loro etichette.
  static let verticalReach: CGFloat = 232

  /// Quanto spazio serve in orizzontale, dal centro, per il secondo anello con le sue etichette.
  static var reach: CGFloat {
    SubRingGeometry(count: 1, side: .right).radius
      + SubRingGeometry(count: 1, side: .right).buttonSize / 2
      + labelGap + labelWidth
  }

  /// L'angolo della voce, in radianti da "ore dodici" in senso orario. L'arco è centrato sul lato:
  /// a destra su ore tre, a sinistra su ore nove. La prima voce sta sempre in alto: a sinistra gli
  /// angoli crescono verso l'alto, quindi l'ordine si inverte.
  func angle(at index: Int) -> CGFloat {
    let center: CGFloat = side == .right ? .pi / 2 : 3 * .pi / 2
    let direction: CGFloat = side == .right ? 1 : -1
    return center + direction * (CGFloat(index) - CGFloat(count - 1) / 2) * step
  }

  func offset(at index: Int) -> CGSize {
    let angle = angle(at: index)
    return CGSize(width: radius * sin(angle), height: -radius * cos(angle))
  }

  /// La voce sotto il puntatore, per direzione: conta l'angolo, non la mira sul bottone.
  func hit(_ offset: CGSize) -> Int? {
    guard count > 0 else { return nil }
    let distance = hypot(offset.width, offset.height)
    guard distance >= innerRadius, distance <= dismissRadius else { return nil }

    let pointer = atan2(offset.width, -offset.height)
    var best = (index: 0, difference: CGFloat.infinity)
    for index in 0..<count {
      let raw = pointer - angle(at: index)
      let difference = atan2(sin(raw), cos(raw))
      if abs(difference) < abs(best.difference) {
        best = (index, difference)
      }
    }

    // Le voci alle estremità accettano un po' di margine oltre l'arco, e una voce sola molto di più.
    let limit: CGFloat = switch count {
    case 1: step * 1.6
    default: (best.index == 0 || best.index == count - 1) ? step * 0.9 : step * 0.5
    }
    return abs(best.difference) <= limit ? best.index : nil
  }
}
