import CoreGraphics
import Testing
@testable import Orbis

struct RingGeometryTests {
  let geometry = RingGeometry(count: 8)

  @Test("Il primo bottone sta in alto, gli altri seguono in senso orario", arguments: [
    (CGSize(width: 0, height: -100), 0),
    (CGSize(width: 100, height: 0), 2),
    (CGSize(width: 0, height: 100), 4),
    (CGSize(width: -100, height: 0), 6),
    (CGSize(width: -70, height: -70), 7),
  ])
  func sectorFollowsDirection(offset: CGSize, expected: Int) {
    #expect(geometry.hit(offset) == .sector(expected))
  }

  @Test("Il settore dipende dalla direzione, non dalla distanza dal bottone")
  func sectorIgnoresDistance() {
    #expect(geometry.hit(CGSize(width: 45, height: 0)) == .sector(2))
    #expect(geometry.hit(CGSize(width: 195, height: 0)) == .sector(2))
  }

  @Test("Al centro non è selezionato nulla")
  func centerIsDeadZone() {
    #expect(geometry.hit(.zero) == .center)
    #expect(geometry.hit(CGSize(width: 20, height: -20)) == .center)
  }

  @Test("Oltre il raggio di uscita si è fuori dal menu")
  func beyondDismissRadiusIsOutside() {
    #expect(geometry.hit(CGSize(width: 0, height: 201)) == .outside)
  }

  @Test("Ogni bottone cade nel proprio settore")
  func buttonsLandInTheirOwnSector() {
    for index in 0..<geometry.count {
      #expect(geometry.hit(geometry.offset(at: index)) == .sector(index))
    }
  }
}
