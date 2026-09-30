import SwiftUI

struct RadialMenuView: View {
  let model: RadialModel

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var isOpen: Bool { model.phase == .ring }

  /// Il bottone su cui sono stati rilasciati i file: resta al suo posto durante la conferma.
  private var confirmedIndex: Int? {
    guard case .confirmation(let action) = model.phase else { return nil }
    return model.actions.firstIndex(of: action)
  }

  var body: some View {
    ZStack {
      if let index = confirmedIndex, !reduceMotion {
        HoloRipple(startDiameter: model.geometry.buttonSize, spread: 110)
          .offset(model.geometry.offset(at: index))
          .transition(.identity)
      }

      ring

      if isOpen, let index = model.highlighted {
        title(for: index)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .animation(.spring(duration: 0.28, bounce: 0.2), value: model.phase)
    .animation(.easeOut(duration: 0.12), value: model.highlighted)
  }

  private var ring: some View {
    let geometry = model.geometry
    return GlassEffectContainer(spacing: 14) {
      ZStack {
        ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
          let isConfirmed = confirmedIndex == index
          let isShown = isOpen || isConfirmed
          RadialButton(
            action: action,
            size: geometry.buttonSize,
            isShown: isShown,
            isHighlighted: model.highlighted == index,
            isConfirmed: isConfirmed
          )
            .opacity(isShown ? 1 : 0)
            .offset(isShown ? geometry.offset(at: index) : .zero)
            .animation(
              isShown
                ? .spring(duration: 0.36, bounce: 0.28).delay(Double(index) * 0.012)
                : .easeOut(duration: 0.12),
              value: isShown
            )
        }
      }
    }
  }

  /// Il nome dell'azione sta al centro dell'anello: accanto al bottone finirebbe sotto
  /// l'immagine dei file trascinati, che segue il puntatore.
  private func title(for index: Int) -> some View {
    Text(model.actions[index].title)
      .font(.system(size: 13, weight: .semibold))
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .modifier(RadialGlass(shape: .capsule))
      .fixedSize()
      .id(index)
      .transition(.opacity)
  }
}

private struct RadialButton: View {
  let action: RadialAction
  let size: CGFloat
  let isShown: Bool
  let isHighlighted: Bool
  let isConfirmed: Bool

  // Il bottone cambia dimensione con il frame e non con `scaleEffect`: applicato al vetro,
  // `scaleEffect` lo scala da un angolo e lo stacca dal contenuto.
  private var diameter: CGFloat {
    guard isShown else { return size * 0.3 }
    return isHighlighted ? size * 1.18 : size
  }

  private var isAccented: Bool { isHighlighted || isConfirmed }

  var body: some View {
    Image(systemName: action.symbol)
      .font(.system(size: 20, weight: .medium))
      .foregroundStyle(isAccented ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
      .scaleEffect(isShown ? 1 : 0.3)
      .frame(width: diameter, height: diameter)
      .modifier(RadialGlass(shape: .circle, isAccented: isAccented))
      .animation(.spring(duration: 0.22, bounce: 0.35), value: isHighlighted)
  }
}
