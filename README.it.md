# Radial

**Trascina dei file, tieni premuto un tasto, rilasciali su un anello di azioni.**

Radial è una piccola app per la barra dei menu di macOS. Inizia a trascinare dei file nel Finder,
tieni premuto **⇧** (o il tasto che preferisci) e attorno al puntatore compare un anello di
bottoni in vetro. Rilascia i file su un bottone: rinominali in serie, clonali, spostali in una
cartella recente, converti o ridimensiona le immagini, trasforma i video in GIF, comprimili, copia i loro percorsi o mandali nel Cestino.
Ogni azione si può annullare.

<p align="center">
  <img src="docs/images/second-ring.jpg" alt="L'anello di Radial attorno al puntatore mentre si trascinano tre file, con il secondo anello di Sposta aperto: due cartelle recenti, quattro preferite e la scelta di una cartella, ognuna con il suo percorso completo" width="760">
</p>

> **Stato:** beta (0.1). L'interfaccia è in **italiano**; una versione in inglese è in programma.
> [English README](README.md).

## Cosa fa

- **Rinomina in serie** con anteprima in tempo reale: nome e numero, sostituisci, aggiungi testo,
  inserisci una data. I problemi (nomi vuoti, duplicati, nomi già occupati) si vedono prima di
  toccare qualsiasi cosa. Scambi e scorrimenti come `1→2, 2→3` sono gestiti senza rischi.
- **Sposta** nelle ultime due cartelle usate, nelle tue quattro preferite o in una qualsiasi. Ogni
  voce mostra il nome della cartella e, in piccolo, il **percorso completo**: cartelle con lo stesso
  nome non si confondono.
- **Converti le immagini** in PNG, JPEG, HEIC, AVIF o TIFF, conservando metadati e orientamento.
- **Ridimensiona le immagini**: falle stare in una larghezza e un'altezza (anche un gruppo di foto
  orizzontali e verticali insieme), scalale in percentuale o ritagliale a 1:1, 4:3, 16:9 o a un
  rapporto a scelta. Scegli formato e qualità, oppure un peso massimo, con l'anteprima delle misure
  e del peso stimato.
- **Video in GIF** con l'anteprima animata: scegli l'intervallo su una striscia di fotogrammi, la
  velocità, la misura e le proporzioni, i fotogrammi al secondo, i colori, il retino, le ripetizioni
  e un peso massimo. Radial ha un suo encoder GIF (niente ffmpeg): una palette per tutta la clip,
  un retino morbido, e da un fotogramma all'altro si salvano solo i pixel che cambiano.
- **Clona**, **comprimi** (zip), **copia il percorso** e **cestina** ("Ripristina" del Finder funziona).
- **Annulla** per qualche secondo dopo ogni azione che modifica dei file. Radial non sovrascrive
  mai un file: se il nome è occupato, quello nuovo arriva come `nome 2`.
- **Il tuo tasto**: ⇧ di base; nelle impostazioni scegli qualsiasi combinazione di modificatori o tasto.
- Pensata per il **Liquid Glass** di macOS 26, segue il tema chiaro e scuro e rispetta "Riduci movimento".

<p align="center">
  <img src="docs/images/rename.jpg" alt="Il pannello di rinomina in serie con l'anteprima in tempo reale" width="330">
  &nbsp;&nbsp;
  <img src="docs/images/rename-conflicts.jpg" alt="L'anteprima segnala due elementi che prenderebbero lo stesso nome" width="330">
</p>

## Requisiti

- macOS 26 (Tahoe) o successivo
- Apple silicon o Intel (binario universale)

## Installazione

1. Scarica `Radial.dmg` dall'[ultima versione](https://github.com/fabiosantaniellobruun/radial/releases/latest).
2. Aprilo e trascina **Radial** in **Applicazioni**.
3. Avvia Radial. Vive nella barra dei menu (non c'è l'icona nel Dock) e una breve finestra di benvenuto spiega come si usa.

Se macOS dice che non può verificare l'app (le versioni non ancora notarizzate), apri
**Impostazioni di Sistema → Privacy e sicurezza**, scorri in fondo e premi **Apri comunque**; oppure
esegui una volta `xattr -dr com.apple.quarantine /Applications/Radial.app`.

Per disinstallare, esci da Radial dalla barra dei menu e trascinalo nel Cestino. Le preferenze si
tolgono con `defaults delete it.fabiosbruun.Radial`.

## Come si usa

1. **Trascina** uno o più file nel Finder (o dalla Scrivania). Tieni premuto il mouse.
2. **Tieni premuto ⇧** (o il tuo tasto). Attorno al puntatore compare l'anello.
3. **Muoviti verso un'azione** e rilascia i file. Basta andare nella sua direzione: il bottone
   sotto il puntatore si illumina.

Alcuni bottoni aprono un **secondo anello**: su **Sposta** trovi le cartelle recenti e preferite, su
**Converti in** i formati (e **GIF**, se trascini un video). **Rinomina**, **Ridimensiona** e **GIF** aprono un pannello con l'anteprima, che
puoi spostare trascinandolo da un punto libero.

Per **annullare**, rilascia il tasto o allontanati dall'anello: il trascinamento prosegue come al solito.

### Impostazioni

Si aprono dall'icona nella barra dei menu (**⌘,**).

- **Tasto per aprire il menu**: clicca il campo e premi la combinazione che vuoi. Le combinazioni di
  soli modificatori (⇧, ⌥⇧, ⌃⌥…) sono la scelta più sicura: un tasto normale (per esempio Spazio)
  arriva anche all'app da cui stai trascinando. ⌫ ripristina ⇧, Esc annulla.
- **Tieni il menu aperto** dopo aver rilasciato il tasto.
- **Apri all'avvio del Mac.**
- **Cartelle preferite** per *Sposta*: fino a quattro, scelte con un pulsante o trascinando una cartella su una riga.

## Privacy

Radial non chiede **nessun permesso**, non usa la **rete** e non invia **nessun dato**. Si accorge che
è in corso un trascinamento osservando gli eventi del mouse e la pasteboard di trascinamento. Guarda i
file trascinati quando si apre l'anello (solo il tipo, per proporre il GIF per i video) e quando li
rilasci su un'azione. I messaggi nel registro di sistema
che potrebbero contenere nomi di file sono privati.

## Compilare dal codice

Serve Xcode 27 o successivo (SDK di macOS 26).

```bash
git clone https://github.com/fabiosantaniellobruun/radial.git
cd radial
xcodebuild -project Radial.xcodeproj -scheme Radial -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Radial.app
```

I test (lavorano in cartelle temporanee):

```bash
xcodebuild test -project Radial.xcodeproj -scheme Radial -derivedDataPath build -destination 'platform=macOS'
```

Per creare un DMG da distribuire, vedi [docs/RELEASING.md](docs/RELEASING.md).

### Com'è fatto il progetto

| Cartella | Cosa c'è |
|---|---|
| `Radial/Actions` | Le operazioni sui file (sposta, rinomina, converti, cestina…) e come si annullano |
| `Radial/Input` | Il riconoscimento del trascinamento e il tasto configurabile |
| `Radial/Menu` | La geometria dell'anello, i bottoni, le voci del secondo anello |
| `Radial/Overlay` | I pannelli trasparenti e il controller |
| `Radial/Rename`, `Resize`, `GIF` | I pannelli di rinomina in serie, ridimensionamento e video in GIF, con la loro logica e l'encoder GIF |
| `Radial/Settings`, `Toast`, `Welcome` | Le impostazioni, l'avviso con Annulla, la finestra del primo avvio |
| `RadialTests` | Le suite di [Swift Testing](https://developer.apple.com/xcode/swift-testing/) |
| `docs` | Le [note di progetto](docs/PROGETTO.md) e la [guida al rilascio](docs/RELEASING.md) |

## Contribuire

Segnalazioni e pull request sono benvenute. Fai passare i test e aggiungine per i comportamenti
nuovi: le operazioni sui file, in particolare, non devono mai sovrascrivere né perdere nulla.

## Licenza

[MIT](LICENSE) © 2026 Fabio Santaniello Bruun
