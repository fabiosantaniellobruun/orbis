import SwiftUI

/// I pezzi dei moduli di Orbis (Rinomina, Ridimensiona…).

struct FieldRow<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
      content
    }
  }
}

/// Un interruttore con l'etichetta a sinistra e l'interruttore sul bordo destro: in colonna
/// gli interruttori stanno tutti sulla stessa linea, qualunque sia la lunghezza delle etichette.
struct SwitchRow: View {
  let title: String
  @Binding var isOn: Bool

  init(_ title: String, isOn: Binding<Bool>) {
    self.title = title
    self._isOn = isOn
  }

  var body: some View {
    Toggle(isOn: $isOn) {
      Text(title)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .toggleStyle(.switch)
  }
}

struct OrbisField: ViewModifier {
  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
    content
      .textFieldStyle(.plain)
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(.primary.opacity(0.09), in: shape)
      .overlay { shape.strokeBorder(.primary.opacity(0.14), lineWidth: 1) }
  }
}

extension Binding where Value == Int? {
  /// Il numero come testo che si aggiorna a ogni tasto (un `TextField` con `value:` lo fa solo
  /// a invio): si tengono le sole cifre, e vuoto vuol dire nessun valore.
  var digits: Binding<String> {
    Binding<String>(
      get: { wrappedValue.map(String.init) ?? "" },
      set: { text in
        let cleaned = text.filter(\.isASCIIDigit)
        // Più cifre di un numero ragionevole sono un errore di battitura, non una misura.
        wrappedValue = cleaned.isEmpty ? nil : Int(cleaned.prefix(6))
      }
    )
  }
}

extension Binding where Value == Int {
  /// Come `digits` per un numero sempre presente: vuoto vale 0.
  var digits: Binding<String> {
    Binding<String>(
      get: { String(wrappedValue) },
      set: { text in
        let cleaned = text.filter(\.isASCIIDigit)
        wrappedValue = Int(cleaned.prefix(6)) ?? 0
      }
    )
  }
}

private extension Character {
  var isASCIIDigit: Bool { isASCII && isNumber }
}
