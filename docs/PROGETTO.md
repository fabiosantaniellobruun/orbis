# Orbis — note di progetto

App da barra dei menu per macOS 26+. Mentre si trascinano dei file, tenendo premuto un tasto
(Shift, di base) compare attorno al puntatore un anello di bottoni in vetro: si rilasciano i file
su un bottone per eseguire l'azione.

Fino all'ottobre 2026 si chiamava Radial: il nome era già usato, ed è cambiato prima della prima
release. Commit e rami vecchi parlano ancora di Radial.

Questo documento raccoglie le decisioni prese e il perché, lo stato dei lavori e come si lavora sul
codice. Per usare l'app, vedi il [README](../README.it.md).

## Stato

| # | Fase | Stato |
|---|------|-------|
| 1 | Prototipo di verifica | fatto |
| 2 | Menu radiale: secondo anello, bordi dello schermo | fatto (le voci di Converti in dipendono dai file; manca: azioni filtrate per tipo di file) |
| 3 | Azioni immediate: Clona, Comprimi, Copia percorso, Cestina, con Annulla | fatto |
| 4 | Rinomina in serie | fatto |
| 5 | Sposta, con cartelle recenti e preferite | fatto |
| 6 | Converti in, per le immagini (PNG, JPEG, HEIC, AVIF, TIFF) | fatto |
| 7 | Impostazioni: tasto, menu aperto, avvio al login, cartelle preferite | fatto (manca: ordine delle azioni) |
| 8 | Distribuzione: versione, DMG, script di rilascio, benvenuto al primo avvio | fatto: DMG firmato ad hoc, senza notarizzazione (scelta, vedi Decisioni) |
| 9 | Ridimensiona: dimensioni, percentuale, proporzioni, qualità e peso massimo | fatto |
| 10 | Video in GIF, con tutti i controlli | fatto |
| 11 | Interfaccia in inglese | da fare, prima di promuovere l'app fuori dall'Italia |

## Decisioni

- **Selezione per settore angolare**: conta la direzione in cui ci si muove, non la mira sul bottone.
  Al centro c'è una zona morta; uscendo dall'anello il menu si chiude e il trascinamento prosegue.
- **Il tasto che apre il menu è configurabile** (Impostazioni → Generale). Di base è Shift, da solo.
  Può essere una combinazione di soli modificatori (⇧, ⌥⇧, ⌃⌥…) oppure dei modificatori più un
  tasto normale. Lo stato dei tasti viene letto (`NSEvent.modifierFlags`,
  `CGEventSource.keyState`), non intercettato: non servono permessi.
  - I modificatori devono essere *esattamente* quelli scelti: con ⌘ o ⌥ in più si è in un'altra
    combinazione, e il Finder cambia il significato del trascinamento (sposta, copia, alias).
  - Un tasto normale arriva anche all'app da cui si trascina. Lo spazio, per esempio, apre
    l'anteprima rapida nel Finder: per questo di base non si usa.
  - Con ⌘ il Finder ammette solo lo spostamento e Orbis rifiuta il rilascio (non accetta mai
    `.move`, per non far toccare gli originali): l'impostazione lo segnala.
- **Niente sandbox, fuori dal Mac App Store**: rinomina e spostamento in sandbox sono molto limitati.
- **Distribuzione da GitHub Releases e dalla landing, senza notarizzazione.** Notarizzare richiede
  l'Apple Developer Program (99 $ l'anno), anche fuori dallo Store: per ora non lo si usa. Il DMG è
  firmato ad hoc (su Apple silicon un'app senza firma non parte nemmeno), e chi lo scarica deve
  autorizzare Orbis una volta in Privacy e sicurezza; README e landing lo spiegano. Se un giorno
  si notarizza, lo script è già pronto (`docs/RELEASING.md`).
- **Repository pubblico con licenza MIT**, README principale in inglese (`README.md`) e la versione
  italiana accanto (`README.it.md`). L'interfaccia dell'app per ora è in italiano.
- **Nessun permesso, nessuna rete, nessuna telemetria.** I messaggi nel registro di sistema che
  possono contenere nomi di file sono privati (`privacy: .private`).
- **Tema chiaro o scuro secondo il sistema**. Nel tema chiaro un velo bianco sotto le icone tiene
  il vetro chiaro anche sugli sfondi scuri, dove altrimenti le icone scure si perderebbero.
- **Icona** in formato Icon Composer (`Orbis/AppIcon.icon`), ricavata da `Orbis icon.png` (una foto di
  Sean Sinclair su Unsplash, citata nei crediti del README; 2048 px,
  a pieno campo): macOS la ritaglia nel quadrato arrotondato e le dà i riflessi di vetro. Il livello
  è opaco: con la traslucenza attiva i colori si slavano sul fondo. Per cambiarla basta sostituire
  `Assets/OrbisIcon.png` (1024 px), oppure aprire la cartella con Icon Composer.
- **I pannelli con cui si interagisce si spostano** (`movableWindow()` in `OrbisGlass.swift`),
  trascinandoli da un punto libero. L'anello e l'avviso seguono il puntatore e non si spostano.
  `isMovableByWindowBackground` non basta: il contenuto SwiftUI se ne prende gli eventi.
- **Secondo anello** per le azioni con opzioni: passando su un bottone che ne ha, si apre un arco di
  voci oltre l'anello, e si rilascia su una di quelle. Il bottone da solo non è un bersaglio. Le
  voci stanno sul lato del loro bottone, con l'etichetta sul lato esterno. Di base Sposta sta a
  sinistra, Converti in a destra, Cestina in basso, lontana da tutte e due.
  Vicino a un bordo dello schermo non c'è posto per le etichette (servono circa 455 punti di lato):
  invece di capovolgere l'arco, che diventerebbe irraggiungibile perché bisognerebbe attraversare
  il centro (e lì il sottomenu si chiude), sono le due voci ad andare dalla parte che ha posto
  (`OrbisAction.layout`). Rinomina sta sempre in alto. In verticale il pannello si sposta di
  quanto serve perché stia l'arco. Il prezzo è che la posizione di Sposta cambia con il punto
  in cui si trascina: se dà fastidio, si può passare a un solo lato.
- **Sposta**: prima le due cartelle usate più di recente, poi le quattro preferite scelte
  dall'utente, poi "Scegli cartella…". Ogni voce mostra il nome e, in piccolo, il percorso completo
  con la casa abbreviata (`~/Sites/Clienti/Rossi`), perché spesso più cartelle hanno lo stesso
  nome. Una cartella già preferita non occupa anche un posto tra le recenti; quelle che non
  esistono più saltano. Se il nome esiste già nella destinazione il file arriva come "nome 2",
  come "Mantieni entrambi" del Finder; non si sovrascrive mai.
- **Converti in** usa solo ciò che il sistema sa scrivere (ImageIO): PNG, JPEG, HEIC, AVIF, TIFF. Il
  WebP non c'è: macOS lo legge ma non lo scrive, e chi lavora sul web lo produce già dalla propria
  toolchain. Il file nuovo arriva accanto all'originale, che resta; le trasparenze verso JPEG
  finiscono su fondo bianco (senza, il fondo diventerebbe nero); orientamento e metadati
  (data di scatto, posizione) si conservano; di un'immagine animata si prende il primo fotogramma.
- **Le voci di Converti in dipendono dai file trascinati**: GIF per i video, le scale PNG per gli
  SVG, i formati per le altre immagini (nel menu di prova GIF e formati).
- **SVG in PNG a 1x, 2x, 3x, 4x**, o tutte e quattro insieme, con i nomi alla maniera di Apple
  (`logo.png`, `logo@2x.png`…) e la risoluzione dichiarata di 72 dpi per scala. ImageIO non legge
  gli SVG: li apre `NSImage` (come immagini vettoriali) e li disegna in un contesto ingrandito, quindi
  a ogni scala il disegno è nitido. 1x è la misura scritta nell'SVG (larghezza e altezza, o il
  viewBox); oltre 16384 pixel per lato non si esporta.
- **Onda al rilascio**, come un sasso nell'acqua (`WaterRipple`): dal bordo del bottone scelto
  partono tre creste di vetro che si allargano e si spengono (lunghezza d'onda 30, velocità 290
  punti al secondo, vita 0,3 s, gli stessi valori della landing). Il vetro del sistema rifrange ciò
  che c'è sotto; un filo rosso fuori e uno azzurro dentro ogni cresta danno l'aberrazione cromatica
  dell'icona. Uno shader che deformi davvero le finestre sotto richiederebbe il permesso di
  registrazione dello schermo (che macOS chiede di riconfermare periodicamente): per ora no. La
  lente olografica di prima (`HoloRipple`) è stata tolta. Con "Riduci movimento" l'onda non compare.
- Preferenza `stickyMenu`: il menu resta aperto dopo aver rilasciato il tasto.
- **Primo avvio**: l'app non ha icona nel Dock, quindi una finestra di benvenuto spiega come si usa
  (una volta sola; si riapre da "Come si usa…" nel menu).

## Cosa ha dimostrato il prototipo

- Il trascinamento di file si riconosce senza permessi: monitor globale del mouse più il contatore
  della pasteboard di trascinamento.
- Un pannello che compare sotto il puntatore a trascinamento già iniziato riceve il rilascio,
  con gli URL dei file.
- Il vetro (`glassEffect`) si disegna correttamente in un pannello trasparente sopra scrivania
  e finestre.
- Il pannello non è mai la finestra attiva, quindi il sistema toglie la tinta al vetro: il colore
  del bottone evidenziato è un riempimento, non `Glass.tint`.
- `scaleEffect` applicato dopo `glassEffect` stacca il vetro dal contenuto: le dimensioni
  si cambiano con il frame.

## Come sono fatte le azioni

- `FileOperations` fa il lavoro sui file, fuori dal thread principale, e non sa nulla dell'interfaccia.
- `ActionRunner` sceglie l'operazione, compone il messaggio e dice come annullare (`UndoStep`).
- Cestina usa `NSWorkspace.recycle`, la chiamata del Finder: con `FileManager.trashItem` il file
  finiva nel Cestino ma "Ripristina" del Finder restava grigio.
- Annullare una copia, un archivio o una conversione li mette nel Cestino, non li cancella.
  Annullare Cestina rimette i file dov'erano, senza sovrascrivere ciò che nel frattempo ha preso
  quel nome. Lo stesso per Sposta e Rinomina.
- L'avviso vive in un pannello suo (`ToastController`), piccolo, che sopravvive al menu.

## Rinomina

- La logica dei nomi (`RenamePlan`) non tocca il disco e si ricalcola a ogni tasto. Segnala nome
  vuoto, caratteri non validi (`/` e `:`), nome troppo lungo, due elementi con lo stesso nome e
  nome già occupato da un elemento estraneo. Basta un problema per spegnere il pulsante.
- L'estensione non viene mai toccata. Nelle cartelle il punto fa parte del nome.
- L'ordine di numerazione è "Come nel Finder", per nome (naturale: 2 prima di 10), per data di
  creazione o di modifica.
- `FileOperations.rename` non sovrascrive mai. Quando un nome nuovo è il vecchio nome di un altro
  elemento del gruppo (scambi, scorrimento di numeri, sole maiuscole) mette prima da parte gli
  elementi coinvolti con un nome provvisorio (`.orbis-…`) e poi li porta al nome finale.
- Annulla rimette i nomi di prima, con la stessa procedura.
- Il pannello (`FormPanel`) può ricevere la tastiera. Orbis si attiva mentre è aperto e restituisce
  il focus all'app di prima quando si chiude.

## Ridimensiona

Un pannello come quello di Rinomina (`FormPanelHost` è in comune), con tre modi e, sotto, la
compressione. Il file nuovo arriva accanto all'originale come "foto ridimensionata.jpg"; Annulla lo
mette nel Cestino.

- **Dimensioni**: larghezza e altezza sono una scatola in cui l'immagine deve stare, e un lato
  vuoto non pone limiti. Così una misura vale per un gruppo di foto orizzontali e verticali
  insieme, cosa che un lucchetto alla Photoshop (che ricalcola l'altro lato su un'immagine sola)
  non sa fare. Senza proporzioni l'immagine si stira alla misura esatta. "Non ingrandire" è attivo
  di base: le immagini già piccole restano come sono.
- **Percentuale**: da 1 a 500; qui ingrandire è voluto.
- **Proporzioni**: ritaglio al centro con 1:1, 4:3, 3:2, 16:9, 5:4 o un rapporto a scelta, più un
  lato lungo massimo. "Segui l'orientamento" (attivo) dà 3:4 a una foto verticale quando si sceglie
  4:3, così non servono le versioni verticali dei rapporti; il quadrato conta come orizzontale.
- **Compressione**: formato (come l'originale, o uno di quelli di Converti in), qualità per JPEG,
  HEIC e AVIF, e un peso massimo facoltativo. Col peso massimo si cerca per bisezione la qualità
  più alta che lo rispetta, partendo da quella scelta e senza scendere sotto il 10%; se non basta,
  il file si scrive lo stesso e l'avviso lo dice ("resta sopra il peso richiesto").
- **Anteprima**: per ogni file, misure prima e dopo; per i primi quattro anche il peso stimato,
  calcolato scrivendo davvero l'immagine in memoria, un attimo dopo che si è smesso di scrivere.
- **Cosa si salta**: file che non sono immagini, immagini a più fotogrammi (GIF animate, sequenze
  HEIC), formati che il Mac non sa scrivere se non se ne sceglie un altro, e le immagini senza
  perdita che resterebbero identiche (stesse misure, stesso formato): riscriverle darebbe lo stesso
  file, spesso più pesante.
- **Pixel**: l'orientamento EXIF si applica ai pixel e si toglie dai metadati (altrimenti la foto
  si girerebbe due volte); il resto dei metadati resta. Le riduzioni proporzionali passano da
  `CGImageSourceCreateThumbnailAtIndex`, che riduce bene senza caricare l'immagine intera; ritagli,
  ingrandimenti e stiramenti da un `CGContext` ad alta interpolazione. L'uscita è a 8 bit per
  canale, nello spazio colore dell'originale.

## Video in GIF

Dal secondo anello di **Converti in**: la voce GIF compare quando tra i file trascinati c'è un
video (per saperlo, all'apertura dell'anello si leggono i file della pasteboard di trascinamento;
nel menu di prova compaiono tutte le voci). Il pannello ha:

- **Anteprima vera**: due secondi dal centro dell'intervallo, codificati con le stesse opzioni del
  file finale e animati nel pannello; dal loro peso si stima quello del GIF intero. Si rifà un
  attimo dopo che le opzioni smettono di cambiare (ripetizioni e peso massimo non la toccano).
- **Intervallo** su una striscia di miniature: si trascinano i bordi, o l'intervallo intero. Si
  parte dai primi dieci secondi. Con più video non c'è intervallo: ognuno va per intero, fino a
  1500 fotogrammi.
- **Velocità** (0,5×–4×), **misura** (larghezza e altezza come scatola, senza ingrandire; 480 px di
  base) e **proporzioni** (originale, 1:1, 4:3, 16:9, 9:16, 4:5, ritaglio al centro),
  **fotogrammi al secondo** (5–30, 15 di base), **colori** (16–256), **retino**, **ripetizioni**
  (sempre, una volta, N volte), **peso massimo**, e "salva solo ciò che cambia".

**Motore: tutto nostro, niente ffmpeg.** Peso, licenze (LGPL/GPL) e distribuzione pesano più del
vantaggio, e il GIF di ImageIO non lascia scegliere palette, retino e ottimizzazione. Quindi:

- `VideoReader` decodifica il video in ordine con `AVAssetReader` (molto più veloce che chiedere i
  fotogrammi uno per uno) e consegna, per ogni istante, il fotogramma che in quel momento è a
  schermo. Core Image lo ruota come va visto (i video girati in verticale sono salvati in
  orizzontale), lo ritaglia e lo riduce, in sRGB.
- Due passaggi sul video: il primo, su una cinquantina di fotogrammi, raccoglie l'istogramma dei
  colori; il secondo scrive. Nessun fotogramma resta in memoria, e la durata non pesa sulla RAM.
- **Palette** unica per tutto il GIF: taglio mediano sull'istogramma a 5 bit per canale, poi tre giri
  di k-means. Se i colori usati sono pochi, la palette è esattamente quelli. La distanza tra i
  colori pesa di più il verde e di meno il blu.
- **Retino**: nessuno (gradini nel cielo), ordinato (matrice di Bayer 8×8, uguale in ogni
  fotogramma: le zone ferme restano ferme) o diffuso (Floyd–Steinberg a serpentina, all'87,5%, il
  più morbido e il predefinito). Provati sul video del Golden Gate di sistema: il diffuso è il
  migliore sulle sfumature; l'ordinato a metà ampiezza è discreto a 256 colori.
- **Ottimizzazione**: un pixel si lascia trasparente (resta quello del fotogramma prima) se il
  colore già a schermo è buono quasi quanto il nuovo; si scrive solo il rettangolo che contiene i
  cambiamenti; un fotogramma senza cambiamenti si fonde con il precedente, che resta a schermo più
  a lungo.
- **LZW** con codici da 3 a 12 bit e azzeramento a tabella piena; il test lo verifica con un
  decodificatore scritto a parte. Tempi in centesimi di secondo, con gli arrotondamenti compensati.
  Ripetizioni con l'estensione NETSCAPE (ImageIO riporta il numero di riproduzioni, cioè una in più).
- **Peso massimo**: se il GIF pesa troppo si riduce la misura (il peso va circa con i pixel) e si
  riprova, fino a quattro volte; se non basta, il file si scrive lo stesso e l'avviso lo dice.

Il file arriva accanto al video ("clip.gif"), con Annulla. Durante la scrittura l'avviso mostra la
percentuale.

## Sviluppo

Serve Xcode 27 o successivo (SDK di macOS 26).

```bash
xcodebuild -project Orbis.xcodeproj -scheme Orbis -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Orbis.app
```

```bash
xcodebuild test -project Orbis.xcodeproj -scheme Orbis -derivedDataPath build -destination 'platform=macOS'
```

I test lavorano in cartelle temporanee. Quelli sul Cestino cestinano e ripristinano file di prova.

- `--preview` all'avvio mostra il menu al centro dello schermo, pilotato dal mouse.
- `--welcome` mostra la finestra di benvenuto anche se è già stata vista.
- `--run <azione> <percorsi…>` (solo Debug, da mettere per ultimo) esegue un'azione senza passare
  dal menu: `clone`, `compress`, `copyPath`, `trash`, `rename` e `resize` (aprono il pannello).
  Per `move` il primo percorso è la cartella di destinazione, per `convert` il formato (`png`,
  `jpeg`, `heic`, `avif`, `tiff`, `gif` per aprire il pannello del GIF su un video, `svg:1`…`svg:4`
  o `svg:all` per gli SVG), per `resize` può essere una larghezza massima in pixel (e allora
  il pannello non si apre); gli altri sono i file.
- `--snapshot <percorso.png>` (solo Debug, prima di `--run`) dopo due secondi fotografa dall'interno
  le finestre visibili (`percorso.1.png`, `.2.png`…): serve a controllare l'impaginazione dei
  pannelli senza permessi di registrazione dello schermo. Il vetro, gli slider e i selettori
  segmentati non escono: li compone il sistema. `ORBIS_SNAPSHOT_DELAY=<secondi>` aspetta di più
  (per esempio che il pannello del GIF abbia letto il video e fatto l'anteprima). `ORBIS_RESIZE_MODE=dimensions|percent|ratio`
  (con `open --env`) apre Ridimensiona in quel modo, con il peso massimo attivo.
- `--settings` (solo Debug) prova ad aprire le impostazioni; da dentro l'app si aprono con ⌘,.
- Le preferenze (`favoriteFolders`, `recentFolders`, `stickyMenu`, `triggerShortcut`,
  `didShowWelcome`) stanno in `defaults read it.fabiosbruun.Orbis`.
- `-stickyMenu YES` attiva la preferenza per una sola esecuzione.
- I messaggi si leggono con
  `log stream --info --predicate 'subsystem == "it.fabiosbruun.Orbis"'`. Quelli che possono
  contenere nomi di file sono privati: per vederli in chiaro serve un profilo di log che li abiliti.

Per creare il DMG da distribuire, vedi [RELEASING.md](RELEASING.md).
