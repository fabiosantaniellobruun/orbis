import Foundation

/// Un fotogramma RGBA a 8 bit per canale, riga dopo riga dall'alto; l'alfa non si usa.
nonisolated struct RGBAFrame: Sendable {
  let width: Int
  let height: Int
  var pixels: [UInt8]

  init(width: Int, height: Int, pixels: [UInt8]) {
    precondition(pixels.count == width * height * 4, "Un fotogramma RGBA ha 4 byte per pixel")
    self.width = width
    self.height = height
    self.pixels = pixels
  }
}

/// Come si simulano i colori che la palette non ha.
nonisolated enum GIFDithering: String, CaseIterable, Identifiable, Sendable {
  /// Il colore più vicino e basta: file leggeri, ma sfumature a gradini.
  case none
  /// Una trama regolare, uguale in ogni fotogramma: le zone ferme restano ferme e il file resta leggero.
  case ordered
  /// Floyd–Steinberg: sfumature più fini, ma la trama cambia da un fotogramma all'altro e pesa di più.
  case diffusion

  var id: String { rawValue }

  var title: String {
    switch self {
    case .none: "Nessuno"
    case .ordered: "Ordinato"
    case .diffusion: "Diffuso"
    }
  }
}

// MARK: - Istogramma e palette

/// Quante volte compare ogni colore, a 5 bit per canale, con la somma dei colori veri di ogni
/// casella: la palette prende la loro media, non il centro della casella.
nonisolated struct ColorHistogram: Sendable {
  private(set) var counts = [UInt32](repeating: 0, count: 1 << 15)
  private(set) var sums = [UInt64](repeating: 0, count: 3 << 15)

  var isEmpty: Bool { !counts.contains { $0 > 0 } }

  /// - Parameter step: ogni quanti pixel se ne conta uno; per i fotogrammi grandi basta un campione.
  mutating func add(_ frame: RGBAFrame, step: Int = 1) {
    let stride = max(1, step) * 4
    frame.pixels.withUnsafeBufferPointer { pixels in
      counts.withUnsafeMutableBufferPointer { counts in
        sums.withUnsafeMutableBufferPointer { sums in
          var offset = 0
          while offset < pixels.count {
            let r = Int(pixels[offset]), g = Int(pixels[offset + 1]), b = Int(pixels[offset + 2])
            let bin = (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)
            counts[bin] &+= 1
            sums[bin * 3] &+= UInt64(r)
            sums[bin * 3 + 1] &+= UInt64(g)
            sums[bin * 3 + 2] &+= UInt64(b)
            offset += stride
          }
        }
      }
    }
  }

  /// Le caselle usate, con il loro colore medio e il peso.
  fileprivate var bins: [ColorBin] {
    counts.indices.compactMap { bin in
      let count = counts[bin]
      guard count > 0 else { return nil }
      let weight = Double(count)
      return ColorBin(
        color: SIMD3(Double(sums[bin * 3]) / weight, Double(sums[bin * 3 + 1]) / weight, Double(sums[bin * 3 + 2]) / weight),
        weight: weight
      )
    }
  }
}

fileprivate nonisolated struct ColorBin {
  var color: SIMD3<Double>
  var weight: Double
}

nonisolated enum GIFPalette {
  /// La distanza tra due colori: il verde pesa di più, il blu di meno, come per l'occhio.
  @inline(__always)
  static func distance(_ r: Int, _ g: Int, _ b: Int, _ color: SIMD3<UInt8>) -> Int {
    let dr = r - Int(color.x), dg = g - Int(color.y), db = b - Int(color.z)
    return 2 * dr * dr + 4 * dg * dg + 3 * db * db
  }

  /// Al massimo `count` colori che rappresentano bene l'istogramma: taglio mediano (si divide
  /// ogni volta il gruppo più esteso e affollato), poi qualche giro di k-means per rifinire.
  /// Se i colori usati sono già pochi, la palette è esattamente quelli.
  static func make(from histogram: ColorHistogram, count: Int) -> [SIMD3<UInt8>] {
    let count = max(2, min(256, count))
    var bins = histogram.bins
    guard !bins.isEmpty else { return [SIMD3(0, 0, 0), SIMD3(255, 255, 255)] }
    if bins.count <= count {
      return bins.map { rounded($0.color) }
    }

    // Taglio mediano: ogni gruppo è un intervallo di `bins`.
    var boxes = [0..<bins.count]
    while boxes.count < count {
      var best: (index: Int, channel: Int, score: Double)?
      for (index, box) in boxes.enumerated() where box.count > 1 {
        var low = SIMD3<Double>(repeating: .infinity)
        var high = SIMD3<Double>(repeating: -.infinity)
        var weight = 0.0
        for bin in bins[box] {
          low = pointwiseMin(low, bin.color)
          high = pointwiseMax(high, bin.color)
          weight += bin.weight
        }
        let range = high - low
        let channel = range.x >= range.y && range.x >= range.z ? 0 : (range.y >= range.z ? 1 : 2)
        let score = range[channel] * weight.squareRoot()
        if score > (best?.score ?? 0) {
          best = (index, channel, score)
        }
      }
      guard let best else { break }

      let box = boxes[best.index]
      bins[box].sort { $0.color[best.channel] < $1.color[best.channel] }
      let total = bins[box].reduce(0) { $0 + $1.weight }
      var cumulative = 0.0
      var split = box.lowerBound + 1
      for position in box {
        cumulative += bins[position].weight
        if cumulative >= total / 2 {
          split = position + 1
          break
        }
      }
      split = min(max(split, box.lowerBound + 1), box.upperBound - 1)
      boxes[best.index] = box.lowerBound..<split
      boxes.append(split..<box.upperBound)
    }

    var palette = boxes.map { box -> SIMD3<Double> in
      var sum = SIMD3<Double>(repeating: 0)
      var weight = 0.0
      for bin in bins[box] {
        sum += bin.color * bin.weight
        weight += bin.weight
      }
      return sum / max(weight, 1)
    }

    // K-means: ogni casella va al colore più vicino, e ogni colore diventa la media delle sue.
    for _ in 0..<3 {
      var sums = [SIMD3<Double>](repeating: SIMD3(repeating: 0), count: palette.count)
      var weights = [Double](repeating: 0, count: palette.count)
      for bin in bins {
        var nearest = 0
        var nearestDistance = Double.infinity
        for (index, color) in palette.enumerated() {
          let delta = bin.color - color
          let distance = 2 * delta.x * delta.x + 4 * delta.y * delta.y + 3 * delta.z * delta.z
          if distance < nearestDistance {
            nearestDistance = distance
            nearest = index
          }
        }
        sums[nearest] += bin.color * bin.weight
        weights[nearest] += bin.weight
      }
      for index in palette.indices where weights[index] > 0 {
        palette[index] = sums[index] / weights[index]
      }
    }
    return palette.map(rounded)
  }

  private static func rounded(_ color: SIMD3<Double>) -> SIMD3<UInt8> {
    SIMD3(
      UInt8(min(255, max(0, color.x.rounded()))),
      UInt8(min(255, max(0, color.y.rounded()))),
      UInt8(min(255, max(0, color.z.rounded())))
    )
  }
}

// MARK: - Scrittura

nonisolated struct GIFSettings: Sendable, Equatable {
  var dithering = GIFDithering.diffusion
  /// Scrive solo i pixel che cambiano rispetto al fotogramma prima (gli altri trasparenti), e solo
  /// il rettangolo che li contiene.
  var optimizes = true
  /// `nil`: si riproduce una volta. 0: all'infinito. N: si ripete N volte dopo la prima.
  var repeats: Int? = 0
}

/// Scrive un GIF animato un fotogramma alla volta, con una palette sola per tutti.
nonisolated final class GIFWriter {
  let width: Int
  let height: Int
  let settings: GIFSettings

  private let palette: [SIMD3<UInt8>]
  /// L'indice dei pixel che non cambiano, dopo i colori; `nil` senza ottimizzazione.
  private let transparentIndex: Int?
  private let tableBits: Int
  private var data = Data()
  /// Il colore oggi visibile in ogni pixel (indice nella palette).
  private var canvas: [UInt8]
  private var hasFirstFrame = false
  private var pending: PendingFrame?
  private var lookup: NearestColorCache
  private(set) var frameCount = 0

  private struct PendingFrame {
    var delay: Int
    var transparent: Bool
    var body: Data
  }

  /// - Parameter palette: i colori, al massimo 256 (255 se `settings.optimizes`, per la trasparenza).
  init(width: Int, height: Int, palette: [SIMD3<UInt8>], settings: GIFSettings) {
    precondition(width > 0 && height > 0 && width <= 65_535 && height <= 65_535)
    let colors = Array(palette.prefix(settings.optimizes ? 255 : 256))
    self.width = width
    self.height = height
    self.settings = settings
    self.palette = colors
    self.transparentIndex = settings.optimizes ? colors.count : nil
    let entries = colors.count + (settings.optimizes ? 1 : 0)
    var bits = 1
    while (1 << bits) < entries { bits += 1 }
    self.tableBits = bits
    self.canvas = [UInt8](repeating: 0, count: width * height)
    self.lookup = NearestColorCache(palette: colors)
    writeHeader()
  }

  /// - Parameter delay: quanto resta a schermo, in centesimi di secondo.
  func add(_ frame: RGBAFrame, delay: Int) {
    precondition(frame.width == width && frame.height == height, "Tutti i fotogrammi hanno la stessa misura")
    let indices = quantize(frame)

    guard hasFirstFrame, let transparentIndex else {
      flushPending()
      pending = PendingFrame(delay: delay, transparent: false, body: imageBody(indices, rect: (0, 0, width, height)))
      hasFirstFrame = true
      return
    }

    // Solo il rettangolo che contiene ciò che è cambiato.
    var minX = width, minY = height, maxX = -1, maxY = -1
    indices.withUnsafeBufferPointer { indices in
      for y in 0..<height {
        let row = y * width
        for x in 0..<width where Int(indices[row + x]) != transparentIndex {
          if x < minX { minX = x }
          if x > maxX { maxX = x }
          if y < minY { minY = y }
          if y > maxY { maxY = y }
        }
      }
    }

    guard maxX >= 0 else {
      // Nulla è cambiato: il fotogramma prima resta a schermo più a lungo.
      pending?.delay += delay
      return
    }

    let rect = (minX, minY, maxX - minX + 1, maxY - minY + 1)
    var cropped = [UInt8]()
    cropped.reserveCapacity(rect.2 * rect.3)
    for y in minY...maxY {
      cropped.append(contentsOf: indices[(y * width + minX)...(y * width + maxX)])
    }
    flushPending()
    pending = PendingFrame(delay: delay, transparent: true, body: imageBody(cropped, rect: rect))
  }

  func finish() -> Data {
    flushPending()
    data.append(0x3B)
    return data
  }

  // MARK: Colori

  private static let bayer: [Double] = {
    let matrix: [Int] = [
      0, 32, 8, 40, 2, 34, 10, 42, 48, 16, 56, 24, 50, 18, 58, 26,
      12, 44, 4, 36, 14, 46, 6, 38, 60, 28, 52, 20, 62, 30, 54, 22,
      3, 35, 11, 43, 1, 33, 9, 41, 51, 19, 59, 27, 49, 17, 57, 25,
      15, 47, 7, 39, 13, 45, 5, 37, 63, 31, 55, 23, 61, 29, 53, 21,
    ]
    return matrix.map { (Double($0) + 0.5) / 64 - 0.5 }
  }()

  /// Gli indici della palette per ogni pixel; con l'ottimizzazione, `transparentIndex` dove si può
  /// tenere ciò che già si vede.
  private func quantize(_ frame: RGBAFrame) -> [UInt8] {
    var output = [UInt8](repeating: 0, count: width * height)
    let comparesWithCanvas = hasFirstFrame && transparentIndex != nil
    let transparent = UInt8(transparentIndex ?? 0)
    // Un colore già a schermo si tiene se è buono quasi quanto il nuovo: le zone ferme restano
    // ferme anche quando il video ha un po' di rumore.
    let tolerance = 300
    // L'ampiezza della trama ordinata: più la palette è povera, più serve.
    let spread = 255 / Foundation.pow(Double(palette.count), 1.0 / 3.0) * 0.3
    let dithering = settings.dithering
    let strength = 0.875

    // Errore da distribuire, per la riga in corso e la prossima (con un pixel di margine per lato).
    var current = [Double](repeating: 0, count: (width + 2) * 3)
    var next = current

    frame.pixels.withUnsafeBufferPointer { pixels in
      output.withUnsafeMutableBufferPointer { output in
        canvas.withUnsafeMutableBufferPointer { canvas in
          for y in 0..<height {
            if dithering == .diffusion {
              swap(&current, &next)
              for index in next.indices { next[index] = 0 }
            }
            let leftToRight = dithering != .diffusion || y % 2 == 0
            let step = leftToRight ? 1 : -1
            var x = leftToRight ? 0 : width - 1

            for _ in 0..<width {
              let pixel = y * width + x
              let source = pixel * 4
              let sr = Int(pixels[source]), sg = Int(pixels[source + 1]), sb = Int(pixels[source + 2])
              var r = Double(sr), g = Double(sg), b = Double(sb)

              switch dithering {
              case .none:
                break
              case .ordered:
                let bias = Self.bayer[(y & 7) * 8 + (x & 7)] * spread
                r += bias
                g += bias
                b += bias
              case .diffusion:
                let slot = (x + 1) * 3
                r += current[slot]
                g += current[slot + 1]
                b += current[slot + 2]
              }

              let ir = Int(min(255, max(0, r.rounded())))
              let ig = Int(min(255, max(0, g.rounded())))
              let ib = Int(min(255, max(0, b.rounded())))
              var chosen = lookup.nearest(ir, ig, ib)
              var keeps = false

              if comparesWithCanvas {
                let shown = Int(canvas[pixel])
                if shown == chosen {
                  keeps = true
                } else if GIFPalette.distance(sr, sg, sb, palette[shown]) <= GIFPalette.distance(sr, sg, sb, palette[chosen]) + tolerance {
                  keeps = true
                  chosen = shown
                }
              }

              if keeps {
                output[pixel] = transparent
              } else {
                output[pixel] = UInt8(chosen)
                canvas[pixel] = UInt8(chosen)
              }

              if dithering == .diffusion {
                let color = palette[chosen]
                let er = (r - Double(color.x)) * strength
                let eg = (g - Double(color.y)) * strength
                let eb = (b - Double(color.z)) * strength
                let ahead = (x + 1 + step) * 3
                let behind = (x + 1 - step) * 3
                let here = (x + 1) * 3
                current[ahead] += er * 7 / 16
                current[ahead + 1] += eg * 7 / 16
                current[ahead + 2] += eb * 7 / 16
                next[behind] += er * 3 / 16
                next[behind + 1] += eg * 3 / 16
                next[behind + 2] += eb * 3 / 16
                next[here] += er * 5 / 16
                next[here + 1] += eg * 5 / 16
                next[here + 2] += eb * 5 / 16
                next[ahead] += er / 16
                next[ahead + 1] += eg / 16
                next[ahead + 2] += eb / 16
              }
              x += step
            }
          }
        }
      }
    }
    return output
  }

  // MARK: Blocchi

  private func writeHeader() {
    data.append(contentsOf: Array("GIF89a".utf8))
    appendWord(width)
    appendWord(height)
    // Tabella dei colori globale, 8 bit per canale, grandezza 2^tableBits.
    data.append(0x80 | 0x70 | UInt8(tableBits - 1))
    data.append(0) // colore di sfondo
    data.append(0) // proporzioni dei pixel
    for index in 0..<(1 << tableBits) {
      let color = index < palette.count ? palette[index] : SIMD3<UInt8>(0, 0, 0)
      data.append(contentsOf: [color.x, color.y, color.z])
    }

    if let repeats = settings.repeats {
      data.append(contentsOf: [0x21, 0xFF, 0x0B])
      data.append(contentsOf: Array("NETSCAPE2.0".utf8))
      data.append(contentsOf: [0x03, 0x01])
      appendWord(min(repeats, 65_535))
      data.append(0x00)
    }
  }

  private func flushPending() {
    guard let pending else { return }
    // Graphic Control Extension: il fotogramma resta dov'è (disposal 1), eventuale trasparenza.
    data.append(contentsOf: [0x21, 0xF9, 0x04])
    data.append(UInt8(1 << 2) | (pending.transparent ? 1 : 0))
    appendWord(min(max(pending.delay, 2), 65_535))
    data.append(UInt8(transparentIndex ?? 0))
    data.append(0x00)
    data.append(pending.body)
    frameCount += 1
    self.pending = nil
  }

  private func imageBody(_ indices: [UInt8], rect: (x: Int, y: Int, width: Int, height: Int)) -> Data {
    var body = Data()
    body.append(0x2C)
    for value in [rect.x, rect.y, rect.width, rect.height] {
      body.append(UInt8(value & 0xFF))
      body.append(UInt8(value >> 8))
    }
    body.append(0x00) // niente tabella locale, niente interlacciamento

    let minimumCodeSize = max(2, tableBits)
    body.append(UInt8(minimumCodeSize))
    let compressed = LZW.encode(indices, minimumCodeSize: minimumCodeSize)
    var offset = 0
    while offset < compressed.count {
      let length = min(255, compressed.count - offset)
      body.append(UInt8(length))
      body.append(contentsOf: compressed[offset..<(offset + length)])
      offset += length
    }
    body.append(0x00)
    return body
  }

  private func appendWord(_ value: Int) {
    data.append(UInt8(value & 0xFF))
    data.append(UInt8((value >> 8) & 0xFF))
  }
}

/// Il colore più vicino della palette, ricordato per ogni casella a 6 bit per canale: in un video
/// gli stessi colori tornano di continuo, e cercarli ogni volta tra 256 costerebbe troppo.
nonisolated struct NearestColorCache {
  private let palette: [SIMD3<UInt8>]
  private var table: [Int16]

  init(palette: [SIMD3<UInt8>]) {
    self.palette = palette
    self.table = [Int16](repeating: -1, count: 1 << 18)
  }

  mutating func nearest(_ r: Int, _ g: Int, _ b: Int) -> Int {
    let key = (r >> 2) << 12 | (g >> 2) << 6 | (b >> 2)
    let cached = table[key]
    if cached >= 0 { return Int(cached) }

    // Il centro della casella: il risultato non dipende da quale colore l'ha vista per primo.
    let cr = (r & ~3) | 2, cg = (g & ~3) | 2, cb = (b & ~3) | 2
    var best = 0
    var bestDistance = Int.max
    for (index, color) in palette.enumerated() {
      let distance = GIFPalette.distance(cr, cg, cb, color)
      if distance < bestDistance {
        bestDistance = distance
        best = index
      }
    }
    table[key] = Int16(best)
    return best
  }
}

// MARK: - LZW

nonisolated enum LZW {
  /// La compressione dei GIF: codici a lunghezza variabile da `minimumCodeSize + 1` a 12 bit,
  /// scritti dal bit meno significativo. Il flusso comincia con un codice di azzeramento e finisce
  /// con quello di fine.
  static func encode(_ indices: [UInt8], minimumCodeSize: Int) -> [UInt8] {
    let clearCode = 1 << minimumCodeSize
    let endCode = clearCode + 1
    var codeSize = minimumCodeSize + 1
    var nextCode = endCode + 1

    var output = [UInt8]()
    output.reserveCapacity(indices.count / 2 + 16)
    var buffer: UInt32 = 0
    var bitCount = 0

    func emit(_ code: Int) {
      buffer |= UInt32(code) << UInt32(bitCount)
      bitCount += codeSize
      while bitCount >= 8 {
        output.append(UInt8(buffer & 0xFF))
        buffer >>= 8
        bitCount -= 8
      }
    }

    // Tabella a indirizzamento aperto: chiave (prefisso << 8 | byte) → codice.
    let capacity = 1 << 13
    var keys = [Int32](repeating: -1, count: capacity)
    var codes = [Int16](repeating: 0, count: capacity)

    func slot(for key: Int32) -> Int {
      var index = Int((UInt32(bitPattern: key) &* 2_654_435_761) >> 19)
      while keys[index] != -1 && keys[index] != key {
        index = (index + 1) & (capacity - 1)
      }
      return index
    }

    emit(clearCode)
    guard var prefix = indices.first.map(Int.init) else {
      emit(endCode)
      if bitCount > 0 { output.append(UInt8(buffer & 0xFF)) }
      return output
    }

    for value in indices.dropFirst() {
      let key = Int32(prefix << 8 | Int(value))
      let index = slot(for: key)
      if keys[index] == key {
        prefix = Int(codes[index])
        continue
      }

      emit(prefix)
      if nextCode < 4096 {
        keys[index] = key
        codes[index] = Int16(nextCode)
        nextCode += 1
        // Il decodificatore allarga i codici un passo dopo: lo si segue.
        if nextCode > (1 << codeSize) && codeSize < 12 {
          codeSize += 1
        }
      } else {
        emit(clearCode)
        for position in keys.indices { keys[position] = -1 }
        codeSize = minimumCodeSize + 1
        nextCode = endCode + 1
      }
      prefix = Int(value)
    }

    emit(prefix)
    // Leggendo l'ultimo codice il decodificatore aggiunge una voce, e può allargare i codici
    // prima di leggere quello di fine.
    if nextCode == (1 << codeSize) && codeSize < 12 {
      codeSize += 1
    }
    emit(endCode)
    if bitCount > 0 {
      output.append(UInt8(buffer & 0xFF))
    }
    return output
  }
}
