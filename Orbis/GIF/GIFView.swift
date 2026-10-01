import AppKit
import SwiftUI

struct GIFView: View {
  @Bindable var model: GIFModel

  static let cardSize = CGSize(width: 520, height: 740)

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header

      if let info = model.info {
        content(info)
      } else if model.loadFailed {
        placeholder("Il video non si legge", symbol: "exclamationmark.triangle")
      } else {
        placeholder("Leggo il video…", symbol: nil)
      }
    }
    .padding(20)
    .frame(width: Self.cardSize.width, height: Self.cardSize.height)
    .modifier(OrbisGlass(shape: RoundedRectangle(cornerRadius: 30, style: .continuous), lightVeil: 0.72))
    .movableWindow()
    .onChange(of: model.options.previewKey) { model.scheduleSample() }
  }

  // MARK: Intestazione

  private var header: some View {
    HStack(spacing: 8) {
      Image(systemName: "film")
        .foregroundStyle(.secondary)
      Text("Video in GIF")
        .font(.system(size: 15, weight: .semibold))
      Text(model.isMultiple ? "\(model.videos.count) video" : model.first.lastPathComponent)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }

  private func placeholder(_ text: String, symbol: String?) -> some View {
    VStack(spacing: 10) {
      Spacer()
      if let symbol {
        Image(systemName: symbol)
          .font(.system(size: 22))
          .foregroundStyle(.secondary)
      } else {
        ProgressView()
          .controlSize(.small)
      }
      Text(text)
        .foregroundStyle(.secondary)
      Spacer()
      HStack {
        Spacer()
        Button("Annulla") { model.onCancel?() }
          .keyboardShortcut(.cancelAction)
          .buttonStyle(.glass)
          .controlSize(.large)
      }
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private func content(_ info: VideoInfo) -> some View {
    preview

    if model.isMultiple {
      Text("Ogni video diventa un GIF, per intero (al massimo \(GIFOptions.maxFrames) fotogrammi).")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    } else {
      range(info)
    }

    controls

    SwitchRow("Salva solo ciò che cambia tra un fotogramma e l'altro", isOn: $model.options.optimizes)

    Spacer(minLength: 0)

    footer(info)
  }

  // MARK: Anteprima

  private var preview: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(.black.opacity(0.82))

      if let sample = model.sample {
        AnimatedImage(data: sample.data)
          .padding(8)
      } else if !model.isSampling {
        Text(model.problem ?? "Anteprima non disponibile")
          .font(.system(size: 12))
          .foregroundStyle(.white.opacity(0.7))
          .multilineTextAlignment(.center)
          .padding()
      }
    }
    .frame(height: 190)
    .overlay(alignment: .topTrailing) {
      if model.isSampling {
        ProgressView()
          .controlSize(.small)
          .padding(10)
      }
    }
    .overlay(alignment: .bottomLeading) {
      Text("Anteprima: due secondi dal centro")
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.black.opacity(0.45), in: Capsule())
        .padding(8)
    }
    .environment(\.colorScheme, .dark)
  }

  // MARK: Intervallo

  private func range(_ info: VideoInfo) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      TimeRangeBar(
        start: $model.options.start,
        end: $model.options.end,
        duration: info.duration,
        thumbnails: model.thumbnails
      )
      HStack {
        Text(Self.time(model.options.start))
        Spacer()
        Text(durationLabel)
          .foregroundStyle(.primary)
        Spacer()
        Text(Self.time(model.options.end))
      }
      .font(.system(size: 11).monospacedDigit())
      .foregroundStyle(.secondary)
    }
  }

  private var durationLabel: String {
    let selected = model.options.end - model.options.start
    let text = "\(Self.seconds(selected)) s"
    guard model.options.speed != 1 else { return text }
    return "\(text) → GIF di \(Self.seconds(model.options.outputDuration)) s"
  }

  /// "1:05,3": minuti, secondi e decimi.
  static func time(_ seconds: Double) -> String {
    let tenths = Int((max(0, seconds) * 10).rounded())
    return String(format: "%d:%02d,%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
  }

  static func seconds(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "it_IT")))
  }

  // MARK: Controlli

  private var controls: some View {
    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
      GridRow {
        label("Velocità")
        Picker("Velocità", selection: $model.options.speed) {
          ForEach(GIFOptions.speeds, id: \.self) { speed in
            Text(Self.speed(speed)).tag(speed)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }

      GridRow {
        label("Misura")
        HStack(spacing: 6) {
          TextField("Auto", text: $model.options.width.digits)
            .modifier(OrbisField())
            .frame(width: 70)
          Text("×")
            .foregroundStyle(.secondary)
          TextField("Auto", text: $model.options.height.digits)
            .modifier(OrbisField())
            .frame(width: 70)
          Text("px")
            .foregroundStyle(.secondary)
          Spacer(minLength: 8)
          Picker("Proporzioni", selection: $model.options.ratio) {
            Text("Originale").tag(AspectRatio?.none)
            ForEach(GIFOptions.ratios) { ratio in
              Text(ratio.title).tag(AspectRatio?.some(ratio))
            }
          }
          .labelsHidden()
          .frame(width: 110)
        }
      }

      GridRow {
        label("Fotogrammi")
        HStack(spacing: 10) {
          Slider(value: fpsSlider, in: Double(GIFOptions.fpsRange.lowerBound)...Double(GIFOptions.fpsRange.upperBound), step: 1)
          Text("\(model.options.fps) al secondo")
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 90, alignment: .trailing)
        }
      }

      GridRow {
        label("Colori")
        Picker("Colori", selection: $model.options.colors) {
          ForEach(GIFOptions.colorChoices, id: \.self) { colors in
            Text("\(colors)").tag(colors)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }

      GridRow {
        label("Retino")
        Picker("Retino", selection: $model.options.dithering) {
          ForEach(GIFDithering.allCases) { dithering in
            Text(dithering.title).tag(dithering)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }

      GridRow {
        label("Ripetizioni")
        HStack(spacing: 10) {
          Picker("Ripetizioni", selection: $model.options.loop) {
            ForEach(GIFOptions.Loop.allCases) { loop in
              Text(loop.title).tag(loop)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          if model.options.loop == .times {
            Stepper(value: $model.options.plays, in: 2...20) {
              Text("\(model.options.plays) volte")
                .monospacedDigit()
            }
            .fixedSize()
          }
        }
      }

      GridRow {
        label("Peso massimo")
        HStack(spacing: 8) {
          if model.options.limitsWeight {
            TextField("5", text: $model.options.weight.digits)
              .modifier(OrbisField())
              .frame(width: 70)
            Picker("Unità", selection: $model.options.weightUnit) {
              ForEach(ResizeOptions.WeightUnit.allCases) { unit in
                Text(unit.title).tag(unit)
              }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 90)
            Text("riduce la misura se serve")
              .font(.system(size: 11))
              .foregroundStyle(.tertiary)
          }
          Spacer(minLength: 0)
          Toggle("Limita il peso", isOn: $model.options.limitsWeight)
            .toggleStyle(.switch)
            .labelsHidden()
        }
      }
    }
  }

  private func label(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(.secondary)
      .gridColumnAlignment(.trailing)
  }

  private var fpsSlider: Binding<Double> {
    Binding(
      get: { Double(model.options.fps) },
      set: { model.options.fps = Int($0.rounded()) }
    )
  }

  static func speed(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "it_IT"))) + "×"
  }

  // MARK: Piede

  private func footer(_ info: VideoInfo) -> some View {
    HStack(spacing: 10) {
      summary(info)
        .font(.system(size: 12))
        .lineLimit(2)

      Spacer(minLength: 8)

      Button("Annulla") {
        model.onCancel?()
      }
      .keyboardShortcut(.cancelAction)
      .buttonStyle(.glass)

      Button("Crea GIF") {
        model.apply()
      }
      .keyboardShortcut(.defaultAction)
      .buttonStyle(.glassProminent)
      .tint(.fixedAccent)
      .disabled(!model.canApply)
    }
    .controlSize(.large)
  }

  @ViewBuilder
  private func summary(_ info: VideoInfo) -> some View {
    if let problem = model.problem {
      Text(problem).foregroundStyle(.red)
    } else if let job = model.job(for: model.first) {
      let size = job.options.geometry(for: info.size).output
      let weight = model.sample.map { "≈ " + ByteCountFormatter.string(fromByteCount: Int64($0.estimatedBytes), countStyle: .file) }
      Text(["\(size.width)×\(size.height)", "\(job.options.frameCount) fotogrammi", weight].compactMap(\.self).joined(separator: " · "))
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
  }
}

/// La striscia del video con l'intervallo da tenere: si trascinano i bordi, o l'intervallo intero.
struct TimeRangeBar: View {
  @Binding var start: Double
  @Binding var end: Double
  let duration: Double
  let thumbnails: [CGImage]

  @State private var dragOrigin: (start: Double, end: Double)?

  private static let minimumLength = 0.1
  private static let height: CGFloat = 46
  private static let handleWidth: CGFloat = 12

  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      let x0 = position(start, in: width)
      let x1 = position(end, in: width)

      ZStack(alignment: .leading) {
        filmstrip(width: width)

        // Fuori dall'intervallo, velato.
        Rectangle()
          .fill(.black.opacity(0.55))
          .frame(width: max(0, x0))
        Rectangle()
          .fill(.black.opacity(0.55))
          .frame(width: max(0, width - x1))
          .offset(x: x1)

        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .strokeBorder(Color.fixedAccent, lineWidth: 3)
          .contentShape(Rectangle())
          .frame(width: max(x1 - x0, 1))
          .offset(x: x0)
          .gesture(drag(width: width) { origin, delta in
            let length = origin.end - origin.start
            let newStart = min(max(0, origin.start + delta), duration - length)
            start = newStart
            end = newStart + length
          })

        handle
          .offset(x: x0)
          .gesture(drag(width: width) { origin, delta in
            start = min(max(0, origin.start + delta), end - Self.minimumLength)
          })

        handle
          .offset(x: x1 - Self.handleWidth)
          .gesture(drag(width: width) { origin, delta in
            end = max(min(duration, origin.end + delta), start + Self.minimumLength)
          })
      }
    }
    .frame(height: Self.height)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func position(_ time: Double, in width: CGFloat) -> CGFloat {
    guard duration > 0 else { return 0 }
    return CGFloat(time / duration) * width
  }

  private func filmstrip(width: CGFloat) -> some View {
    HStack(spacing: 0) {
      if thumbnails.isEmpty {
        Rectangle().fill(.primary.opacity(0.1))
      } else {
        ForEach(thumbnails.indices, id: \.self) { index in
          Image(decorative: thumbnails[index], scale: 2)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: width / CGFloat(thumbnails.count), height: Self.height)
            .clipped()
        }
      }
    }
    .frame(width: width, height: Self.height)
  }

  private var handle: some View {
    RoundedRectangle(cornerRadius: 4, style: .continuous)
      .fill(Color.fixedAccent)
      .frame(width: Self.handleWidth, height: Self.height)
      .overlay {
        Capsule()
          .fill(.white.opacity(0.9))
          .frame(width: 2, height: 16)
      }
      .contentShape(Rectangle())
  }

  /// Un trascinamento che parte dai valori al momento della presa: così non si accumulano errori.
  private func drag(width: CGFloat, update: @escaping ((start: Double, end: Double), Double) -> Void) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        let origin = dragOrigin ?? (start, end)
        dragOrigin = origin
        update(origin, Double(value.translation.width / max(width, 1)) * duration)
      }
      .onEnded { _ in
        dragOrigin = nil
      }
  }
}

/// Un'immagine animata (il GIF di anteprima), che gira da sola.
struct AnimatedImage: NSViewRepresentable {
  let data: Data

  final class Coordinator {
    var data: Data?
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSImageView {
    let view = NSImageView()
    view.animates = true
    view.imageScaling = .scaleProportionallyUpOrDown
    view.isEditable = false
    // La misura la decide SwiftUI, non quella dell'immagine.
    for orientation in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
      view.setContentHuggingPriority(.defaultLow, for: orientation)
      view.setContentCompressionResistancePriority(.defaultLow, for: orientation)
    }
    return view
  }

  func updateNSView(_ view: NSImageView, context: Context) {
    guard context.coordinator.data != data else { return }
    context.coordinator.data = data
    view.image = NSImage(data: data)
  }
}
