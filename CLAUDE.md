# Istruzioni per Claude

Questo repository contiene i percorsi dell'app Trekking per Garmin fēnix 7 e li pubblica con GitHub Pages. L'utente parla italiano. Il README spiega i campi di `routes.config.json`.

Per aggiungere o cambiare un percorso:

1. GPX in `routes/` e voce in `routes.config.json`, come nel README.
2. `node tools/build_site.js` deve finire senza errori. Leggi gli avvisi: tappe o fine di un tratto a più di 60 m dal tracciato, troppi punti.
3. Pubblicare vuol dire fare push su `main`: il workflow `.github/workflows/pages.yml` parte solo da lì. Se la sessione lavora su un altro ramo (per esempio `claude/...`), alla fine porta il commit anche su `main`:
   ```
   git fetch origin main && git rebase origin/main && git push origin HEAD:main
   ```
4. Controlla che GitHub l'abbia pubblicato. Il sito `pietroni1.github.io` di solito non è raggiungibile dalle sessioni cloud, quindi guarda l'ultima esecuzione del workflow finché non è `completed` con `success`:
   ```
   gh api "repos/Pietroni1/trekking-percorsi/actions/runs?branch=main&per_page=1" --jq '.workflow_runs[0] | {status, conclusion, html_url}'
   ```
   Poi l'utente sceglie "Aggiorna percorsi" sull'orologio.

Non cambiare il formato dei file generati e non aggiungere `index.json` o `<id>.json` al repository: l'orologio legge `{"routes": [{id, name, sub, file, h}]}`, con `h` uguale ai primi 8 caratteri esadecimali dello SHA-1 del file del percorso, e scarica solo i percorsi la cui `h` è cambiata.
