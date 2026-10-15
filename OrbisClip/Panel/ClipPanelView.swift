import SwiftUI

/// Gli elementi accanto al puntatore: i preferiti e gli ultimi usati, oppure, appena si scrive,
/// la ricerca e i suoi risultati.
struct ClipPanelView: View {
  @Bindable var model: ClipPanelModel
  var choose: (ClipItem) -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var contentHeight: CGFloat = 0

  private var alignment: HorizontalAlignment { model.side == .right ? .leading : .trailing }

  var body: some View {
    VStack(alignment: alignment, spacing: 6) {
      if model.isSearching {
        SearchBox(query: model.query, count: model.visibleItems.count)
          .transition(.opacity)
      }
      ForEach(model.sections) { section in
        if !model.isSearching {
          SectionLabel(title: section.title)
            .padding(.top, section.id == model.sections.first?.id ? 0 : 6)
        }
        ForEach(section.items) { item in
          card(item, index: index(of: item))
        }
      }
      if model.visibleItems.isEmpty {
        SectionLabel(title: model.isSearching ? "Nessun elemento" : "Ancora nessun preferito: aggiungili da Orbis Clip → Elementi…")
      }
    }
    .padding(8)
    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
    .offset(y: contentOffset)
    .animation(.snappy(duration: 0.2), value: model.query)
    .frame(
      width: model.size.width,
      height: model.size.height,
      alignment: model.side == .right ? .topLeading : .topTrailing
    )
  }

  private func card(_ item: ClipItem, index: Int) -> some View {
    let entering = model.side == .right ? -28.0 : 28.0
    return ClipCard(item: item, isSelected: model.selectedItem?.id == item.id)
      .contentShape(Rectangle())
      .onTapGesture { choose(item) }
      .onHover { inside in
        if inside { model.selectedID = item.id }
      }
      .opacity(model.hasAppeared ? 1 : 0)
      // Le schede escono dal puntatore una dopo l'altra. Niente `scaleEffect`: staccherebbe il
      // vetro dal contenuto.
      .offset(x: model.hasAppeared || reduceMotion ? 0 : entering)
      .animation(
        reduceMotion
          ? .easeOut(duration: 0.15)
          : .spring(response: 0.36, dampingFraction: 0.78).delay(Double(index) * 0.025),
        value: model.hasAppeared
      )
  }

  private func index(of item: ClipItem) -> Int {
    model.visibleItems.firstIndex { $0.id == item.id } ?? 0
  }

  /// Senza ricerca gli elementi stanno a metà altezza del puntatore; con la ricerca, la casella
  /// sta all'altezza del puntatore e i risultati sotto. Sempre dentro il pannello.
  private var contentOffset: CGFloat {
    let wanted = model.isSearching ? model.anchorY - 28 : model.anchorY - contentHeight / 2
    return min(max(wanted, 0), max(model.size.height - contentHeight, 0))
  }
}

private struct SearchBox: View {
  let query: String
  let count: Int

  private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      Text(query)
        .font(.title3)
        .lineLimit(1)
        .truncationMode(.head)
      Spacer(minLength: 0)
      Text("\(count)")
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 12)
    .frame(width: ClipCard.size.width, height: 40)
    .modifier(OrbisGlass(shape: shape, lightVeil: 0.7))
  }
}

private struct SectionLabel: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .modifier(OrbisGlass(shape: Capsule(), lightVeil: 0.6))
  }
}
