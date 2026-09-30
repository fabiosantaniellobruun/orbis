import SwiftUI

struct RadialMenuView: View {
  let model: RadialModel

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var isOpen: Bool { model.phase == .ring }

  /// Il bottone su cui sono stati rilasciati i file: resta al suo posto durante la conferma.
  private var confirmedIndex: Int? {
    guard case .confirmation(let action, _) = model.phase else { return nil }
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

      if case .confirmation(let action, let fileCount) = model.phase {
        ConfirmationLabel(action: action, fileCount: fileCount)
          .transition(.scale(scale: 0.8).combined(with: .opacity))
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

/// Il vetro del menu, con un velo di colore tra il vetro e il contenuto.
private struct RadialGlass<S: Shape>: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme

  let shape: S
  var isAccented = false

  func body(content: Content) -> some View {
    content
      .background { shape.fill(isAccented ? Color.fixedAccent.opacity(0.85) : veil) }
      .glassEffect(.regular, in: shape)
  }

  // Il colore di accento è un riempimento e non una tinta del vetro: il pannello non è mai la
  // finestra attiva, e il sistema toglie la tinta al vetro delle finestre non attive.
  //
  // Nel tema chiaro il vetro prende il tono di ciò che ha dietro: su uno sfondo scuro diventa
  // scuro e le icone scure non si leggono più. Un velo bianco lo tiene chiaro.
  private var veil: Color {
    colorScheme == .light ? .white.opacity(0.5) : .clear
  }
}

private extension Color {
  /// Il colore di accento di sistema, fissato ai suoi componenti: quello dinamico diventa grigio
  /// nelle finestre non attive, e il pannello non lo è mai.
  static var fixedAccent: Color {
    guard let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return .accentColor }
    return Color(red: accent.redComponent, green: accent.greenComponent, blue: accent.blueComponent)
  }
}

private struct ConfirmationLabel: View {
  let action: RadialAction
  let fileCount: Int

  private var text: String {
    switch fileCount {
    case 0: action.title
    case 1: "\(action.title) · 1 elemento"
    default: "\(action.title) · \(fileCount) elementi"
    }
  }

  var body: some View {
    Label(text, systemImage: action.symbol)
      .font(.system(size: 14, weight: .semibold))
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .modifier(RadialGlass(shape: .capsule))
  }
}
