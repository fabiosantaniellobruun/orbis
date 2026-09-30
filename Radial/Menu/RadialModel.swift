import Observation

@Observable
final class RadialModel {
  enum Phase: Equatable {
    case hidden
    case ring
    case confirmation(RadialAction)
  }

  var phase: Phase = .hidden
  var highlighted: Int?

  let actions: [RadialAction]
  let geometry: RingGeometry

  init(actions: [RadialAction] = RadialAction.all) {
    self.actions = actions
    self.geometry = RingGeometry(count: actions.count)
  }
}
