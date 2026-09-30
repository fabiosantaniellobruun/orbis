# Come si rilascia Radial

Radial si distribuisce fuori dal Mac App Store: un DMG scaricabile dal sito o da GitHub Releases.
Perché gli utenti possano aprirlo con un doppio clic, senza avvisi di Gatekeeper, l'app deve essere
**firmata con un certificato Developer ID** e **notarizzata** da Apple. Senza, il DMG funziona ma
su un altro Mac macOS lo blocca finché l'utente non lo autorizza a mano (vedi in fondo).

Lo script [`scripts/release.sh`](../scripts/release.sh) fa tutto: compila in Release, firma, crea il
DMG, lo notarizza e lo rilega alla ricevuta di Apple. Senza credenziali produce comunque un DMG
firmato "ad hoc", utile per provare.

## Cosa serve, una volta sola

1. **Apple Developer Program** (99 $ l'anno): [developer.apple.com/programs](https://developer.apple.com/programs/).
   Senza, non si può né firmare con Developer ID né notarizzare.
2. **Un certificato "Developer ID Application"**. In Xcode: Impostazioni → Accounts → il tuo team →
   Manage Certificates → + → *Developer ID Application*. Si controlla con:
   ```bash
   security find-identity -v -p codesigning
   ```
   Cerca una riga come `Developer ID Application: Nome Cognome (ABCDE12345)`: è il valore di
   `DEVELOPER_ID`.
3. **Le credenziali per la notarizzazione**, salvate nel portachiavi con un nome a scelta. Serve una
   [password specifica per l'app](https://support.apple.com/102654) (non quella dell'Apple ID):
   ```bash
   xcrun notarytool store-credentials "radial-notary" \
     --apple-id "tua@email" --team-id "ABCDE12345" --password "xxxx-xxxx-xxxx-xxxx"
   ```
   Il nome (`radial-notary`) è il valore di `NOTARY_PROFILE`.

## Ogni rilascio

1. **Aggiorna la versione** in Xcode (target Radial → General → Version), oppure in
   `Radial.xcodeproj/project.pbxproj` (`MARKETING_VERSION`, nelle due configurazioni del target).
   Usa tre numeri: `0.2.0`, `1.0.0`.
2. **Controlla che i test passino**:
   ```bash
   xcodebuild test -project Radial.xcodeproj -scheme Radial -derivedDataPath build -destination 'platform=macOS'
   ```
3. **Crea il DMG**:
   ```bash
   DEVELOPER_ID="Developer ID Application: Nome Cognome (ABCDE12345)" \
   NOTARY_PROFILE="radial-notary" \
   scripts/release.sh
   ```
   Ci vogliono qualche minuto, quasi tutti per l'attesa della notarizzazione. Alla fine in `dist/`:
   - `Radial-<versione>.dmg`: il file da pubblicare;
   - `Radial.dmg`: lo stesso, con il nome fisso (serve al link "ultima versione", vedi sotto);
   - `Radial-<versione>.dmg.sha256`: il checksum, da pubblicare accanto al DMG.
4. **Provalo su un Mac pulito** (o almeno in un altro account utente): scarica il DMG da Internet,
   aprilo, trascina Radial in Applicazioni, avvialo. Non deve comparire nessun avviso, e al primo
   avvio deve aprirsi la finestra di benvenuto.
5. **Pubblica**:
   ```bash
   git tag v0.2.0 && git push origin v0.2.0
   gh release create v0.2.0 dist/Radial-0.2.0.dmg dist/Radial.dmg dist/Radial-0.2.0.dmg.sha256 \
     --title "Radial 0.2.0" --notes "Cosa è cambiato…"
   ```

## Il link per il sito o per la landing

Se ogni rilascio include anche `Radial.dmg` (stesso nome, ogni volta), questo indirizzo punta sempre
all'ultima versione, senza doverlo aggiornare:

```
https://github.com/fabiosantaniellobruun/radial/releases/latest/download/Radial.dmg
```

Sulla landing bastano: il pulsante di download con quel link, i requisiti (macOS 26 o successivo) e
due righe su cosa fa. Se vuoi mostrare la versione, si legge da
`https://api.github.com/repos/fabiosantaniellobruun/radial/releases/latest` (campo `tag_name`).

## Cosa vedrà chi scarica un DMG non notarizzato

Finché non c'è la notarizzazione, macOS dice che "Radial non può essere aperto perché non è stato
possibile verificare l'assenza di software dannoso". Per aprirlo una volta:

- **Impostazioni di Sistema → Privacy e sicurezza**, in fondo: "Radial è stato bloccato" → **Apri
  comunque**; oppure
- dal Terminale: `xattr -dr com.apple.quarantine /Applications/Radial.app`.

Va scritto chiaramente nel README, finché serve.

## Idee per dopo

- **Aggiornamenti automatici con [Sparkle](https://sparkle-project.org/)**: l'app controlla un
  file `appcast.xml` (si può ospitare su GitHub Pages) e propone l'aggiornamento. Richiede una
  chiave di firma degli aggiornamenti e una dipendenza Swift Package.
- **Homebrew Cask**: `brew install --cask radial` dopo aver inviato un cask a
  [homebrew-cask](https://github.com/Homebrew/homebrew-cask) (serve un'app notarizzata).
- **Un rilascio automatico su GitHub Actions**: richiede un runner con macOS 26 e i certificati
  come segreti del repository.
