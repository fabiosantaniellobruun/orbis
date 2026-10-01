import Testing
@testable import Orbis

struct ResizeOptionsTests {
  private let landscape = PixelSize(width: 4000, height: 3000)
  private let portrait = PixelSize(width: 3000, height: 4000)

  private func options(_ configure: (inout ResizeOptions) -> Void) -> ResizeOptions {
    var options = ResizeOptions()
    configure(&options)
    return options
  }

  // MARK: Dimensioni

  @Test("Con la sola larghezza l'altezza segue le proporzioni")
  func widthOnly() {
    let geometry = options { $0.width = 1200 }.geometry(for: landscape)
    #expect(geometry == ResizeGeometry(output: PixelSize(width: 1200, height: 900)))
  }

  @Test("Con la sola altezza la larghezza segue le proporzioni")
  func heightOnly() {
    let geometry = options { $0.height = 600 }.geometry(for: landscape)
    #expect(geometry.output == PixelSize(width: 800, height: 600))
  }

  @Test("Larghezza e altezza sono una scatola: ci sta sia una foto orizzontale sia una verticale")
  func fitsInsideBox() {
    let box = options {
      $0.width = 1000
      $0.height = 1000
    }
    #expect(box.geometry(for: landscape).output == PixelSize(width: 1000, height: 750))
    #expect(box.geometry(for: portrait).output == PixelSize(width: 750, height: 1000))
  }

  @Test("Le immagini più piccole non si ingrandiscono, a meno di chiederlo")
  func neverEnlarges() {
    let small = PixelSize(width: 800, height: 600)
    #expect(options { $0.width = 2000 }.geometry(for: small).output == small)

    let enlarging = options {
      $0.width = 2000
      $0.neverEnlarges = false
    }
    #expect(enlarging.geometry(for: small).output == PixelSize(width: 2000, height: 1500))
  }

  @Test("Senza misure l'immagine resta com'è (si cambia solo la compressione)")
  func noDimensions() {
    #expect(ResizeOptions().geometry(for: landscape) == ResizeGeometry(output: landscape))
  }

  @Test("Senza proporzioni l'immagine viene stirata alla misura esatta")
  func stretches() {
    let stretched = options {
      $0.keepsProportions = false
      $0.width = 500
      $0.height = 500
    }
    #expect(stretched.geometry(for: landscape).output == PixelSize(width: 500, height: 500))
    // Anche stirando, non si ingrandisce.
    #expect(stretched.geometry(for: PixelSize(width: 300, height: 800)).output == PixelSize(width: 300, height: 500))
  }

  // MARK: Percentuale

  @Test("La percentuale scala entrambi i lati, e non scende sotto un pixel")
  func percent() {
    #expect(options { $0.mode = .percent; $0.percent = 50 }.geometry(for: landscape).output == PixelSize(width: 2000, height: 1500))
    #expect(options { $0.mode = .percent; $0.percent = 150 }.geometry(for: PixelSize(width: 10, height: 10)).output == PixelSize(width: 15, height: 15))
    #expect(options { $0.mode = .percent; $0.percent = 1 }.geometry(for: PixelSize(width: 20, height: 20)).output == PixelSize(width: 1, height: 1))
  }

  // MARK: Proporzioni

  @Test("Il quadrato si ritaglia al centro")
  func squareCrop() {
    let geometry = options { $0.mode = .ratio; $0.ratio = AspectRatio(width: 1, height: 1) }.geometry(for: landscape)
    #expect(geometry.crop == PixelRect(x: 500, y: 0, width: 3000, height: 3000))
    #expect(geometry.output == PixelSize(width: 3000, height: 3000))
  }

  @Test("16:9 da una foto 4:3 toglie sopra e sotto")
  func widescreenCrop() {
    let geometry = options { $0.mode = .ratio; $0.ratio = AspectRatio(width: 16, height: 9) }.geometry(for: landscape)
    #expect(geometry.crop == PixelRect(x: 0, y: 375, width: 4000, height: 2250))
  }

  @Test("Una foto verticale prende il rapporto in verticale, se si segue l'orientamento")
  func followsOrientation() {
    let following = options { $0.mode = .ratio; $0.ratio = AspectRatio(width: 16, height: 9) }
    #expect(following.geometry(for: portrait).crop == PixelRect(x: 375, y: 0, width: 2250, height: 4000))

    let fixed = options {
      $0.mode = .ratio
      $0.ratio = AspectRatio(width: 16, height: 9)
      $0.followsOrientation = false
    }
    #expect(fixed.geometry(for: portrait).crop == PixelRect(x: 0, y: 1156, width: 3000, height: 1688))
  }

  @Test("Se l'immagine ha già il rapporto giusto non si ritaglia")
  func sameRatioKeepsWholeImage() {
    let geometry = options { $0.mode = .ratio; $0.ratio = AspectRatio(width: 4, height: 3) }.geometry(for: landscape)
    #expect(geometry == ResizeGeometry(output: landscape))
  }

  @Test("Il lato lungo massimo riduce dopo il ritaglio")
  func longSide() {
    let geometry = options {
      $0.mode = .ratio
      $0.ratio = AspectRatio(width: 1, height: 1)
      $0.longSide = 1080
    }.geometry(for: landscape)
    #expect(geometry.output == PixelSize(width: 1080, height: 1080))
    #expect(geometry.crop?.width == 3000)
  }

  @Test("Il rapporto personalizzato vale al posto di quello scelto")
  func customRatio() {
    let geometry = options {
      $0.mode = .ratio
      $0.usesCustomRatio = true
      $0.customRatio = AspectRatio(width: 2, height: 1)
    }.geometry(for: landscape)
    #expect(geometry.crop == PixelRect(x: 0, y: 500, width: 4000, height: 2000))
  }

  // MARK: Problemi e peso

  @Test("Le opzioni che non hanno senso lo dicono")
  func problems() {
    #expect(ResizeOptions().problem == nil)
    #expect(options { $0.width = 0 }.problem != nil)
    #expect(options { $0.width = 40_000 }.problem != nil)
    #expect(options { $0.keepsProportions = false; $0.width = 100 }.problem != nil)
    #expect(options { $0.mode = .percent; $0.percent = 0 }.problem != nil)
    #expect(options { $0.mode = .ratio; $0.usesCustomRatio = true; $0.customRatio = AspectRatio(width: 0, height: 1) }.problem != nil)
    // Un valore sbagliato in un modo che non si usa non conta.
    #expect(options { $0.mode = .percent; $0.width = 0 }.problem == nil)
  }

  @Test("Il peso massimo vale solo se attivato")
  func maxBytes() {
    #expect(ResizeOptions().maxBytes == nil)
    #expect(options { $0.limitsWeight = true; $0.weight = 300 }.maxBytes == 300_000)
    #expect(options { $0.limitsWeight = true; $0.weight = 2; $0.weightUnit = .megabytes }.maxBytes == 2_000_000)
  }
}
