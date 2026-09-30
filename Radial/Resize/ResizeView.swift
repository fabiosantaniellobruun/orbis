import SwiftUI

struct ResizeView: View {
  @Bindable var model: ResizeModel

  @FocusState private var isWidthFocused: Bool

  static let cardSize = CGSize(width: 460, height: 660)

  var body: some View {
    let plan = model.plan

    VStack(alignment: .leading, spacing: 14) {
      header

      Picker("Modo", selection: $model.options.mode) {
        ForEach(ResizeOptions.Mode.allCases) { mode in
          Text(mode.title).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      fields(plan)
        .frame(maxWidth: .infinity, alignment: .leading)

      Divider()

      compression(plan)

      preview(plan)
        .frame(maxHeight: .infinity)

      footer(plan)
    }
    .padding(20)
    .frame(width: Self.cardSize.width, height: Self.cardSize.height)
    .modifier(RadialGlass(shape: RoundedRectangle(cornerRadius: 30, style: .continuous), lightVeil: 0.72))
    .movableWindow()
    .onAppear { isWidthFocused = true }
    .onChange(of: model.options) { model.scheduleEstimates() }
  }

  // MARK: Intestazione

  private var header: some View {
    HStack(spacing: 8) {
      Image(systemName: "arrow.up.left.and.arrow.down.right")
        .foregroundStyle(.secondary)
      Text(model.sources.count == 1 ? "Ridimensiona" : "Ridimensiona \(model.sources.count) file")
        .font(.system(size: 15, weight: .semibold))
    }
  }

  // MARK: Campi

  @ViewBuilder
  private func fields(_ plan: ResizePlan) -> some View {
    switch model.options.mode {
    case .dimensions: dimensionFields(plan)
    case .percent: percentFields
    case .ratio: ratioFields
    }
  }

  private func dimensionFields(_ plan: ResizePlan) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        FieldRow("Larghezza (px)") {
          TextField("Auto", text: $model.options.width.digits)
            .modifier(RadialField())
            .focused($isWidthFocused)
            .onSubmit { model.apply(plan) }
        }
        FieldRow("Altezza (px)") {
          TextField("Auto", text: $model.options.height.digits)
            .modifier(RadialField())
            .onSubmit { model.apply(plan) }
        }
      }
      SwitchRow("Mantieni le proporzioni", isOn: $model.options.keepsProportions)
      SwitchRow("Non ingrandire le immagini più piccole", isOn: $model.options.neverEnlarges)

      Text(model.options.keepsProportions
        ? "Con le proporzioni mantenute l'immagine sta dentro la misura indicata. Lascia vuoto un lato per non porre limiti."
        : "L'immagine viene stirata fino alla misura esatta.")
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var percentFields: some View {
    VStack(alignment: .leading, spacing: 10) {
      FieldRow("Percentuale della misura originale") {
        HStack(spacing: 10) {
          Slider(value: percentSlider, in: 1...200, step: 1)
          TextField("50", text: $model.options.percent.digits)
            .modifier(RadialField())
            .frame(width: 64)
            .focused($isWidthFocused)
            .onSubmit { model.apply(model.plan) }
          Text("%")
            .foregroundStyle(.secondary)
        }
      }
      HStack(spacing: 8) {
        ForEach([25, 50, 75, 150, 200], id: \.self) { value in
          Button("\(value)%") { model.options.percent = value }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
      }
    }
  }

  private var percentSlider: Binding<Double> {
    Binding(
      get: { Double(model.options.percent) },
      set: { model.options.percent = Int($0.rounded()) }
    )
  }

  private var ratioFields: some View {
    VStack(alignment: .leading, spacing: 10) {
      FieldRow("Ritaglia al centro con rapporto") {
        Picker("Rapporto", selection: ratioChoice) {
          ForEach(AspectRatio.presets) { ratio in
            Text(ratio.title).tag(ratio.id)
          }
          Text("Altro").tag(Self.customChoice)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }

      if model.options.usesCustomRatio {
        HStack(spacing: 8) {
          TextField("2", text: $model.options.customRatio.width.digits)
            .modifier(RadialField())
            .frame(width: 64)
            .focused($isWidthFocused)
          Text(":")
            .foregroundStyle(.secondary)
          TextField("1", text: $model.options.customRatio.height.digits)
            .modifier(RadialField())
            .frame(width: 64)
        }
      }

      SwitchRow("Segui l'orientamento dell'immagine", isOn: $model.options.followsOrientation)

      FieldRow("Lato lungo massimo (px)") {
        TextField("Auto", text: $model.options.longSide.digits)
          .modifier(RadialField())
          .frame(width: 120)
          .onSubmit { model.apply(model.plan) }
      }
    }
  }

  private static let customChoice = "custom"

  private var ratioChoice: Binding<String> {
    Binding(
      get: { model.options.usesCustomRatio ? Self.customChoice : model.options.ratio.id },
      set: { choice in
        if choice == Self.customChoice {
          model.options.usesCustomRatio = true
        } else if let ratio = AspectRatio.presets.first(where: { $0.id == choice }) {
          model.options.usesCustomRatio = false
          model.options.ratio = ratio
        }
      }
    )
  }

  // MARK: Compressione

  private func compression(_ plan: ResizePlan) -> some View {
    // Con file tutti PNG o TIFF non c'è qualità da scegliere.
    let isLossy = plan.jobs.isEmpty || plan.jobs.contains { $0.format.defaultQuality != nil }

    return VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 12) {
        FieldRow("Formato") {
          Picker("Formato", selection: $model.options.format) {
            Text("Come l'originale").tag(ImageFormat?.none)
            ForEach(ImageFormat.available, id: \.self) { format in
              Text(format.title).tag(ImageFormat?.some(format))
            }
          }
          .labelsHidden()
          .frame(maxWidth: 170)
        }
        FieldRow("Qualità  \(Int((model.options.quality * 100).rounded()))%") {
          Slider(value: $model.options.quality, in: ResizeOptions.qualityRange)
            .disabled(!isLossy)
        }
      }

      HStack(spacing: 10) {
        Text("Limita il peso")
        Spacer(minLength: 0)
        if model.options.limitsWeight && isLossy {
          TextField("500", text: $model.options.weight.digits)
            .modifier(RadialField())
            .frame(width: 80)
          Picker("Unità", selection: $model.options.weightUnit) {
            ForEach(ResizeOptions.WeightUnit.allCases) { unit in
              Text(unit.title).tag(unit)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .frame(width: 90)
        }
        Toggle("Limita il peso", isOn: $model.options.limitsWeight)
          .toggleStyle(.switch)
          .labelsHidden()
      }
      .disabled(!isLossy)

      if !isLossy {
        Text("PNG e TIFF sono senza perdita: per pesare meno riduci le dimensioni, oppure scegli JPEG, HEIC o AVIF.")
          .font(.system(size: 11))
          .foregroundStyle(.tertiary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  // MARK: Anteprima

  private func preview(_ plan: ResizePlan) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 8) {
        ForEach(plan.rows) { row in
          PreviewRow(row: row, estimatedBytes: model.estimatedBytes[row.source.url])
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minHeight: 90)
    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  // MARK: Piede

  private func footer(_ plan: ResizePlan) -> some View {
    HStack(spacing: 10) {
      summary(plan)
        .font(.system(size: 12))
        .lineLimit(2)

      Spacer(minLength: 8)

      Button("Annulla") {
        model.onCancel?()
      }
      .keyboardShortcut(.cancelAction)
      .buttonStyle(.glass)

      Button("Ridimensiona") {
        model.apply(plan)
      }
      .keyboardShortcut(.defaultAction)
      .buttonStyle(.glassProminent)
      .tint(.fixedAccent)
      .disabled(!plan.canApply)
    }
    .controlSize(.large)
  }

  @ViewBuilder
  private func summary(_ plan: ResizePlan) -> some View {
    if let problem = plan.options.problem {
      Text(problem).foregroundStyle(.red)
    } else {
      let count = plan.jobs.count
      let skipped = plan.skippedCount
      let base = count == 1 ? "1 immagine" : "\(count) immagini"
      Text(skipped > 0 ? "\(base), \(skipped) \(skipped == 1 ? "saltato" : "saltati")" : base)
        .foregroundStyle(.secondary)
    }
  }
}

private struct PreviewRow: View {
  let row: ResizePlan.Row
  let estimatedBytes: Int?

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(row.source.name)
        .font(.system(size: 12.5, weight: .medium))
        .lineLimit(1)
        .truncationMode(.middle)

      switch row.status {
      case .ready(let job):
        if let info = row.source.info {
          HStack(spacing: 6) {
            Text("\(Self.dimensions(info.size)) \(Image(systemName: "arrow.right")) \(Self.dimensions(job.geometry.output))")
            Spacer(minLength: 8)
            if let weight = weight(original: info.byteCount) {
              Text(weight)
            }
          }
          .font(.system(size: 11.5))
          .foregroundStyle(.secondary)
          .monospacedDigit()
        }
      case .skipped(let skip):
        Text(skip.message)
          .font(.system(size: 11.5))
          .foregroundStyle(.tertiary)
      }
    }
  }

  private static func dimensions(_ size: PixelSize) -> String {
    "\(size.width)×\(size.height)"
  }

  private func weight(original: Int?) -> String? {
    let format = { (bytes: Int) in ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }
    switch (original, estimatedBytes) {
    case (let original?, let estimate?): return "\(format(original)) → ≈ \(format(estimate))"
    case (let original?, nil): return format(original)
    case (nil, let estimate?): return "≈ \(format(estimate))"
    case (nil, nil): return nil
    }
  }
}
