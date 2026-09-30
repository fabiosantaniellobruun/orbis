import CoreGraphics
import Foundation
import Testing
@testable import Radial

struct SubRingGeometryTests {
  @Test("L'arco è centrato sul lato: la voce di mezzo sta a ore tre a destra, a ore nove a sinistra")
  func arcIsCenteredOnItsSide() {
    let right = SubRingGeometry(count: 5, side: .right)
    let left = SubRingGeometry(count: 5, side: .left)

    let middleRight = right.offset(at: 2)
    let middleLeft = left.offset(at: 2)

    #expect(abs(middleRight.width - right.radius) < 0.001)
    #expect(abs(middleRight.height) < 0.001)
    #expect(abs(middleLeft.width + left.radius) < 0.001)
    #expect(abs(middleLeft.height) < 0.001)
  }

  @Test("Le voci vanno dall'alto verso il basso, su tutti e due i lati")
  func itemsRunTopToBottom() {
    for side in [SubRingGeometry.Side.right, .left] {
      let geometry = SubRingGeometry(count: 6, side: side)
      let heights = (0..<6).map { geometry.offset(at: $0).height }
      #expect(heights == heights.sorted())
    }
  }

  @Test("Fino a sette voci, quante ne ha Sposta, due etichette vicine non si sovrappongono")
  func neighboursDoNotCrowd() {
    for side in [SubRingGeometry.Side.right, .left] {
      let geometry = SubRingGeometry(count: 7, side: side)

      for index in 1..<7 {
        let gap = geometry.offset(at: index).height - geometry.offset(at: index - 1).height
        // Un'etichetta è alta poco più di trenta punti.
        #expect(gap >= 45)
      }
    }
  }

  @Test("Ogni voce cade nella propria zona", arguments: [1, 3, 7, 9])
  func itemsLandInTheirOwnZone(count: Int) {
    for side in [SubRingGeometry.Side.right, .left] {
      let geometry = SubRingGeometry(count: count, side: side)
      for index in 0..<count {
        #expect(geometry.hit(geometry.offset(at: index)) == index)
      }
    }
  }

  @Test("La zona di una voce dipende dalla direzione, non dalla distanza")
  func hitIgnoresDistance() {
    let geometry = SubRingGeometry(count: 5, side: .right)
    let direction = geometry.offset(at: 2)
    let unit = CGSize(width: direction.width / geometry.radius, height: direction.height / geometry.radius)

    for distance in [geometry.innerRadius + 5, geometry.radius, geometry.radius + 150] {
      let point = CGSize(width: unit.width * distance, height: unit.height * distance)
      #expect(geometry.hit(point) == 2)
    }
  }

  @Test("Dentro l'anello principale non c'è nessuna voce del secondo anello")
  func nothingInsideInnerRadius() {
    let geometry = SubRingGeometry(count: 5, side: .right)

    #expect(geometry.hit(CGSize(width: geometry.innerRadius - 5, height: 0)) == nil)
    #expect(geometry.hit(.zero) == nil)
  }

  @Test("Fuori dal menu non c'è nessuna voce")
  func nothingBeyondDismissRadius() {
    let geometry = SubRingGeometry(count: 5, side: .right)

    #expect(geometry.hit(CGSize(width: geometry.dismissRadius + 10, height: 0)) == nil)
  }

  @Test("Lontano dall'arco non c'è nessuna voce")
  func nothingFarFromTheArc() {
    let geometry = SubRingGeometry(count: 5, side: .right)

    // A sinistra: dalla parte opposta dell'arco.
    #expect(geometry.hit(CGSize(width: -220, height: 0)) == nil)
    // In alto, ben oltre l'ultima voce.
    #expect(geometry.hit(CGSize(width: 0, height: -220)) == nil)
  }

  @Test("Le voci alle estremità accettano un po' di margine oltre l'arco")
  func edgeItemsHaveMargin() {
    let geometry = SubRingGeometry(count: 5, side: .right)
    let step = geometry.step

    func point(at angle: CGFloat) -> CGSize {
      CGSize(width: 220 * sin(angle), height: -220 * cos(angle))
    }

    let beyondFirst = geometry.angle(at: 0) - step * 0.8
    let beyondLast = geometry.angle(at: 4) + step * 0.8
    #expect(geometry.hit(point(at: beyondFirst)) == 0)
    #expect(geometry.hit(point(at: beyondLast)) == 4)

    // Una voce di mezzo non ha lo stesso margine: a metà strada tra due voci decide la più vicina.
    let between = geometry.angle(at: 1) + step * 0.45
    #expect(geometry.hit(point(at: between)) == 1)
  }

  @Test("Una voce sola si prende con ampio margine")
  func singleItemIsEasyToHit() {
    let geometry = SubRingGeometry(count: 1, side: .right)
    let angle = geometry.angle(at: 0) + geometry.step * 1.2

    let point = CGSize(width: 220 * sin(angle), height: -220 * cos(angle))

    #expect(geometry.hit(point) == 0)
  }

  // MARK: Disposizioni dell'anello

  static let layouts: [(name: String, actions: [RadialAction])] = [
    ("di base", RadialAction.all),
    ("con le voci a destra", RadialAction.rightHanded),
    ("con le voci a sinistra", RadialAction.leftHanded),
  ]

  /// Il lato da cui si apre il secondo anello di una voce, dalla sua posizione sull'anello.
  func side(of id: RadialAction.ID, in actions: [RadialAction]) -> SubRingGeometry.Side {
    let ring = RingGeometry(count: actions.count)
    let index = actions.firstIndex { $0.id == id }!
    return sin(ring.angleFromTop(at: index)) >= 0 ? .right : .left
  }

  @Test("Ogni disposizione ha tutte le azioni, una volta sola")
  func layoutsHaveEveryActionOnce() {
    let everything = Set(RadialAction.ID.allCasesForTests)

    for layout in Self.layouts {
      #expect(layout.actions.count == 8, "\(layout.name)")
      #expect(Set(layout.actions.map(\.id)) == everything, "\(layout.name)")
    }
  }

  @Test("Di base Converti in sta a destra e Sposta a sinistra")
  func defaultLayoutSides() {
    #expect(side(of: .convert, in: RadialAction.all) == .right)
    #expect(side(of: .move, in: RadialAction.all) == .left)
  }

  @Test("Con le voci a destra, Sposta e Converti in si aprono tutte e due a destra")
  func rightHandedLayoutSides() {
    #expect(side(of: .convert, in: RadialAction.rightHanded) == .right)
    #expect(side(of: .move, in: RadialAction.rightHanded) == .right)
  }

  @Test("Con le voci a sinistra, Sposta e Converti in si aprono tutte e due a sinistra")
  func leftHandedLayoutSides() {
    #expect(side(of: .convert, in: RadialAction.leftHanded) == .left)
    #expect(side(of: .move, in: RadialAction.leftHanded) == .left)
  }

  @Test("In ogni disposizione Cestina non sta accanto a Sposta né a Converti in")
  func trashIsAwayFromSubmenus() {
    for layout in Self.layouts {
      let ids = layout.actions.map(\.id)
      let trash = ids.firstIndex(of: .trash)!
      let count = ids.count
      let neighbours = [(trash + 1) % count, (trash + count - 1) % count]

      for neighbour in neighbours {
        #expect(ids[neighbour] != .move, "\(layout.name)")
        #expect(ids[neighbour] != .convert, "\(layout.name)")
      }
    }
  }

  @Test("In ogni disposizione Sposta e Converti in non sono uno accanto all'altro")
  func submenusAreNotAdjacent() {
    for layout in Self.layouts {
      let ids = layout.actions.map(\.id)
      let convert = ids.firstIndex(of: .convert)!
      let move = ids.firstIndex(of: .move)!
      let count = ids.count

      let distance = min((convert - move + count) % count, (move - convert + count) % count)
      #expect(distance >= 2, "\(layout.name)")
    }
  }

  @Test("Rinomina sta sempre in alto, dove ci si aspetta di trovarla")
  func renameStaysOnTop() {
    for layout in Self.layouts {
      #expect(layout.actions.first?.id == .rename, "\(layout.name)")
    }
  }

  @Test("Con posto da tutte e due le parti la disposizione è quella di base")
  func layoutWithRoomOnBothSides() {
    let reach = SubRingGeometry.reach

    let actions = RadialAction.layout(roomLeft: reach + 1, roomRight: reach + 1)

    #expect(actions.map(\.id) == RadialAction.all.map(\.id))
  }

  @Test("Se a sinistra non c'è posto, le voci passano a destra")
  func layoutNearTheLeftEdge() {
    let reach = SubRingGeometry.reach

    let actions = RadialAction.layout(roomLeft: 200, roomRight: reach + 400)

    #expect(actions.map(\.id) == RadialAction.rightHanded.map(\.id))
  }

  @Test("Se a destra non c'è posto, le voci passano a sinistra")
  func layoutNearTheRightEdge() {
    let reach = SubRingGeometry.reach

    let actions = RadialAction.layout(roomLeft: reach + 400, roomRight: 200)

    #expect(actions.map(\.id) == RadialAction.leftHanded.map(\.id))
  }

  @Test("Se non c'è posto da nessuna parte, si sceglie il lato più ampio")
  func layoutOnANarrowScreen() {
    #expect(RadialAction.layout(roomLeft: 300, roomRight: 200).map(\.id) == RadialAction.leftHanded.map(\.id))
    #expect(RadialAction.layout(roomLeft: 200, roomRight: 300).map(\.id) == RadialAction.rightHanded.map(\.id))
  }

  @Test("Il modello dispone i bottoni e ricava il lato di ogni secondo anello")
  @MainActor
  func modelDerivesSidesFromLayout() {
    let model = RadialModel()

    model.arrange(RadialAction.rightHanded)

    #expect(model.actions.map(\.id) == RadialAction.rightHanded.map(\.id))
    #expect(model.subSides[.move] == .right)
    #expect(model.subSides[.convert] == .right)

    model.arrange(RadialAction.leftHanded)

    #expect(model.subSides[.move] == .left)
    #expect(model.subSides[.convert] == .left)
  }
}

extension RadialAction.ID {
  /// Tutti i casi, per i test: l'enum non ha `CaseIterable` perché a chi lo usa non serve.
  static let allCasesForTests: [RadialAction.ID] = [.rename, .clone, .convert, .move, .resize, .compress, .copyPath, .trash]
}
