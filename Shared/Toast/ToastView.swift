import SwiftUI

struct ToastContent: Equatable {
  var symbol: String
  var text: String
  var isWorking = false
  var canUndo = false
}

@Observable
final class ToastModel {
  var content: ToastContent?
  var onUndo: (() -> Void)?

  /// Annulla una volta sola, anche con un doppio clic.
  func undo() {
    let action = onUndo
    onUndo = nil
    action?()
  }
}

/// L'avviso che dice com'è andata un'azione, con il pulsante per annullarla.
struct ToastView: View {
  let model: ToastModel

  var body: some View {
    ZStack {
      if let content = model.content {
        ToastBubble(content: content) { model.undo() }
          .transition(.scale(scale: 0.9).combined(with: .opacity))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .animation(.spring(duration: 0.28, bounce: 0.2), value: model.content)
  }
}

/// La capsula dell'avviso. Sta in una vista sua perché `ToastController` ne misura la grandezza,
/// per mettere l'avviso accanto al bottone usato.
struct ToastBubble: View {
  let content: ToastContent
  let onUndo: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      if content.isWorking {
        ProgressView()
          .controlSize(.small)
      } else {
        Image(systemName: content.symbol)
      }

      Text(content.text)
        .contentTransition(.opacity)
        // Il nome di una cartella può essere lungo: si taglia nel mezzo, dov'è meno importante.
        .lineLimit(1)
        .truncationMode(.middle)
        .frame(maxWidth: 440)

      if content.canUndo {
        Divider()
          .frame(height: 16)
        Button("Annulla", action: onUndo)
          .buttonStyle(.plain)
          .fontWeight(.semibold)
          .foregroundStyle(Color.fixedAccent)
          // Un bersaglio più grande del testo, fino al bordo dell'avviso.
          .padding(.vertical, 10)
          .padding(.trailing, 16)
          .contentShape(.rect)
          .padding(.vertical, -10)
          .padding(.trailing, -16)
      }
    }
    .font(.system(size: 14, weight: .medium))
    .lineLimit(1)
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .modifier(OrbisGlass(shape: .capsule))
    .fixedSize()
  }
}
