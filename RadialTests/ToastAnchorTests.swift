import CoreGraphics
import Testing
@testable import Radial

struct ToastAnchorTests {
  private let center = CGPoint(x: 500, y: 500)
  private let ring = RingGeometry(count: 8)
  private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
  private let toast = CGSize(width: 260, height: 40)

  private func anchor(at index: Int) -> ToastAnchor {
    .beside(offset: ring.offset(at: index), from: center, radius: ring.buttonSize * 1.18 / 2)
  }

  @Test("Ogni bottone ha l'avviso dalla parte che guarda fuori dall'anello")
  func sides() {
    // In senso orario dall'alto: in alto, in diagonale, a destra, in diagonale, in basso…
    let expected: [ToastAnchor.Side] = [.top, .top, .right, .bottom, .bottom, .bottom, .left, .top]
    #expect((0..<8).map { anchor(at: $0).side } == expected)
  }

  @Test("Il punto è il centro del bottone, con y verso l'alto come sullo schermo")
  func point() {
    let top = anchor(at: 0)
    #expect(abs(top.point.x - 500) < 0.001)
    #expect(abs(top.point.y - 612) < 0.001)
    #expect(top.reach == ring.buttonSize * 1.18 / 2 + 10)
  }

  @Test("Sotto Cestina, sopra Rinomina, di fianco ai bottoni sui lati")
  func frames() {
    let bottom = anchor(at: 4).frame(for: toast, in: screen)
    #expect(bottom.maxY <= 388 - anchor(at: 4).reach + 0.001)
    #expect(abs(bottom.midX - 500) < 0.001)

    let top = anchor(at: 0).frame(for: toast, in: screen)
    #expect(top.minY >= 612 + anchor(at: 0).reach - 0.001)

    let right = anchor(at: 2).frame(for: toast, in: screen)
    #expect(right.minX >= 612 + anchor(at: 2).reach - 0.001)
    #expect(abs(right.midY - 500) < 0.001)

    let left = anchor(at: 6).frame(for: toast, in: screen)
    #expect(left.maxX <= 388 - anchor(at: 6).reach + 0.001)
  }

  @Test("Le voci del secondo anello hanno l'avviso sopra o sotto: di fianco c'è l'etichetta")
  func subRingOptions() {
    let sub = SubRingGeometry(count: 7, side: .left)
    let upper = ToastAnchor.beside(offset: sub.offset(at: 0), from: center, radius: 27, vertical: true)
    let lower = ToastAnchor.beside(offset: sub.offset(at: 6), from: center, radius: 27, vertical: true)
    #expect(upper.side == .top)
    #expect(lower.side == .bottom)
  }

  @Test("Se dal lato giusto non c'è posto, l'avviso va sotto il bottone, non sopra di esso")
  func fallsBackNearEdges() {
    // Un bottone a destra, vicino al bordo destro dello schermo.
    let nearEdge = ToastAnchor.beside(offset: CGSize(width: 112, height: 0), from: CGPoint(x: 1300, y: 500), radius: 33)
    #expect(nearEdge.side == .right)
    let frame = nearEdge.frame(for: toast, in: screen)
    #expect(frame.maxY <= 500 - nearEdge.reach + 0.001)
    #expect(frame.maxX <= screen.maxX)

    // Cestina vicino al fondo dello schermo: l'avviso sale sopra il bottone.
    let nearBottom = ToastAnchor.beside(offset: CGSize(width: 0, height: 112), from: CGPoint(x: 700, y: 150), radius: 33)
    let lifted = nearBottom.frame(for: toast, in: screen)
    #expect(lifted.minY >= 38 + nearBottom.reach - 0.001)
  }

  @Test("Centrato sul punto, e comunque dentro lo schermo")
  func centeredAndClamped() {
    let centered = ToastAnchor.centered(at: CGPoint(x: 720, y: 450)).frame(for: toast, in: screen)
    #expect(centered.midX == 720 && centered.midY == 450)

    let corner = ToastAnchor.centered(at: CGPoint(x: 5, y: 5)).frame(for: toast, in: screen)
    #expect(corner.minX == 0 && corner.minY == 0)
  }
}
