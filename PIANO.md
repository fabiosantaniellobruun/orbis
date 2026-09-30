# Radial — piano

App da barra dei menu per macOS 26+. Mentre si trascinano dei file, tenendo premuto ⌃⇧ compare
attorno al puntatore un anello di bottoni in vetro: si rilasciano i file su un bottone per
eseguire l'azione.

## Decisioni

- **Selezione per settore angolare**: conta la direzione in cui ci si muove, non la mira sul bottone.
  Al centro c'è una zona morta; uscendo dall'anello il menu si chiude e il trascinamento prosegue.
- **Combinazione di soli modificatori** (⌃⇧ di default): non richiede permessi di sistema.
- **Niente sandbox, fuori dal Mac App Store**: rinomina e spostamento in sandbox sono molto limitati.
- **Pannello sempre scuro**: compare sopra qualsiasi sfondo e con il vetro chiaro le icone si perdono.
- Preferenza `stickyMenu` (UserDefaults): il menu resta aperto dopo aver rilasciato i tasti.

## Fasi

1. **Prototipo di verifica** — fatto. Vedi sotto.
2. **Menu radiale**: secondo anello per le azioni con opzioni, comportamento ai bordi dello schermo,
   azioni filtrate per tipo di file, test sulla geometria.
3. **Azioni semplici**: Clona, Sposta, Comprimi, Copia percorso, Cestina, con Annulla.
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

## Sviluppo

```bash
xcodebuild -project Radial.xcodeproj -scheme Radial -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Radial.app
```

- `--preview` all'avvio mostra il menu al centro dello schermo, pilotato dal mouse.
- `-stickyMenu YES` attiva la preferenza per una sola esecuzione.
- I messaggi si leggono con
  `log stream --info --predicate 'subsystem == "it.geckosoft.Radial"'`.
