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

  /// La voce del secondo anello su cui sono stati rilasciati i file, se c'è.
  private var confirmedOption: Int? {
    guard case .confirmation(_, let option) = model.phase else { return nil }
    return option
  }

  /// Da dove parte l'onda: dal bottone scelto, o dalla voce del secondo anello.
  private var rippleOrigin: (offset: CGSize, diameter: CGFloat)? {
    guard let index = confirmedIndex else { return nil }
    if let option = confirmedOption, let sub = model.subGeometry {
      return (sub.offset(at: option), sub.buttonSize)
    }
    return (model.geometry.offset(at: index), model.geometry.buttonSize)
  }

  var body: some View {
    ZStack {
      if let origin = rippleOrigin, !reduceMotion {
        HoloRipple(startDiameter: origin.diameter, spread: 110)
          .offset(origin.offset)
          .transition(.identity)
      }

      ring
      subRing

      if isOpen, let index = model.highlighted {
        title(for: index)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .animation(.spring(duration: 0.28, bounce: 0.2), value: model.phase)
    .animation(.easeOut(duration: 0.12), value: model.highlighted)
    .animation(.easeOut(duration: 0.12), value: model.highlightedOption)
  }

  // MARK: Anello principale

  private var ring: some View {
    let geometry = model.geometry
    return GlassEffectContainer(spacing: 14) {
      ZStack {
        ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
          // Il bottone scelto resta al suo posto anche durante la conferma.
          let isKept = confirmedIndex == index
          let isShown = isOpen || isKept
          RadialButton(
            action: action,
            size: geometry.buttonSize,
            isShown: isShown,
            isHighlighted: model.highlighted == index,
            isConfirmed: isKept && confirmedOption == nil
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

  // MARK: Secondo anello

  @ViewBuilder
  private var subRing: some View {
    if let expanded = model.expanded, let sub = model.subGeometry, isOpen || confirmedIndex == expanded {
      let origin = model.geometry.offset(at: expanded)
      GlassEffectContainer(spacing: 4) {
        ZStack {
          ForEach(Array(model.options(at: expanded).enumerated()), id: \.element.id) { index, option in
            SubItem(
              option: option,
              index: index,
              geometry: sub,
              origin: origin,
              isHighlighted: model.highlightedOption == index,
              isConfirmed: confirmedOption == index,
              isDimmed: confirmedOption != nil && confirmedOption != index
            )
          }
        }
      }
      // Passando da un'azione all'altra le voci si ridisegnano e ripartono dal loro bottone.
      .id(expanded)
      .transition(.opacity)
    }
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

/// Una voce del secondo anello: il bottone e, accanto, l'etichetta con nome e percorso.
private struct SubItem: View {
  let option: RadialOption
  let index: Int
  let geometry: SubRingGeometry
  /// Il bottone dell'anello principale da cui la voce si apre.
  let origin: CGSize
  let isHighlighted: Bool
  let isConfirmed: Bool
  let isDimmed: Bool

  @State private var appeared = false

  private var isAccented: Bool { isHighlighted || isConfirmed }

  private var diameter: CGFloat {
    guard appeared else { return geometry.buttonSize * 0.3 }
    return isAccented ? geometry.buttonSize * 1.18 : geometry.buttonSize
  }

  private var alignment: Alignment { geometry.side == .right ? .leading : .trailing }

  var body: some View {
    let target = geometry.offset(at: index)
    let reach = geometry.buttonSize * 1.18 / 2 + SubRingGeometry.labelGap + SubRingGeometry.labelWidth / 2
    let labelTarget = CGSize(
      width: target.width + (geometry.side == .right ? reach : -reach),
      height: target.height
    )

    ZStack {
      button
        .offset(appeared ? target : origin)
      label
        .offset(appeared ? labelTarget : origin)
        .opacity(appeared ? 1 : 0)
    }
    .opacity(isDimmed ? 0 : 1)
    .animation(.easeOut(duration: 0.15), value: isDimmed)
    .onAppear {
      withAnimation(.spring(duration: 0.34, bounce: 0.25).delay(Double(index) * 0.02)) {
        appeared = true
      }
    }
  }

  private var button: some View {
    glyph
      .frame(width: diameter, height: diameter)
      .modifier(RadialGlass(shape: .circle, isAccented: isAccented))
      .opacity(appeared ? 1 : 0)
      .animation(.spring(duration: 0.22, bounce: 0.35), value: isAccented)
  }

  @ViewBuilder
  private var glyph: some View {
    if let folder = option.folder {
      // L'icona vera della cartella, com'è nel Finder: aiuta a riconoscerla a colpo d'occhio.
      Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path(percentEncoded: false)))
        .resizable()
        .frame(width: 28, height: 28)
    } else {
      Image(systemName: option.symbol)
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(isAccented ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
    }
  }

  private var label: some View {
    VStack(alignment: geometry.side == .right ? .leading : .trailing, spacing: 1) {
      HStack(spacing: 4) {
        if let badge = option.badge {
          Image(systemName: badge)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(isAccented ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
        }
        Text(option.title)
          .font(.system(size: 13, weight: .semibold))
          .lineLimit(1)
      }
      if let subtitle = option.subtitle {
        Text(subtitle)
          .font(.system(size: 10.5))
          .foregroundStyle(isAccented ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
          .lineLimit(1)
          // Del percorso contano l'inizio e la fine: il mezzo si taglia.
          .truncationMode(.middle)
      }
    }
    .foregroundStyle(isAccented ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
    .frame(maxWidth: SubRingGeometry.labelWidth - 24, alignment: alignment)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .modifier(RadialGlass(shape: RoundedRectangle(cornerRadius: 14, style: .continuous), isAccented: isAccented))
    .fixedSize()
    .frame(width: SubRingGeometry.labelWidth, alignment: alignment)
  }
}
