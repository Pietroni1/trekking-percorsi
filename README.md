# trekking-percorsi

I percorsi dell'app Trekking per Garmin fēnix 7. Con la voce **Aggiorna percorsi** l'orologio scarica, col Bluetooth del telefono, l'elenco `index.json` da https://pietroni1.github.io/trekking-percorsi/ e poi un file `<id>.json` per ogni percorso nuovo o cambiato.

## Cosa c'è

- `routes/`: i file GPX.
- `routes.config.json`: l'elenco dei percorsi pubblicati, con tappe e nomi dei sentieri.
- `tools/`: la conversione dai GPX ai file che legge l'orologio. Basta Node, senza pacchetti npm.
- `.github/workflows/pages.yml`: a ogni push su `main` GitHub Actions esegue `node tools/build_site.js` e pubblica il risultato con GitHub Pages.

`index.json` e i `<id>.json` non stanno nel repository: li prepara GitHub Actions a ogni push. Se la conversione dà errore, il sito resta com'era.

## Aggiungere un percorso

1. Metti il GPX in `routes/`. Deve contenere il tracciato e un waypoint per ogni tappa, nell'ordine. La prima tappa è sempre l'inizio del tracciato. Se l'ultima tappa non ha un waypoint, è la fine del tracciato.
2. Aggiungi una voce in `routes.config.json`, per esempio (accorciata):
   ```json
   {
     "id": "monte-adone",
     "name": "Monte Adone",
     "sub": "Anello da Badolo, 9,7 km",
     "gpx": "routes/monte-adone.gpx",
     "tappe": [
       { "name": "Badolo", "msg": "Partenza: sentiero 110" },
       { "name": "Monte Adone", "msg": "Vetta 655 m" },
       { "name": "Badolo", "msg": "Arrivo" }
     ],
     "tratti": [
       { "name": "Sentiero 110", "fino": [44.34422, 11.30345] },
       { "name": "Sentiero 912" }
     ]
   }
   ```
   - `id`: lettere minuscole, numeri e trattini, diverso per ogni percorso. Sul sito diventa il nome del file, `<id>.json`.
   - `name` e `sub`: le due righe nell'elenco dei percorsi sull'orologio.
   - `tappe`: per ogni tappa il nome e l'indicazione breve che l'orologio mostra quando ci arrivi.
   - `tratti` (facoltativo): i nomi dei sentieri. Ogni tratto finisce nel punto `fino` (latitudine, longitudine), l'ultimo arriva alla fine. Senza tratti, tutto il giro prende il nome del percorso.
   - `tolerance` (facoltativo): quanto si semplifica il tracciato, in metri. Normalmente 3.
   - `nellApp` (facoltativo): `true` se il percorso è anche dentro l'app. Lo usa solo il computer, quando si ricompila l'app.
3. Prova la conversione con `node tools/build_site.js`. Deve finire senza errori. Gli avvisi dicono se una tappa o la fine di un tratto è a più di 60 m dal tracciato, o se il percorso ha troppi punti per l'orologio.
4. Fai commit su `main` e push. In un paio di minuti GitHub lo pubblica: si vede nella scheda **Actions**, sotto "Pubblica i percorsi".
5. Sull'orologio, nell'elenco Percorsi, scegli **Aggiorna percorsi**.

Per togliere un percorso, togli la sua voce da `routes.config.json` (e il GPX): al prossimo aggiornamento sparisce anche dall'orologio.

## Dal telefono

Il computer non serve: basta un push su `main`.

- **Con Claude:** nell'app Claude apri la scheda **Code** e avvia una sessione su `Pietroni1/trekking-percorsi`. Chiedi per esempio "Aggiungi questo percorso e pubblicalo". Claude segue `CLAUDE.md`: prepara GPX e voce, prova la conversione, fa push su `main` e controlla che GitHub l'abbia pubblicato. Se Claude deve costruire il GPX da OpenStreetMap, l'ambiente cloud deve poter raggiungere quei servizi (per esempio `overpass-api.de` per i sentieri e `api.opentopodata.org` per le quote): nelle impostazioni dell'ambiente scegli l'accesso di rete "Custom" con quei domini, oppure "Full".
- **Senza Claude:** su github.com, anche dal browser del telefono, apri la cartella `routes/`, poi **Add file → Upload files** per il GPX, e modifica `routes.config.json` con la matita. Ogni commit su `main` fa partire la pubblicazione.

Chiunque conosca l'indirizzo può vedere i percorsi.

Tracciati e quote: © OpenStreetMap contributors (ODbL), EU-DEM.
