// Converte i percorsi nel formato v2, quello che legge la nuova app (cartella app/):
// oltre a tracciato, quote, tappe e tratti contiene i bivi di routes/<id>.bivi.json
// (li prepara tools/osm_bivi.js) e l'elenco delle tessere di mappa lungo il percorso.
//
// Le coordinate sono in metri interi a est e a nord del primo punto del tracciato:
// l'orologio converte solo la posizione GPS, con "o" (latitudine e longitudine
// dell'origine, in gradi x 1e6) e "k" (metri per grado di longitudine e latitudine).
//
//   xy      il tracciato semplificato: x0, y0, x1, y1, ...
//   ele     la quota di ogni punto, in metri
//   wps     le tappe: [punto, nome, indicazione]
//   tratti  i nomi dei sentieri: [punto da cui vale, nome]
//   bivi    [punto, livello, direzione di arrivo, di uscita, indicazione, rami];
//           rami elenca le vie da non prendere, una dopo l'altra: tipo (0 sentiero,
//           1 carraia, 2 strada), numero di punti, poi x e y di ogni punto in metri
//           dal bivio, a partire da dove il ramo si stacca dal percorso
//   map     le tessere di mappa (zoom z) lungo il percorso: x e y sono la colonna e la
//           riga della prima, ox la coordinata locale del suo bordo sinistro, mx i
//           metri per pixel in orizzontale, ry il bordo superiore di ogni riga da y in
//           giù, l le tessere da scaricare (colonna e riga, contate da x e y)
const fs = require("fs");
const path = require("path");
const { parseGpx, simplify, readConfig, ROOT } = require("./gpx_to_route");

const ZOOM = 16;        // zoom delle tessere: a 44° nord sono 1,7 m per pixel
const CORRIDOIO = 150;  // si scaricano le tessere entro questi metri dal tracciato
const TIPO = { s: 0, c: 1, r: 2 };

const rad = x => x * Math.PI / 180;

function buildRoutesV2(config = readConfig()) {
  const out = [];
  for (const r of config) {
    const { trk, wpt } = parseGpx(fs.readFileSync(path.join(ROOT, r.gpx), "utf8"));
    if (trk.length < 2) throw new Error(`${r.id}: tracciato vuoto`);
    const lat0 = trk[0].lat, lon0 = trk[0].lon;
    const kx = 111320 * Math.cos(rad(lat0)), ky = 110950;
    const proj = p => ({ ...p, x: (p.lon - lon0) * kx, y: (p.lat - lat0) * ky });
    const full = trk.map(proj);
    let cum = 0;
    full.forEach((p, i) => { if (i) cum += Math.hypot(p.x - full[i - 1].x, p.y - full[i - 1].y); p.m = cum; });

    // i bivi: ognuno sul punto del tracciato più vicino, che la semplificazione non toglie
    const biviFile = path.join(ROOT, r.gpx.replace(/\.gpx$/, ".bivi.json"));
    const bivi = fs.existsSync(biviFile) ? JSON.parse(fs.readFileSync(biviFile, "utf8")).bivi : [];
    if (!bivi.length) console.warn(`  attenzione: ${r.id} non ha bivi: prepara ${path.relative(ROOT, biviFile)} con tools/osm_bivi.js`);
    const fissi = new Set([0, full.length - 1]);
    for (const b of bivi) {
      const q = proj(b);
      let best = Infinity;
      full.forEach((p, i) => {
        if (Math.abs(p.m - b.m) > 30) return;
        const d = Math.hypot(p.x - q.x, p.y - q.y);
        if (d < best) { best = d; b.p = p; b.fi = i; }
      });
      if (best > 15) throw new Error(`${r.id}: il bivio a ${b.m} m non è sul tracciato: rigenera i bivi con tools/osm_bivi.js`);
      fissi.add(b.fi);
    }
    const tagli = [...fissi].sort((a, b) => a - b);
    const pts = [];
    for (let k = 0; k < tagli.length - 1; k++) {
      const pezzo = simplify(full.slice(tagli[k], tagli[k + 1] + 1), r.tolerance || 3);
      pts.push(...(k ? pezzo.slice(1) : pezzo));
    }
    let len = 0;
    pts.forEach((p, i) => { if (i) len += Math.hypot(p.x - pts[i - 1].x, p.y - pts[i - 1].y); p.d = len; });

    // tappe e tratti, come nel formato attuale
    const anchors = wpt.map(proj);
    const wps = [];
    let from = 0;
    r.tappe.forEach((s, k) => {
      let i;
      if (k === 0) i = 0;
      else if (k === r.tappe.length - 1 && k >= anchors.length) i = pts.length - 1;
      else {
        const a = anchors[k];
        if (!a) throw new Error(`${r.id}: manca il waypoint ${k + 1} nel GPX`);
        let best = Infinity;
        for (let j = from; j < pts.length; j++) {
          const d = Math.hypot(pts[j].x - a.x, pts[j].y - a.y);
          if (d < best) { best = d; i = j; }
        }
      }
      from = i;
      wps.push([i, s.name, s.msg]);
    });
    const tratti = [];
    let start = 0;
    (r.tratti || [{ name: r.name }]).forEach(t => {
      tratti.push([start, t.name]);
      if (!t.fino) return;
      const f = proj({ lat: t.fino[0], lon: t.fino[1] });
      let best = Infinity, bi = start;
      for (let j = start; j < pts.length; j++) {
        const d = Math.hypot(pts[j].x - f.x, pts[j].y - f.y);
        if (d < best) { best = d; bi = j; }
      }
      start = bi;
    });

    // tessere di mappa entro CORRIDOIO metri dal tracciato
    const n = 2 ** ZOOM;
    const colDi = lon => (lon + 180) / 360 * n;
    const rigaDi = lat => (1 - Math.asinh(Math.tan(rad(lat))) / Math.PI) / 2 * n;
    const latDi = riga => Math.atan(Math.sinh(Math.PI * (1 - 2 * riga / n))) * 180 / Math.PI;
    const tessere = new Set();
    for (let i = 0; i < full.length - 1; i++) {
      const a = full[i], b = full[i + 1], passi = Math.max(1, Math.ceil(Math.hypot(b.x - a.x, b.y - a.y) / 25));
      for (let s = 0; s <= passi; s++) {
        const x = a.x + (b.x - a.x) * s / passi, y = a.y + (b.y - a.y) * s / passi;
        for (const [ex, ey] of [[-1, -1], [-1, 1], [1, -1], [1, 1], [0, 0]]) {
          const lon = lon0 + (x + ex * CORRIDOIO) / kx, lat = lat0 + (y + ey * CORRIDOIO) / ky;
          tessere.add(`${Math.floor(colDi(lon))},${Math.floor(rigaDi(lat))}`);
        }
      }
    }
    const lista = [...tessere].map(t => t.split(",").map(Number));
    const x0 = Math.min(...lista.map(t => t[0])), y0 = Math.min(...lista.map(t => t[1])), y1 = Math.max(...lista.map(t => t[1]));
    const ry = [];
    for (let riga = y0; riga <= y1 + 1; riga++) ry.push(Math.round((latDi(riga) - lat0) * ky * 10) / 10);
    // ordinate lungo il percorso, così le prime scaricate sono quelle della partenza
    const ordine = new Map();
    full.forEach(p => {
      const k = `${Math.floor(colDi(p.lon))},${Math.floor(rigaDi(p.lat))}`;
      if (!ordine.has(k)) ordine.set(k, p.m);
    });
    const centro = t => ({ x: ((t[0] + 0.5) / n * 360 - 180 - lon0) * kx, y: (latDi(t[1] + 0.5) - lat0) * ky });
    const quando = t => {
      const k = `${t[0]},${t[1]}`;
      if (ordine.has(k)) return ordine.get(k);
      const c = centro(t);
      let best = Infinity, m = 0;
      for (const p of full) { const d = Math.hypot(p.x - c.x, p.y - c.y); if (d < best) { best = d; m = p.m; } }
      return m + 0.5;
    };
    lista.sort((a, b) => quando(a) - quando(b));

    out.push({
      v: 2,
      id: r.id,
      name: r.name,
      sub: r.sub,
      len: Math.round(len),
      o: [Math.round(lat0 * 1e6), Math.round(lon0 * 1e6)],
      k: [Math.round(kx), ky],
      xy: pts.flatMap(p => [Math.round(p.x), Math.round(p.y)]),
      ele: pts.map(p => Math.round(p.ele ?? 0)),
      wps,
      tratti,
      bivi: bivi.map(b => [pts.indexOf(b.p), b.liv, b.in, b.out, b.msg,
        b.rami.flatMap(ramo => [TIPO[ramo.tipo], ramo.pts.length, ...ramo.pts.flat()])]),
      map: {
        z: ZOOM, x: x0, y: y0,
        ox: Math.round(((x0 / n * 360 - 180) - lon0) * kx * 10) / 10,
        mx: Math.round(360 / n / 256 * kx * 1e5) / 1e5,
        ry,
        l: lista.flatMap(t => [t[0] - x0, t[1] - y0]),
      },
    });
    console.log(`${r.id} (v2): ${pts.length} punti, ${bivi.length} bivi, ${lista.length} tessere di mappa`);
  }
  return out;
}

module.exports = { buildRoutesV2 };
