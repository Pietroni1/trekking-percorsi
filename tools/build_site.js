// Prepara i file che l'orologio scarica con "Aggiorna percorsi".
//
// Uso (dalla cartella del repository):  node tools/build_site.js [--out <cartella>]
//
// Converte tutti i percorsi di routes.config.json e scrive nella cartella
// (predefinita: _site):
//   index.json   l'elenco che l'orologio scarica per primo: id, nome, file e
//                impronta (h) di ogni percorso
//   <id>.json    un file per percorso, nello stesso formato degli elementi di
//                resources/jsonData/routes.json dell'app
// L'orologio scarica solo i percorsi nuovi o cambiati (impronta diversa), uno
// alla volta, così la memoria basta anche con molti percorsi.
//
// A ogni push su main, GitHub Actions (.github/workflows/pages.yml) lo esegue e
// pubblica la cartella con GitHub Pages.
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { buildRoutes, readConfig, ROOT } = require("./gpx_to_route");

// Oltre questi punti un percorso rischia di superare i 32 KB che Application.Storage
// accetta per ogni valore: sull'orologio un percorso occupa circa 19 byte a punto
// (Monte Adone, 245 punti: 4,7 KB).
const MAX_POINTS = 1300;

function buildSite(outDir, config = readConfig()) {
  const ids = new Set();
  for (const r of config) {
    if (!/^[a-z0-9-]+$/.test(r.id)) throw new Error(`id "${r.id}": usa solo lettere minuscole, numeri e trattini`);
    if (ids.has(r.id)) throw new Error(`id "${r.id}" ripetuto`);
    ids.add(r.id);
  }

  const routes = buildRoutes(config);
  fs.mkdirSync(outDir, { recursive: true });
  for (const f of fs.readdirSync(outDir)) {
    if (f.endsWith(".json")) fs.rmSync(path.join(outDir, f));
  }
  const index = [];
  for (const r of routes) {
    const n = r.pts.length / 2;
    if (n > MAX_POINTS) console.warn(`  attenzione: ${r.id} ha ${n} punti, troppi per l'orologio: alza "tolerance" in routes.config.json`);
    const json = JSON.stringify(r);
    const file = `${r.id}.json`;
    fs.writeFileSync(path.join(outDir, file), json);
    index.push({ id: r.id, name: r.name, sub: r.sub, file, h: crypto.createHash("sha1").update(json).digest("hex").slice(0, 8) });
  }
  fs.writeFileSync(path.join(outDir, "index.json"), JSON.stringify({ routes: index }));
  fs.writeFileSync(path.join(outDir, ".nojekyll"), "");
  const rel = path.relative(process.cwd(), outDir);
  console.log(`scritti index.json e ${routes.length} percorsi in ${rel && !rel.startsWith("..") ? rel : outDir}`);
  return index;
}

module.exports = { buildSite };

if (require.main === module) {
  const args = process.argv.slice(2);
  const i = args.indexOf("--out");
  buildSite(path.resolve(i >= 0 ? args[i + 1] : path.join(ROOT, "_site")));
}
