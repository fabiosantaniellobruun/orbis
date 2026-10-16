# Orbis Clip — note di progetto

Seconda app del repository, accanto a Orbis. Tenendo premuto ⇧ e facendo clic destro, accanto al
puntatore compaiono gli elementi che si sono salvati (testi, link, immagini, file, password): se ne
sceglie uno e viene incollato dove si era fatto clic. Se si inizia a scrivere, compare una ricerca.

## Stato

Funzionano: pannello, ricerca, intercettazione del clic, incolla nei campi di testo (anche in
Chrome ed Electron), aggiunta dal menu Servizi o dagli appunti, salvataggio su disco con le copie
di file e immagini (fino a 10 MB), testo formattato, la finestra Elementi per gestirli. Mancano le
voci di "Da fare".

## Decisioni

- **App separata da Orbis, nello stesso repository.** Orbis non chiede permessi e non usa la rete;
  Orbis Clip ha bisogno di entrambe le cose. Il codice in comune (vetro, scorciatoie, fotografie
  di debug) sta in `Shared/`, una cartella che appartiene a tutti e due i target.
- **Niente cronologia degli appunti.** Gli elementi li aggiunge l'utente, uno per uno, con un nome,
  una scorciatoia facoltativa e se è un preferito. Quindi Orbis Clip non legge gli appunti in
  background.
- **Il pannello mostra gli ultimi 6 preferiti aggiunti e gli ultimi 4 usati** (senza ripetere quelli
  già tra i preferiti). Scrivendo, i risultati della ricerca li sostituiscono: la scorciatoia conta
  più del nome, il nome più del contenuto; maiuscole e accenti non contano.
- **⇧ + clic destro**, prima il tasto e poi il clic: il clic si intercetta con un event tap e non
  arriva all'app, che altrimenti aprirebbe il suo menu contestuale (si apre al mouse-down). Un
  monitor globale non basterebbe: vede il clic ma non lo ferma. La combinazione è configurabile,
  sia i tasti sia il tasto del mouse (`ClipTrigger`), nelle Impostazioni, con l'avvio al login.
  Registratore della combinazione e avvio al login sono gli stessi di Orbis, in `Shared/`.
- **Il pannello resta aperto**: si sceglie con un clic, o con le frecce e Invio; Esc o un clic fuori
  lo chiudono. Riceve la tastiera senza attivare l'app (`.nonactivatingPanel` che può diventare
  finestra chiave), così l'app in cui si è fatto clic resta in primo piano.
- **Le scorciatoie si usano solo nella ricerca** (scrivendo `lin` LinkedIn va al primo posto): niente
  combinazioni di tasti per singolo elemento, che andrebbero ricordate, né espansione del testo.
- **Dove si incolla** si capisce con le API di accessibilità, nel punto del clic:
  - in un campo di una riga si incolla il testo, il link, o il *nome* dell'immagine o del file;
  - in un'area di testo (anche web) l'elemento stesso, che l'app accetta se può;
  - altrove l'elemento resta negli appunti.
  Per incollare si manda un clic nello stesso punto (il campo prende il focus e il cursore va lì),
  poi ⌘V. L'elemento resta negli appunti. Chrome, gli altri browser basati su Chromium e le app
  Electron pubblicano i campi delle pagine solo se glielo si chiede (`AXEnhancedUserInterface`,
  `AXManualAccessibility`): lo si chiede all'apertura del pannello, e il campo si ricontrolla al
  momento di incollare, quando la pagina li ha pubblicati.
- **File: se ne conserva una copia** (fino a 10 MB), che resta valida se l'originale si sposta.
- **Il testo si incolla con la sua formattazione**, quando ce l'ha.
- **Nel Finder si crea un file**: un'immagine in PNG, un testo in .txt (o .rtf, se formattato), un
  link in .webloc, una copia del file salvato; mai sopra un file esistente ("nome 2"). Sulla
  scrivania la cartella è nota; per una finestra la si chiede al Finder con AppleScript (le API di
  accessibilità non la dicono), e la prima volta macOS chiede il permesso Automazione. Se la
  finestra non mostra una cartella (Recenti, AirDrop) l'elemento resta negli appunti.
- **Aggiungere elementi**: dal menu contestuale, con il servizio "Aggiungi a Orbis Clip" (testi
  selezionati, link, file nel Finder), oppure dal menu della barra con "Aggiungi dagli appunti…",
  che serve per le immagini copiate da un browser (il menu Servizi non le riceve).
- **La rete si usa per le anteprime dei link** (LinkPresentation): l'immagine che la pagina
  dichiara per la condivisione o, se non c'è, la sua icona, ridotta a 240 pixel. Si scarica dopo
  l'aggiunta e, per i link che non ce l'hanno (rete assente), a ogni avvio.
- **Le password stanno nel Portachiavi** di login (servizio `it.fabiosbruun.OrbisClip`, una voce
  per elemento), mai su disco in chiaro: `items.json` ne conserva solo il riferimento. Si aggiungono
  e si cambiano nella finestra Elementi, senza mai mostrarle. Prima di incollarne una si chiede
  Touch ID (o la password del Mac, dove Touch ID non c'è). Negli appunti vanno con
  `org.nspasteboard.ConcealedType`, perché i gestori di appunti non le conservino, e dopo un minuto
  si tolgono. Eliminando l'elemento si toglie anche la voce del Portachiavi.

## Permessi

- **Automazione (Finder)**: solo per creare un file in una finestra del Finder. Serve anche
  l'entitlement `com.apple.security.automation.apple-events`, per il runtime protetto.
- **Accessibilità**: per l'event tap e per mandare clic e ⌘V. All'avvio l'app lo chiede e riprova
  ogni due secondi finché non arriva.
- **La firma conta.** macOS lega il permesso alla firma dell'app; con la firma ad hoc cambia a ogni
  build, e dopo ogni aggiornamento (o ricompilazione) il permesso va tolto e ridato. Con un
  certificato, anche autofirmato, il requisito diventa "questo identificativo, firmato con questo
  certificato", e resta valido. `Config/OrbisClip.xcconfig` firma ad hoc; chi ha un certificato lo
  indica in `Config/OrbisClip.local.xcconfig`, escluso da git (sul Mac di sviluppo: "Orbis Clip
  Dev", autofirmato, nel portachiavi di login). Il certificato non serve che sia "fidato": firma
  lo stesso, e il requisito confronta solo l'impronta. Per la release servirà lo stesso
  certificato, o un Developer ID.

## Da fare

- Usare le password già salvate: quelle dell'app Password e del portachiavi iCloud non sono
  leggibili da altre app; quelle del portachiavi "login" sì, ma il sistema chiede conferma per
  ciascuna. Per ora le password si inseriscono in Orbis Clip.

## Come si prova

```bash
xcodebuild -project Orbis.xcodeproj -scheme OrbisClip -configuration Debug -derivedDataPath build/clip build
open "build/clip/Build/Products/Debug/Orbis Clip.app" --args --preview
```

- `--preview` apre il pannello al centro dello schermo (l'elemento scelto va negli appunti).
- `--add-preview` apre la finestra con cui si aggiunge un elemento.
- `--library` apre la finestra Elementi; `--samples` usa degli esempi al posto degli elementi
  veri, senza salvarli.
- `--snapshot <percorso.png>` fotografa le finestre visibili, senza chiedere il permesso.
- Il servizio compare nel menu contestuale quando l'app sta in `/Applications` o
  `~/Applications`; altrimenti `/System/Library/CoreServices/pbs -update` dopo averla aperta.
