# Radial — piano

App da barra dei menu per macOS 26+. Mentre si trascinano dei file, tenendo premuto Shift compare
attorno al puntatore un anello di bottoni in vetro: si rilasciano i file su un bottone per
eseguire l'azione.

## Decisioni

- **Selezione per settore angolare**: conta la direzione in cui ci si muove, non la mira sul bottone.
  Al centro c'è una zona morta; uscendo dall'anello il menu si chiude e il trascinamento prosegue.
- **Il menu si apre con Shift**, da solo. Lo stato dei modificatori viene letto
  (`NSEvent.modifierFlags`), non intercettato: non servono permessi. Con ⌘, ⌥ o ⌃ premuti il
  Finder cambia il trascinamento (sposta, copia, alias) e il menu non compare.
  Lo spazio è stato scartato: apre l'anteprima rapida del Finder, e a leggerlo con
  `CGEventSource.keyState` serve comunque un tasto vero, perché quelli simulati non risultano.
- **Niente sandbox, fuori dal Mac App Store**: rinomina e spostamento in sandbox sono molto limitati.
- **Tema chiaro o scuro secondo il sistema**. Nel tema chiaro un velo bianco sotto le icone tiene
  il vetro chiaro anche sugli sfondi scuri, dove altrimenti le icone scure si perderebbero.
- **Onda al rilascio**: dal bottone scelto parte una lente di vetro con il bordo iridescente
  (`HoloRipple`). Con "Riduci movimento" attivo non compare.
- Preferenza `stickyMenu` (UserDefaults): il menu resta aperto dopo aver rilasciato Shift.

## Fasi

1. **Prototipo di verifica** — fatto. Vedi sotto.
2. **Menu radiale**: secondo anello per le azioni con opzioni, comportamento ai bordi dello schermo,
   azioni filtrate per tipo di file, test sulla geometria.
3. **Azioni immediate** — fatto: Clona, Comprimi, Copia percorso, Cestina. Dopo l'azione un avviso
   dice com'è andata e, dove ha senso, offre Annulla per cinque secondi. Resta Sposta, che ha
   bisogno del secondo anello. Le azioni non ancora pronte rispondono "in arrivo" e non toccano nulla.
4. **Rinomina in serie**: schema (testo + contatore, trova/sostituisci, data) con anteprima live.
5. **Converti in** e **Ridimensiona**: immagini (PNG, JPEG, HEIC, WebP, AVIF), poi video e audio.
   Ridimensiona copre compressione, dimensioni e proporzioni.
6. **Impostazioni**: combinazione di tasti, ordine delle azioni, cartelle preferite, avvio al login.
7. **Rifinitura e distribuzione**: icona, gestione errori, firma e notarizzazione.

## Cosa ha dimostrato il prototipo

- Il trascinamento di file si riconosce senza permessi: monitor globale del mouse più il contatore
  della pasteboard di trascinamento. I modificatori si leggono con `NSEvent.modifierFlags`.
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
- Annullare una copia o un archivio li mette nel Cestino, non li cancella. Annullare Cestina
  rimette i file dov'erano, senza sovrascrivere ciò che nel frattempo ha preso quel nome.
- L'avviso vive in un pannello suo (`ToastController`), piccolo, che sopravvive al menu.

## Sviluppo

```bash
xcodebuild -project Radial.xcodeproj -scheme Radial -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Radial.app
```

```bash
xcodebuild test -project Radial.xcodeproj -scheme Radial -derivedDataPath build -destination 'platform=macOS'
```

I test lavorano in cartelle temporanee. Quelli sul Cestino cestinano e ripristinano file di prova.

- `--preview` all'avvio mostra il menu al centro dello schermo, pilotato dal mouse.
- `--run <azione> <percorsi…>` (solo Debug, da mettere per ultimo) esegue un'azione senza passare
  dal menu: `clone`, `compress`, `copyPath`, `trash`.
- `-stickyMenu YES` attiva la preferenza per una sola esecuzione.
- I messaggi si leggono con
  `log stream --info --predicate 'subsystem == "it.fabiosbruun.Radial"'`.
