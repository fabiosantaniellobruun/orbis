# Come si rilascia Orbis

Orbis si distribuisce fuori dal Mac App Store: un DMG su GitHub Releases, scaricabile anche dalla
landing. **Per ora non è notarizzato**: notarizzare richiede l'Apple Developer Program (99 $ l'anno),
anche per le app che non passano dallo Store. Il DMG è firmato "ad hoc" (senza, su Apple silicon
l'app non partirebbe nemmeno), e chi lo scarica autorizza Orbis una volta, come spiega il README.

Lo script [`scripts/release.sh`](../scripts/release.sh) fa tutto: compila in Release (universale,
Apple silicon e Intel), firma, controlla e crea il DMG. Se un giorno ci saranno le credenziali Apple,
lo stesso script firma con il Developer ID e notarizza (vedi in fondo).

## Ogni rilascio

1. **Aggiorna la versione** in Xcode (target Orbis → General → Version), oppure in
   `Orbis.xcodeproj/project.pbxproj` (`MARKETING_VERSION`, nelle due configurazioni del target).
   Usa tre numeri: `0.2.0`, `1.0.0`.
2. **Fai le [prove a mano](PROVE.md)** con la versione Release installata in Applicazioni: i
   trascinamenti veri, i pannelli, i tasti. I test automatici non li vedono.
3. **Controlla che i test passino** (in italiano: controllano i messaggi):
   ```bash
   xcodebuild test -project Orbis.xcodeproj -scheme Orbis -derivedDataPath build -destination 'platform=macOS' -testLanguage it
   ```
4. **Crea il DMG**:
   ```bash
   scripts/release.sh
   ```
   Alla fine in `dist/`:
   - `Orbis-<versione>.dmg`: il file da pubblicare;
   - `Orbis.dmg`: lo stesso, con il nome fisso (serve al link "ultima versione", vedi sotto);
   - `Orbis-<versione>.dmg.sha256`: il checksum, da pubblicare accanto al DMG.

   Lo script avvisa che il DMG non è notarizzato: è previsto.
5. **Provalo come lo proverà chi lo scarica**: caricalo (o scaricalo) da Internet, perché solo i file
   scaricati hanno il segno di quarantena che fa scattare il blocco. Apri il DMG, trascina Orbis in
   Applicazioni, avvialo, e segui i passaggi del README ("The first launch"). Dopo l'autorizzazione
   deve aprirsi la finestra di benvenuto.
6. **Pubblica**:
   ```bash
   git tag v0.2.0 && git push origin v0.2.0
   gh release create v0.2.0 dist/Orbis-0.2.0.dmg dist/Orbis.dmg dist/Orbis-0.2.0.dmg.sha256 \
     --title "Orbis 0.2.0" --notes "Cosa è cambiato…"
   ```
   Nelle note conviene ripetere in due righe come si autorizza l'app al primo avvio.

## Orbis Clip

Si rilascia con lo stesso script:

```bash
scripts/release.sh OrbisClip
```

In `dist/` arrivano `OrbisClip-<versione>.dmg`, `OrbisClip.dmg` e il checksum, accanto a quelli di
Orbis (lo script toglie solo i file dell'app che sta rilasciando).

- **La firma.** Senza `DEVELOPER_ID`, Orbis Clip si firma con il certificato autofirmato
  "Orbis Clip Dev" del portachiavi di login (`SIGN_IDENTITY` per usarne un altro). Il permesso
  Accessibilità è legato alla firma: con lo stesso certificato resta valido da una versione
  all'altra; con un altro certificato, o con la firma ad hoc, chi aggiorna deve toglierlo e ridarlo.
  **Conserva una copia del certificato con la sua chiave** (Accesso Portachiavi → esporta come
  .p12): perderlo vuol dire ridare il permesso a tutti al rilascio successivo.
- **Il tag e "latest".** Le due app stanno nello stesso repository, e il link "ultima versione"
  (`releases/latest/download/Orbis.dmg`) segue l'ultimo rilascio marcato *latest*. I rilasci di
  Orbis Clip hanno un tag loro e non sono mai *latest*, così quel link resta di Orbis:
  ```bash
  git tag clip-v0.1.0 && git push origin clip-v0.1.0
  gh release create clip-v0.1.0 dist/OrbisClip-0.1.0.dmg dist/OrbisClip.dmg dist/OrbisClip-0.1.0.dmg.sha256 \
    --title "Orbis Clip 0.1.0" --latest=false --notes "…"
  ```
  Il link a Orbis Clip contiene quindi la versione:
  `https://github.com/fabiosantaniellobruun/orbis/releases/download/clip-v0.1.0/OrbisClip.dmg`.

## Il link per il sito o per la landing

Se ogni rilascio include anche `Orbis.dmg` (stesso nome, ogni volta), questo indirizzo punta sempre
all'ultima versione, senza doverlo aggiornare:

```
https://github.com/fabiosantaniellobruun/orbis/releases/latest/download/Orbis.dmg
```

Sulla landing servono:

- il pulsante di download con quel link e i requisiti (macOS 26 o successivo);
- due righe su cosa fa, e magari il GIF dell'anello;
- **come si apre la prima volta**, ben visibile accanto al pulsante: "macOS blocca le app non
  notarizzate: apri Orbis, premi Fine, poi Impostazioni di Sistema → Privacy e sicurezza → Apri
  comunque". Senza, molti penseranno che l'app sia rotta o pericolosa;
- il link al codice su GitHub: per chi non si fida di un'app non notarizzata, poterla leggere e
  compilare è la garanzia che conta.

Se vuoi mostrare la versione, si legge da
`https://api.github.com/repos/fabiosantaniellobruun/orbis/releases/latest` (campo `tag_name`).

## Cosa vede chi scarica il DMG

Al primo avvio macOS dice che Orbis non è stata aperta perché Apple non ha potuto verificare che
sia priva di malware, con i pulsanti *Fine* e *Sposta nel Cestino*. Da macOS 15 non c'è più il
trucco del clic destro → Apri: si passa da **Impostazioni di Sistema → Privacy e sicurezza → Apri
comunque**, con la password. Una volta sola; gli aggiornamenti scaricati di nuovo chiedono di nuovo.

In alternativa, dal Terminale: `xattr -dr com.apple.quarantine /Applications/Orbis.app`.

## Se un giorno si notarizza

Con l'Apple Developer Program l'avviso sparisce: l'app si apre con un doppio clic.

1. **Iscriviti** su [developer.apple.com/programs](https://developer.apple.com/programs/).
2. **Crea un certificato "Developer ID Application"**. In Xcode: Impostazioni → Accounts → il tuo
   team → Manage Certificates → + → *Developer ID Application*. Si controlla con:
   ```bash
   security find-identity -v -p codesigning
   ```
   Cerca una riga come `Developer ID Application: Nome Cognome (ABCDE12345)`: è il valore di
   `DEVELOPER_ID`.
3. **Salva le credenziali per la notarizzazione** nel portachiavi, con un nome a scelta. Serve una
   [password specifica per l'app](https://support.apple.com/102654), non quella dell'Apple ID:
   ```bash
   xcrun notarytool store-credentials "orbis-notary" \
     --apple-id "tua@email" --team-id "ABCDE12345" --password "xxxx-xxxx-xxxx-xxxx"
   ```
   Il nome (`orbis-notary`) è il valore di `NOTARY_PROFILE`.
4. **Crea il DMG** con le due variabili:
   ```bash
   DEVELOPER_ID="Developer ID Application: Nome Cognome (ABCDE12345)" \
   NOTARY_PROFILE="orbis-notary" \
   scripts/release.sh
   ```
   Ci vogliono qualche minuto, quasi tutti per l'attesa della notarizzazione. Poi si tolgono dal
   README e dalla landing le istruzioni per il primo avvio.

## Idee per dopo

- **Aggiornamenti automatici con [Sparkle](https://sparkle-project.org/)**: l'app controlla un
  file `appcast.xml` (si può ospitare su GitHub Pages) e propone l'aggiornamento. Funziona anche
  senza notarizzazione, ma ogni aggiornamento firmato ad hoc potrebbe richiedere di nuovo
  l'autorizzazione: va provato.
- **Homebrew Cask**: il repository ufficiale chiede app notarizzate. Un *tap* personale
  (`brew install --cask fabiosantaniellobruun/tap/orbis`) si può fare anche senza, ma il blocco al
  primo avvio resta.
- **Un rilascio automatico su GitHub Actions**: richiede un runner con macOS 26.
