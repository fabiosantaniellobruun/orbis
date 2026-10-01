# Prove a mano

Ciò che i test automatici non vedono: trascinamenti veri dal Finder, tasti veri, il vetro dei
pannelli, i tempi. Va rifatta prima di ogni rilascio, con la versione che si distribuisce (quella
del DMG, in Applicazioni), non con quella di sviluppo.

**Materiale:** la cartella `Prove Radial` sulla Scrivania.

| Cartella | Cosa c'è |
|---|---|
| `Foto` | `Azzorre.jpg` e `Islanda.jpg` (verticali, 1200×1600), `Eolie.jpg` (orizzontale, 1600×1276), `Nepal.heic`, `Trasparente.png` (cerchio rosso su fondo trasparente, 400×300) |
| `Video` | `Acqua.mp4` e `Split.mp4` (22 s, verticali) |
| `SVG` | `Logo.svg` (100×60), `Icona.svg` (solo viewBox, 64×64) |
| `Documenti` | `Documento.pdf`, `uno.txt`, `due.txt`, `tre.txt` |
| `Destinazioni` | `Clienti/Rossi`, `Clienti/Bianchi`, `Archivio` |

**Come segnalare:** il numero del passo (per esempio "3d") e cosa è successo invece di quello
atteso. Uno screenshot aiuta, soprattutto per il vetro e le misure.

In tutto il documento "trascina con ⇧" vuol dire: inizia a trascinare i file nel Finder, tieni
premuto il mouse, premi e tieni ⇧ (o il tasto scelto nelle impostazioni).

---

## 1. Anello

- [ ] **1a** Trascina `Eolie.jpg` con ⇧: attorno al puntatore compare l'anello con otto bottoni.
      Rinomina in alto, Converti in a destra, Cestina in basso, Sposta a sinistra.
- [ ] **1b** Muoviti verso un bottone senza arrivarci: si illumina quello nella direzione, non
      serve centrarlo. Al centro non si illumina nulla.
- [ ] **1c** Rilascia ⇧ senza rilasciare il file: l'anello si chiude e il trascinamento prosegue
      (puoi rilasciare il file dove vuoi, come sempre).
- [ ] **1d** Riapri l'anello e allontanati molto: si chiude, il trascinamento prosegue.
- [ ] **1e** Trascina vicino al bordo sinistro dello schermo e poi vicino a quello destro: Sposta e
      Converti in passano dalla parte dove c'è posto per le etichette, e restano raggiungibili.
- [ ] **1f** Rilascia su Clona: onda di vetro dal bottone, avviso "1 elemento clonato" con
      Annulla. Premi Annulla: la copia va nel Cestino.

## 2. Converti in: le voci giuste per ogni file

- [ ] **2a** Trascina `Eolie.jpg` con ⇧ e passa su Converti in: il secondo anello ha PNG, JPEG,
      HEIC, AVIF, TIFF. Niente GIF, niente 1x–4x.
- [ ] **2b** Trascina `Acqua.mp4`: c'è solo GIF.
- [ ] **2c** Trascina `Logo.svg`: ci sono PNG 1x, 2x, 3x, 4x e 1x–4x, e nient'altro.
- [ ] **2d** Rilascia `Logo.svg` su **1x–4x**: accanto all'SVG compaiono `Logo.png`,
      `Logo@2x.png`, `Logo@3x.png`, `Logo@4x.png`. L'avviso dice "4 PNG creati (1x–4x)".
- [ ] **2e** Seleziona `Logo@4x.png` e premi ⌘I nel Finder: in "Altre informazioni" le dimensioni
      sono 400×240. Aperto in Anteprima ha i bordi netti e gli angoli trasparenti. `Logo.png` è
      100×60.
- [ ] **2f** Annulla dall'avviso: i quattro PNG vanno nel Cestino.
- [ ] **2g** Trascina `Icona.svg` su PNG 2x: `Icona@2x.png` di 128×128.
- [ ] **2h** Trascina insieme `Logo.svg` e `Eolie.jpg`: compaiono sia le scale PNG sia i formati.
- [ ] **2i** Trascina `Trasparente.png` su JPEG: `Trasparente.jpg` ha il fondo **bianco**, non nero.
- [ ] **2j** Trascina `Nepal.heic` su JPEG: `Nepal.jpg`, dritto e di 1139×1600.

## 3. Ridimensiona

- [ ] **3a** Trascina `Azzorre.jpg`, `Islanda.jpg` ed `Eolie.jpg` con ⇧ e rilascia su Ridimensiona:
      si apre il pannello vicino all'anello. Il vetro si legge, con il tema chiaro e con quello
      scuro (prova a cambiarlo con il pannello aperto).
- [ ] **3b** Scrivi `800` in Larghezza: l'anteprima si aggiorna a ogni cifra. Le verticali diventano
      800×1067, l'orizzontale 800×638. Dopo un attimo compare il peso stimato (≈).
- [ ] **3c** Scrivi anche `800` in Altezza: ora è una scatola, le verticali diventano 600×800.
- [ ] **3d** Percentuale: lo slider e i bottoni 25% / 50%… cambiano le misure.
- [ ] **3e** Proporzioni → 1:1 con "Segui l'orientamento": tutte quadrate. Prova 16:9: le verticali
      diventano 9:16.
- [ ] **3f** Formato JPEG, qualità al 50%: il peso stimato scende. "Limita il peso a" 100 KB.
- [ ] **3g** Premi Ridimensiona (o Invio): accanto agli originali compaiono i file
      "… ridimensionata.jpg" con le misure dell'anteprima. Annulla li toglie.
- [ ] **3h** Il pannello si sposta trascinandolo da un punto vuoto; Esc lo chiude.
- [ ] **3i** Trascina `Documento.pdf` su Ridimensiona: avviso "Il file non è un'immagine da
      ridimensionare", nessun pannello.

## 4. Video in GIF

- [ ] **4a** Trascina `Acqua.mp4` con ⇧ → Converti in → GIF: si apre il pannello. Entro pochi
      secondi l'anteprima si anima, e sotto compaiono le miniature del video.
- [ ] **4b** Trascina i bordi colorati dell'intervallo, e poi l'intervallo intero: i tempi sotto si
      aggiornano, l'anteprima si rifà.
- [ ] **4c** Cambia fotogrammi, colori, retino: l'anteprima cambia aspetto, il peso stimato cambia.
- [ ] **4d** Crea GIF: l'avviso mostra la percentuale, poi "Acqua.gif creato, … MB". **Annota
      quanti secondi ci mette** per 10 secondi a 480 px, 15 fotogrammi al secondo.
- [ ] **4e** Apri `Acqua.gif` con la barra spaziatrice: gira, i colori sono quelli dell'anteprima.
- [ ] **4f** Rifai con "Peso massimo" a 1 MB: il GIF sta sotto, o l'avviso dice che è rimasto sopra.
- [ ] **4g** Trascina insieme `Acqua.mp4` e `Split.mp4`: niente barra dell'intervallo, "Ogni video
      diventa un GIF, per intero". Crea GIF: due file.

## 5. Rinomina e Sposta

- [ ] **5a** Trascina `uno.txt`, `due.txt`, `tre.txt` su Rinomina: nome `nota`, numero progressivo.
      L'anteprima mostra `nota 1.txt`… Rinomina, poi Annulla: tornano i nomi di prima.
- [ ] **5b** Impostazioni (⌘, dal menu di Radial) → Sposta: trascina la cartella `Clienti/Rossi`
      su una riga delle preferite. Compare con il percorso completo.
- [ ] **5c** Trascina un file su Sposta: nel secondo anello c'è Rossi, con il percorso sotto.
      Rilascia: il file si sposta, e Annulla lo riporta indietro. Rossi non compare anche tra le
      recenti: una preferita non occupa un posto lì.
- [ ] **5d** Sposta un file in `Archivio` con "Scegli cartella…": la volta dopo Archivio è tra le
      recenti, in cima.

## 6. Il tasto

- [ ] **6a** Impostazioni → Generale → clicca il campo del tasto e premi **⌥**, poi rilascia: il
      campo mostra ⌥. Trascina con ⌥: l'anello si apre (il Finder mostra il + della copia, è
      normale).
- [ ] **6b** Registra **⌃⌥**: funziona solo con tutti e due premuti, non con uno solo.
- [ ] **6c** Registra **⌘**: compare l'avviso. Trascinando con ⌘ l'anello si apre, ma il rilascio
      su un'azione viene rifiutato (il Finder ammette solo lo spostamento): è voluto.
- [ ] **6d** Registra un tasto normale, per esempio **R**: compare l'avviso. Trascinando e tenendo
      R l'anello si apre.
- [ ] **6e** Nel campo premi ⌫: torna ⇧. Esc durante la registrazione annulla.
- [ ] **6f** "Tieni il menu aperto": dopo aver rilasciato il tasto l'anello resta aperto finché
      non rilasci il file o esci dall'anello.

## 7. Il resto

- [ ] **7a** "Apri Radial all'avvio del Mac": acceso, Radial compare in Impostazioni di Sistema →
      Generale → Elementi login. Spento, sparisce.
- [ ] **7b** Menu di Radial nella barra: "Mostra menu di prova" apre l'anello al centro dello
      schermo; "Come si usa…" apre la finestra di benvenuto.
- [ ] **7c** Impostazioni di Sistema → Accessibilità → Movimento → Riduci movimento: l'onda al
      rilascio non c'è più, il resto funziona.
- [ ] **7d** Nessuna finestra di permessi è comparsa in tutte le prove.
