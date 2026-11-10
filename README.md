# trekking-percorsi

I percorsi dell'app Trekking per Garmin fēnix 7. Con la voce **Aggiorna percorsi** l'orologio scarica, col Bluetooth del telefono, l'elenco `index.json` da https://pietroni1.github.io/trekking-percorsi/ e poi un file `<id>.json` per ogni percorso nuovo o cambiato.

## Cosa c'è

- `routes/`: i file GPX e, per ogni percorso, i suoi bivi (`<id>.bivi.json`).
- `routes.config.json`: l'elenco dei percorsi pubblicati, con tappe e nomi dei sentieri.
- `tools/`: la conversione dai GPX ai file che legge l'orologio. Basta Node, senza pacchetti npm.
- `app/`: la nuova app per l'orologio, Trekking 2 (vedi sotto).
- `.github/workflows/pages.yml`: a ogni push su `main` GitHub Actions esegue `node tools/build_site.js` e pubblica il risultato con GitHub Pages.

`index.json` e i `<id>.json` non stanno nel repository: li prepara GitHub Actions a ogni push. Se la conversione dà errore, il sito resta com'era.

Il sito ha anche la cartella `v2/`, con lo stesso elenco e gli stessi percorsi nel formato di Trekking 2: in più ci sono i bivi e l'elenco delle tessere di mappa. I file dell'app attuale non cambiano.

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
3. Prepara i bivi con `node tools/osm_bivi.js <id>`: scarica i sentieri della zona da OpenStreetMap (`api.openstreetmap.org`) e scrive `routes/<id>.bivi.json`, con un'indicazione per ogni bivio (per esempio "Gira a destra, non dritto") e il disegno dei rami da non prendere. Leggi l'elenco che stampa: le indicazioni si possono correggere a mano nel file, ma rifare il comando le sovrascrive. Senza questo file il percorso funziona lo stesso, ma Trekking 2 non avvisa ai bivi.
4. Prova la conversione con `node tools/build_site.js`. Deve finire senza errori. Gli avvisi dicono se una tappa o la fine di un tratto è a più di 60 m dal tracciato, o se il percorso ha troppi punti per l'orologio.
5. Fai commit su `main` e push. In un paio di minuti GitHub lo pubblica: si vede nella scheda **Actions**, sotto "Pubblica i percorsi".
6. Sull'orologio, nell'elenco Percorsi, scegli **Aggiorna percorsi**.

Per togliere un percorso, togli la sua voce da `routes.config.json` (e il GPX): al prossimo aggiornamento sparisce anche dall'orologio.

## Trekking 2, la nuova app

La cartella `app/` contiene una nuova app per fēnix 7 (anche S, X e Pro), scritta da capo per non perdersi ai bivi. Si installa accanto a quella attuale, che resta com'è. **Non è ancora stata compilata né provata sull'orologio**: la logica della guida è stata provata solo con camminate simulate al computer.

Cosa fa:

- **Bivi:** a 60 m da un bivio decisivo vibra due volte, ingrandisce la mappa e mostra in alto freccia, distanza e indicazione; al bivio vibra tre volte; 20 m dopo conferma "Direzione giusta". I rami da non prendere sono disegnati in rosso con una croce. Ai bivi dove si prosegue dà un solo colpo.
- **Allarmi:** "Ramo sbagliato" dopo una ventina di metri sul ramo sbagliato di un bivio, "Fuori percorso" oltre 30 m dal tracciato, "Contromano" se cammini sul percorso nel verso opposto, e un avviso se salti un pezzo di percorso. Ogni allarme mostra la freccia e i metri per tornare.
- **Mappa:** sfondo satellitare, topografico o solo percorso; il percorso davanti a te va verso l'alto, oppure il nord. Le mappe si scaricano dal telefono con **Scarica mappe** (menu, tenendo premuto SU) e restano sull'orologio; quelle che mancano arrivano durante la camminata, se il telefono è collegato.
- **Registrazione:** START avvia un'attività di Escursionismo, con traccia GPS, battito, quota e dislivello, passi, temperatura e calorie; poi la trovi in Garmin Connect. START di nuovo mette in pausa e offre Riprendi, Salva o Scarta.
- **Tasti:** SU e GIÙ cambiano pagina (mappa, dati, profilo altimetrico); BACK passa dalla mappa vicina a tutto il percorso. Lo schermo tattile non fa nulla, per non mettere in pausa per sbaglio.

Per compilarla serve il Connect IQ SDK di Garmin, con una chiave da sviluppatore:

```
monkeyc -f app/monkey.jungle -d fenix7 -o app/bin/trekking2.prg -y <chiave.der>
```

Il file `trekking2.prg` va copiato nella cartella `GARMIN/APPS` dell'orologio collegato al computer. Al primo avvio scegli **Aggiorna percorsi**.

## Dal telefono

Il computer non serve: basta un push su `main`.

- **Con Claude:** nell'app Claude apri la scheda **Code** e avvia una sessione su `Pietroni1/trekking-percorsi`. Chiedi per esempio "Aggiungi questo percorso e pubblicalo". Claude segue `CLAUDE.md`: prepara GPX e voce, prova la conversione, fa push su `main` e controlla che GitHub l'abbia pubblicato. Se Claude deve costruire il GPX da OpenStreetMap, l'ambiente cloud deve poter raggiungere quei servizi (per esempio `overpass-api.de` per i sentieri e `api.opentopodata.org` per le quote): nelle impostazioni dell'ambiente scegli l'accesso di rete "Custom" con quei domini, oppure "Full".
- **Senza Claude:** su github.com, anche dal browser del telefono, apri la cartella `routes/`, poi **Add file → Upload files** per il GPX, e modifica `routes.config.json` con la matita. Ogni commit su `main` fa partire la pubblicazione.

Chiunque conosca l'indirizzo può vedere i percorsi.

Tracciati, bivi e quote: © OpenStreetMap contributors (ODbL), EU-DEM. Mappe di Trekking 2: immagini satellitari Esri World Imagery (Esri, Maxar, Earthstar Geographics); mappa topografica © OpenTopoMap (CC-BY-SA), dati © OpenStreetMap contributors e SRTM.
