import AppKit
import SwiftUI

/// Un elemento nel pannello, con un aspetto diverso per tipo: i testi sono foglietti adesivi,
/// gli altri schede di vetro con un'anteprima.
struct ClipCard: View {
  static let size = CGSize(width: 260, height: 60)

  let item: ClipItem
  var isSelected = false

  var body: some View {
    switch item.content {
    case .text(let text, _):
      StickyNote(name: item.name, text: text, shortcut: item.shortcut, isSelected: isSelected)
    default:
      GlassCard(item: item, isSelected: isSelected)
    }
  }
}

private struct GlassCard: View {
  let item: ClipItem
  let isSelected: Bool

  private let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

  var body: some View {
    HStack(spacing: 10) {
      Thumbnail(content: item.content)
        .frame(width: 40, height: 40)
      VStack(alignment: .leading, spacing: 2) {
        Text(item.name)
          .font(.callout.weight(.semibold))
          .lineLimit(1)
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer(minLength: 0)
      if let shortcut = item.shortcut {
        ShortcutBadge(shortcut: shortcut)
      }
    }
    .padding(.horizontal, 10)
    .frame(width: ClipCard.size.width, height: ClipCard.size.height)
    .modifier(OrbisGlass(shape: shape, lightVeil: 0.6))
    .overlay {
      shape.strokeBorder(Color.fixedAccent, lineWidth: 2).opacity(isSelected ? 1 : 0)
    }
  }

  private var subtitle: String {
    switch item.content {
    case .link(let url):
      let host = url.host(percentEncoded: false) ?? ""
      return host + (url.path(percentEncoded: false) == "/" ? "" : url.path(percentEncoded: false))
    case .file(let blob):
      return blob.name
    case .image(let blob):
      guard let rep = Thumbnails.image(for: blob)?.representations.first else { return "Immagine" }
      return "\(rep.pixelsWide) × \(rep.pixelsHigh) px"
    case .password:
      return "••••••••"
    case .text(let text, _):
      return text
    }
  }
}

private struct Thumbnail: View {
  let content: ClipItem.Content

  private let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)

  var body: some View {
    switch content {
    case .image(let blob):
      if let image = Thumbnails.image(for: blob) {
        Image(nsImage: image)
          .resizable()
          .scaledToFill()
          .clipShape(shape)
      }
    case .file(let blob):
      Image(nsImage: NSWorkspace.shared.icon(forFile: blob.url.path(percentEncoded: false)))
        .resizable()
        .scaledToFit()
    case .link:
      // L'anteprima del sito arriverà da LinkPresentation.
      symbol("globe", color: .blue)
    case .password:
      symbol("key.fill", color: .gray)
    case .text:
      symbol("text.alignleft", color: .yellow)
    }
  }

  private func symbol(_ name: String, color: Color) -> some View {
    shape
      .fill(color.gradient)
      .overlay {
        Image(systemName: name)
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(.white)
      }
  }
}

/// Un foglietto adesivo: carta gialla, ombra leggera, il testo in primo piano e il nome sopra.
private struct StickyNote: View {
  let name: String
  let text: String
  let shortcut: String?
  let isSelected: Bool

  @Environment(\.colorScheme) private var colorScheme

  private let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Text(name)
          .font(.caption.weight(.semibold))
          .opacity(0.7)
          .lineLimit(1)
        Spacer(minLength: 0)
        if let shortcut {
          ShortcutBadge(shortcut: shortcut)
        }
      }
      Text(text)
        .font(.footnote)
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .foregroundStyle(Color.black.opacity(0.82))
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .frame(width: ClipCard.size.width, height: ClipCard.size.height, alignment: .topLeading)
    .background {
      shape.fill(
        LinearGradient(colors: paper, startPoint: .top, endPoint: .bottom)
      )
      .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
    }
    .overlay {
      shape.strokeBorder(Color.fixedAccent, lineWidth: 2).opacity(isSelected ? 1 : 0)
    }
  }

  private var paper: [Color] {
    colorScheme == .dark
      ? [Color(red: 0.96, green: 0.86, blue: 0.45), Color(red: 0.92, green: 0.8, blue: 0.38)]
      : [Color(red: 1, green: 0.94, blue: 0.6), Color(red: 0.99, green: 0.89, blue: 0.5)]
  }
}

/// Le immagini degli elementi, lette una volta sola: il pannello si ridisegna spesso.
enum Thumbnails {
  private static let cache = NSCache<NSUUID, NSImage>()

  static func image(for blob: ClipBlob) -> NSImage? {
    if let image = cache.object(forKey: blob.id as NSUUID) { return image }
    guard let image = NSImage(contentsOf: blob.url) else { return nil }
    cache.setObject(image, forKey: blob.id as NSUUID)
    return image
  }
}

private struct ShortcutBadge: View {
  let shortcut: String

  var body: some View {
    Text(shortcut)
      .font(.caption2.monospaced().weight(.medium))
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(.primary.opacity(0.1), in: Capsule())
  }
}
