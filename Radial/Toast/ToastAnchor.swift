import Foundation

/// Dove compare l'avviso: accanto al bottone usato, dalla parte che guarda fuori dall'anello
/// (sotto Cestina, sopra Rinomina, di fianco ai bottoni sui lati), oppure centrato su un punto.
/// Al centro dell'anello finirebbe sopra i file appena trascinati.
nonisolated struct ToastAnchor: Equatable, Sendable {
  enum Side: Sendable {
    case top, bottom, left, right
  }

  /// Il centro del bottone, in coordinate dello schermo (y verso l'alto).
  var point: CGPoint
  /// Dal centro del bottone al bordo da cui parte l'avviso.
  var reach: CGFloat = 0
  /// Il lato preferito; `nil` per centrare l'avviso sul punto.
  var side: Side?

  static func centered(at point: CGPoint) -> ToastAnchor {
    ToastAnchor(point: point)
  }

  /// L'avviso accanto a un bottone dell'anello.
  /// - Parameters:
  ///   - offset: il bottone rispetto al centro dell'anello, con y verso il basso (come in SwiftUI).
  ///   - center: il centro dell'anello sullo schermo, con y verso l'alto.
  ///   - radius: il raggio del bottone (acceso).
  ///   - vertical: per le voci del secondo anello, che hanno l'etichetta di fianco: l'avviso va
  ///     sopra o sotto.
  static func beside(offset: CGSize, from center: CGPoint, radius: CGFloat, vertical: Bool = false) -> ToastAnchor {
    let length = hypot(offset.width, offset.height)
    let dx = length > 0 ? offset.width / length : 0
    let dy = length > 0 ? offset.height / length : 1
    // In alto, in basso e in diagonale l'avviso va sopra o sotto; ai lati di fianco.
    let side: Side = vertical || abs(dy) >= abs(dx) * 0.9
      ? (dy >= 0 ? .bottom : .top)
      : (dx > 0 ? .right : .left)
    return ToastAnchor(
      point: CGPoint(x: center.x + offset.width, y: center.y - offset.height),
      reach: radius + 10,
      side: side
    )
  }

  /// Dove sta un avviso di questa misura dentro `bounds` (y verso l'alto). Dal lato preferito se
  /// lì c'è posto; altrimenti sotto o sopra il bottone, e verso il centro dell'anello solo per
  /// ultimo. Comunque dentro `bounds`.
  func frame(for size: CGSize, in bounds: CGRect) -> CGRect {
    guard let side else {
      return clamped(CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), to: bounds)
    }

    let order: [Side] = switch side {
    case .right: [.right, .bottom, .top, .left]
    case .left: [.left, .bottom, .top, .right]
    case .bottom: [.bottom, .top, .right, .left]
    case .top: [.top, .bottom, .right, .left]
    }
    let candidates = order.map { ($0, rect(on: $0, size: size)) }
    let chosen = candidates.first { candidate, rect in
      switch candidate {
      // Sopra e sotto l'avviso può scorrere di lato senza coprire il bottone: basta l'altezza.
      case .top, .bottom: rect.minY >= bounds.minY && rect.maxY <= bounds.maxY
      case .left, .right: rect.minX >= bounds.minX && rect.maxX <= bounds.maxX
      }
    }?.1 ?? rect(on: side, size: size)
    return clamped(chosen, to: bounds)
  }

  private func rect(on side: Side, size: CGSize) -> CGRect {
    let origin = switch side {
    case .bottom: CGPoint(x: point.x - size.width / 2, y: point.y - reach - size.height)
    case .top: CGPoint(x: point.x - size.width / 2, y: point.y + reach)
    case .right: CGPoint(x: point.x + reach, y: point.y - size.height / 2)
    case .left: CGPoint(x: point.x - reach - size.width, y: point.y - size.height / 2)
    }
    return CGRect(origin: origin, size: size)
  }

  private func clamped(_ rect: CGRect, to bounds: CGRect) -> CGRect {
    var rect = rect
    rect.origin.x = min(max(rect.minX, bounds.minX), bounds.maxX - rect.width)
    rect.origin.y = min(max(rect.minY, bounds.minY), bounds.maxY - rect.height)
    return rect
  }
}
