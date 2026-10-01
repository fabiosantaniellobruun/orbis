import Foundation
import Observation

@Observable
final class OrbisModel {
  enum Phase: Equatable {
    case hidden
    case ring
    /// L'azione scelta e, se ha un secondo anello, la voce su cui si è rilasciato.
    case confirmation(OrbisAction, option: Int?)
  }

  var phase: Phase = .hidden
  /// Il bottone dell'anello principale sotto il puntatore.
  var highlighted: Int?
  /// Il bottone dell'anello principale di cui si vede il secondo anello.
  var expanded: Int?
  /// La voce del secondo anello sotto il puntatore.
  var highlightedOption: Int?

  /// Le voci del secondo anello di ogni azione che ne ha, calcolate a ogni apertura del menu.
  var options: [OrbisAction.ID: [OrbisOption]] = [:]
  /// Da che lato si apre il secondo anello di ogni azione: quello del suo bottone.
  private(set) var subSides: [OrbisAction.ID: SubRingGeometry.Side] = [:]

  /// Le azioni nell'ordine dell'anello. Cambia a ogni apertura, secondo dove sta il menu.
  private(set) var actions: [OrbisAction]
  let geometry: RingGeometry

  init(actions: [OrbisAction] = OrbisAction.all) {
    self.actions = actions
    self.geometry = RingGeometry(count: actions.count)
    arrange(actions)
  }

  /// Dispone le azioni sull'anello. Il secondo anello di ognuna si apre dal lato del suo bottone:
  /// gli angoli da 0 a 180 gradi sono a destra, gli altri a sinistra.
  func arrange(_ actions: [OrbisAction]) {
    precondition(actions.count == geometry.count, "L'anello ha un numero fisso di bottoni")
    self.actions = actions
    subSides = Dictionary(uniqueKeysWithValues: actions.enumerated().map { index, action in
      (action.id, sin(geometry.angleFromTop(at: index)) >= 0 ? .right : .left)
    })
  }

  func options(at index: Int) -> [OrbisOption] {
    options[actions[index].id] ?? []
  }

  func hasOptions(at index: Int) -> Bool {
    !options(at: index).isEmpty
  }

  /// La geometria del secondo anello, se ce n'è uno aperto.
  var subGeometry: SubRingGeometry? {
    guard let expanded else { return nil }
    let options = options(at: expanded)
    guard !options.isEmpty else { return nil }
    return SubRingGeometry(count: options.count, side: subSides[actions[expanded].id] ?? .right)
  }
}
