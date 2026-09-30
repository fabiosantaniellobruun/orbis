import SwiftUI

struct RadialMenuView: View {
  let model: RadialModel

  private var isOpen: Bool { model.phase == .ring }

  var body: some View {
    ZStack {
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
          RadialButton(
            action: action,
            size: geometry.buttonSize,
            isOpen: isOpen,
            isHighlighted: model.highlighted == index
          )
            .opacity(isOpen ? 1 : 0)
            .offset(isOpen ? geometry.offset(at: index) : .zero)
            .animation(
              isOpen
                ? .spring(duration: 0.36, bounce: 0.28).delay(Double(index) * 0.012)
                : .easeOut(duration: 0.12),
              value: isOpen
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
      .glassEffect(.regular, in: .capsule)
      .fixedSize()
      .id(index)
      .transition(.opacity)
  }
}

private struct RadialButton: View {
  let action: RadialAction
  let size: CGFloat
  let isOpen: Bool
  let isHighlighted: Bool

  // Il bottone cambia dimensione con il frame e non con `scaleEffect`: applicato al vetro,
  // `scaleEffect` lo scala da un angolo e lo stacca dal contenuto.
  private var diameter: CGFloat {
    guard isOpen else { return size * 0.3 }
    return isHighlighted ? size * 1.18 : size
  }

  var body: some View {
    Image(systemName: action.symbol)
      .font(.system(size: 20, weight: .medium))
      .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
      .scaleEffect(isOpen ? 1 : 0.3)
      .frame(width: diameter, height: diameter)
      // Il colore è un riempimento e non una tinta del vetro: il pannello non è mai la finestra
      // attiva, e il sistema toglie la tinta al vetro delle finestre non attive.
      .background {
        Circle()
          .fill(Color.fixedAccent)
          .opacity(isHighlighted ? 0.85 : 0)
      }
      .glassEffect(.regular, in: .circle)
      .animation(.spring(duration: 0.22, bounce: 0.35), value: isHighlighted)
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
      .glassEffect(.regular, in: .capsule)
  }
}
