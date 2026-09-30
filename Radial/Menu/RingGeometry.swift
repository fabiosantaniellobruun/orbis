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
