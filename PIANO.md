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
- **Icona** in formato Icon Composer (`Radial/AppIcon.icon`), ricavata da `Radial icon.png` (2048 px,
  a pieno campo): macOS la ritaglia nel quadrato arrotondato e le dà i riflessi di vetro. Il livello
  è opaco: con la traslucenza attiva i colori si slavano sul fondo. Per cambiarla basta sostituire
  `Assets/RadialIcon.png` (1024 px), oppure aprire la cartella con Icon Composer.
- **I pannelli con cui si interagisce si spostano** (`movableWindow()` in `RadialGlass.swift`),
  trascinandoli da un punto libero. L'anello e l'avviso seguono il puntatore e non si spostano.
  `isMovableByWindowBackground` non basta: il contenuto SwiftUI se ne prende gli eventi.
- **Secondo anello** per le azioni con opzioni: passando su un bottone che ne ha, si apre un arco di
  voci oltre l'anello, e si rilascia su una di quelle. Il bottone da solo non è un bersaglio. Le
  voci stanno sul lato del loro bottone, con l'etichetta sul lato esterno. Di base Sposta sta a
  sinistra, Converti in a destra, Cestina in basso, lontana da tutte e due.
  Vicino a un bordo dello schermo non c'è posto per le etichette (servono circa 455 punti di lato):
  invece di capovolgere l'arco, che diventerebbe irraggiungibile perché bisognerebbe attraversare
  il centro (e lì il sottomenu si chiude), sono le due voci ad andare dalla parte che ha posto
  (`RadialAction.layout`). Rinomina sta sempre in alto. In verticale il pannello si sposta di
  quanto serve perché stia l'arco. Il prezzo è che la posizione di Sposta cambia con il punto
  in cui si trascina: se dà fastidio, si può passare a un solo lato.
- **Sposta**: prima le due cartelle usate più di recente, poi le quattro preferite scelte
  dall'utente (Impostazioni…), poi "Scegli cartella…". Ogni voce mostra il nome e, in piccolo, il
  percorso completo con la casa abbreviata (`~/Sites/Clienti/Rossi`), perché spesso più cartelle
  hanno lo stesso nome. Una cartella già preferita non occupa anche un posto tra le recenti; quelle
  che non esistono più saltano. Se il nome esiste già nella destinazione il file arriva come
  "nome 2", come "Mantieni entrambi" del Finder; non si sovrascrive mai.
- **Onda al rilascio**: dal bottone scelto parte una lente di vetro con il bordo iridescente
  (`HoloRipple`). Con "Riduci movimento" attivo non compare.
- Preferenza `stickyMenu` (UserDefaults): il menu resta aperto dopo aver rilasciato Shift.

## Fasi

1. **Prototipo di verifica** — fatto. Vedi sotto.
2. **Menu radiale** — fatto il secondo anello (usato da Sposta; Converti in lo userà per i formati)
   e il comportamento ai bordi dello schermo. Manca: azioni filtrate per tipo di file.
3. **Azioni immediate** — fatto: Clona, Comprimi, Copia percorso, Cestina. Dopo l'azione un avviso
   dice com'è andata e, dove ha senso, offre Annulla per cinque secondi. Resta Sposta, che ha
   bisogno del secondo anello. Le azioni non ancora pronte rispondono "in arrivo" e non toccano nulla.
4. **Rinomina in serie** — fatto. Pannello in vetro con quattro modi (Nome e numero, Sostituisci,
   Aggiungi, Data) e anteprima in tempo reale. Vedi "Rinomina" sotto.
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

## Rinomina

- La logica dei nomi (`RenamePlan`) non tocca il disco e si ricalcola a ogni tasto. Segnala nome
  vuoto, caratteri non validi (`/` e `:`), nome troppo lungo, due elementi con lo stesso nome e
  nome già occupato da un elemento estraneo. Basta un problema per spegnere il pulsante.
- L'estensione non viene mai toccata. Nelle cartelle il punto fa parte del nome.
- L'ordine di numerazione è "Come nel Finder", per nome (naturale: 2 prima di 10), per data di
  creazione o di modifica.
- `FileOperations.rename` non sovrascrive mai. Quando un nome nuovo è il vecchio nome di un altro
  elemento del gruppo (scambi, scorrimento di numeri, sole maiuscole) mette prima da parte gli
  elementi coinvolti con un nome provvisorio (`.radial-…`) e poi li porta al nome finale.
- Annulla rimette i nomi di prima, con la stessa procedura.
- Il pannello (`FormPanel`) può ricevere la tastiera. Radial si attiva mentre è aperto e restituisce
  il focus all'app di prima quando si chiude.

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
  dal menu: `clone`, `compress`, `copyPath`, `trash`, `rename` (apre il pannello). Per `move` il
  primo percorso è la cartella di destinazione, gli altri sono i file.
- `--settings` (solo Debug) prova ad aprire le impostazioni; da dentro l'app si aprono con ⌘,.
- Le preferenze (`favoriteFolders`, `recentFolders`, `stickyMenu`) stanno in
  `defaults read it.fabiosbruun.Radial`.
- `-stickyMenu YES` attiva la preferenza per una sola esecuzione.
- I messaggi si leggono con
  `log stream --info --predicate 'subsystem == "it.fabiosbruun.Radial"'`.
