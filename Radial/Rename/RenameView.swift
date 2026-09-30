import SwiftUI

struct RenameView: View {
  @Bindable var model: RenameModel

  @FocusState private var isNameFocused: Bool

  static let cardSize = CGSize(width: 460, height: 540)

  var body: some View {
    let plan = model.plan

    VStack(alignment: .leading, spacing: 14) {
      header

      Picker("Modo", selection: $model.options.mode) {
        ForEach(RenameOptions.Mode.allCases) { mode in
          Text(mode.title).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      fields
        .frame(maxWidth: .infinity, alignment: .leading)

      preview(plan)
        .frame(maxHeight: .infinity)

      footer(plan)
    }
    .padding(20)
    .frame(width: Self.cardSize.width, height: Self.cardSize.height)
    .modifier(RadialGlass(shape: RoundedRectangle(cornerRadius: 30, style: .continuous), lightVeil: 0.72))
    .movableWindow()
    .onAppear { isNameFocused = true }
  }

  // MARK: Intestazione

  private var header: some View {
    HStack(spacing: 8) {
      Image(systemName: "character.cursor.ibeam")
        .foregroundStyle(.secondary)
      Text(model.sources.count == 1 ? "Rinomina" : "Rinomina \(model.sources.count) elementi")
        .font(.system(size: 15, weight: .semibold))
    }
  }

  // MARK: Campi

  @ViewBuilder
  private var fields: some View {
    switch model.options.mode {
    case .name: nameFields
    case .replace: replaceFields
    case .add: addFields
    case .date: dateFields
    }
  }

  private var nameFields: some View {
    VStack(alignment: .leading, spacing: 10) {
      FieldRow("Nome") {
        TextField("Nome originale", text: $model.options.baseName)
          .modifier(RadialField())
          .focused($isNameFocused)
          .onSubmit { model.apply(model.plan) }
      }

      SwitchRow("Numero progressivo", isOn: $model.options.addsNumber)

      if model.options.addsNumber {
        HStack(spacing: 14) {
          FieldRow("Parti da") {
            TextField("1", value: $model.options.start, format: .number.grouping(.never))
              .modifier(RadialField())
              .frame(width: 60)
          }
          FieldRow("Cifre") {
            Stepper(value: $model.options.digits, in: 1...6) {
              Text("\(model.options.digits)")
                .monospacedDigit()
                .frame(width: 16, alignment: .trailing)
            }
          }
          FieldRow("Separatore") {
            SeparatorPicker(selection: $model.options.separator)
          }
        }

        FieldRow("Posizione") {
          Picker("Posizione", selection: $model.options.numberFirst) {
            Text("Dopo il nome").tag(false)
            Text("Prima del nome").tag(true)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
        }

        if model.sources.count > 1 {
          FieldRow("Ordine") {
            Picker("Ordine", selection: $model.options.order) {
              ForEach(RenameOptions.Order.allCases) { order in
                Text(order.title).tag(order)
              }
            }
            .labelsHidden()
          }
        }
      }
    }
  }

  private var replaceFields: some View {
    VStack(alignment: .leading, spacing: 10) {
      FieldRow("Trova") {
        TextField("Testo da cercare", text: $model.options.find)
          .modifier(RadialField())
          .focused($isNameFocused)
      }
      FieldRow("Sostituisci con") {
        TextField("Testo nuovo (vuoto per togliere)", text: $model.options.replacement)
          .modifier(RadialField())
      }
      SwitchRow("Distingui maiuscole e minuscole", isOn: $model.options.matchCase)
    }
  }

  private var addFields: some View {
    VStack(alignment: .leading, spacing: 10) {
      FieldRow("Prima del nome") {
        TextField("Prefisso", text: $model.options.prefix)
          .modifier(RadialField())
          .focused($isNameFocused)
      }
      FieldRow("Dopo il nome") {
        TextField("Suffisso", text: $model.options.suffix)
          .modifier(RadialField())
      }
    }
  }

  private var dateFields: some View {
    VStack(alignment: .leading, spacing: 10) {
      FieldRow("Data di") {
        Picker("Data di", selection: $model.options.dateSource) {
          ForEach(RenameOptions.DateSource.allCases) { source in
            Text(source.title).tag(source)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }
      HStack(spacing: 14) {
        FieldRow("Formato") {
          Picker("Formato", selection: $model.options.dateFormat) {
            ForEach(RenameOptions.DateFormat.allCases) { format in
              Text(Self.example(of: format)).tag(format)
            }
          }
          .labelsHidden()
        }
        FieldRow("Separatore") {
          SeparatorPicker(selection: $model.options.dateSeparator)
        }
      }
      FieldRow("Posizione") {
        Picker("Posizione", selection: $model.options.dateFirst) {
          Text("Prima del nome").tag(true)
          Text("Dopo il nome").tag(false)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }
    }
  }

  private static func example(of format: RenameOptions.DateFormat) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = format.pattern
    return formatter.string(from: .now)
  }

  // MARK: Anteprima

  private func preview(_ plan: RenamePlan) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 6) {
        ForEach(plan.rows) { row in
          PreviewRow(row: row)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  // MARK: Piede

  private func footer(_ plan: RenamePlan) -> some View {
    HStack(spacing: 10) {
      summary(plan)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .lineLimit(1)

      Spacer(minLength: 8)

      Button("Annulla") {
        model.onCancel?()
      }
      .keyboardShortcut(.cancelAction)
      .buttonStyle(.glass)

      Button("Rinomina") {
        model.apply(plan)
      }
      .keyboardShortcut(.defaultAction)
      .buttonStyle(.glassProminent)
      .tint(.fixedAccent)
      .disabled(!plan.canApply)
    }
    .controlSize(.large)
  }

  private func summary(_ plan: RenamePlan) -> Text {
    if plan.problemCount > 0 {
      return Text(plan.problemCount == 1 ? "1 problema" : "\(plan.problemCount) problemi")
    }
    let count = plan.pending.count
    return switch count {
    case 0: Text("Nessuna modifica")
    case 1: Text("1 elemento da rinominare")
    default: Text("\(count) elementi da rinominare")
    }
  }
}

/// I separatori più usati, con un nome: uno spazio o niente, in un campo di testo, non si vedono.
private struct SeparatorPicker: View {
  @Binding var selection: String

  private static let options: [(value: String, title: String)] = [
    (" ", "Spazio"), ("-", "Trattino  -"), ("_", "Sottolineato  _"), (".", "Punto  ."), ("", "Nessuno"),
  ]

  var body: some View {
    Picker("Separatore", selection: $selection) {
      ForEach(Self.options, id: \.value) { option in
        Text(option.title).tag(option.value)
      }
    }
    .labelsHidden()
  }
}

private struct PreviewRow: View {
  let row: RenamePlan.Row

  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      HStack(spacing: 6) {
        Text(row.source.currentName)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
        Image(systemName: "arrow.right")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(.tertiary)
        Text(row.newName.isEmpty ? "—" : row.newName)
          .foregroundStyle(newNameStyle)
          .lineLimit(1)
          .truncationMode(.middle)
          .layoutPriority(1)
      }
      if case .problem(let problem) = row.status {
        Text(problem.message)
          .font(.system(size: 11))
          .foregroundStyle(.red)
      }
    }
    .font(.system(size: 12.5))
  }

  private var newNameStyle: AnyShapeStyle {
    switch row.status {
    case .ready: AnyShapeStyle(.primary)
    case .unchanged: AnyShapeStyle(.tertiary)
    case .problem: AnyShapeStyle(.red)
    }
  }
}
