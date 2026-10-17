// Converte i percorsi GPX elencati in routes.config.json nel formato che l'app
// Trekking legge sull'orologio.
//
// Per ogni percorso: tracciato semplificato (tolleranza 3 m), coordinate in
// gradi x 1e6 come interi, quote in metri e tappe agganciate al punto del
// tracciato più vicino, nell'ordine in cui si incontrano.
//
// Lo usano tools/build_site.js, che prepara il sito scaricato dall'orologio, e
// sul computer tools/gpx_to_route.js del progetto dell'app, per i percorsi
// inclusi nell'app. Basta Node, senza pacchetti npm.
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");

const rad = x => x * Math.PI / 180;

function parseGpx(xml) {
  const num = (s, re) => { const m = s.match(re); return m ? parseFloat(m[1]) : null; };
  const trk = [];
  for (const m of xml.matchAll(/<trkpt\b([^>]*)>([\s\S]*?)<\/trkpt>|<trkpt\b([^>]*)\/>/g)) {
    const attrs = m[1] || m[3];
    trk.push({
      lat: num(attrs, /lat="([-\d.]+)"/),
      lon: num(attrs, /lon="([-\d.]+)"/),
      ele: m[2] ? num(m[2], /<ele>([-\d.]+)<\/ele>/) : null,
    });
  }
  const wpt = [];
  for (const m of xml.matchAll(/<wpt\b([^>]*)>([\s\S]*?)<\/wpt>/g)) {
    wpt.push({ lat: num(m[1], /lat="([-\d.]+)"/), lon: num(m[1], /lon="([-\d.]+)"/) });
  }
  return { trk, wpt };
}

function simplify(pts, tol) {
  const keep = new Uint8Array(pts.length);
  keep[0] = keep[pts.length - 1] = 1;
  const stack = [[0, pts.length - 1]];
  while (stack.length) {
    const [a, b] = stack.pop();
    const A = pts[a], B = pts[b];
    const dx = B.x - A.x, dy = B.y - A.y, L = dx * dx + dy * dy;
    let idx = -1, md = 0;
    for (let i = a + 1; i < b; i++) {
      const P = pts[i];
      let t = L ? ((P.x - A.x) * dx + (P.y - A.y) * dy) / L : 0;
      t = Math.max(0, Math.min(1, t));
      const ex = A.x + t * dx - P.x, ey = A.y + t * dy - P.y, d = ex * ex + ey * ey;
      if (d > md) { md = d; idx = i; }
    }
    if (idx > 0 && md > tol * tol) { keep[idx] = 1; stack.push([a, idx], [idx, b]); }
  }
  return pts.filter((_, i) => keep[i]);
}

function readConfig() {
  return JSON.parse(fs.readFileSync(path.join(ROOT, "routes.config.json"), "utf8"));
}

// Converte i percorsi di config (default: tutti quelli di routes.config.json).
function buildRoutes(config = readConfig()) {
  const out = [];
  for (const r of config) {
    const { trk, wpt } = parseGpx(fs.readFileSync(path.join(ROOT, r.gpx), "utf8"));
    if (trk.length < 2) throw new Error(`${r.id}: tracciato vuoto`);
    const lat0 = trk[0].lat, lon0 = trk[0].lon;
    const kx = 111320 * Math.cos(rad(lat0)), ky = 110950;
    const proj = p => ({ ...p, x: (p.lon - lon0) * kx, y: (p.lat - lat0) * ky });
    const full = trk.map(proj);
    const pts = simplify(full, r.tolerance || 3);

    let cum = 0;
    pts.forEach((p, i) => { if (i) cum += Math.hypot(p.x - pts[i - 1].x, p.y - pts[i - 1].y); p.d = cum; });

    // tappe: dalla prima all'ultima, ognuna sul punto più vicino dopo la precedente
    const stops = r.tappe;
    const anchors = wpt.map(proj);
    const wps = [];
    let from = 0;
    stops.forEach((s, k) => {
      let i;
      if (k === 0) i = 0;
      else if (k === stops.length - 1 && k >= anchors.length) i = pts.length - 1;
      else {
        const a = anchors[k];
        if (!a) throw new Error(`${r.id}: manca il waypoint ${k + 1} nel GPX`);
        let best = Infinity;
        for (let j = from; j < pts.length; j++) {
          const d = Math.hypot(pts[j].x - a.x, pts[j].y - a.y);
          if (d < best) { best = d; i = j; }
        }
        if (best > 60) console.warn(`  attenzione: "${s.name}" è a ${Math.round(best)} m dal tracciato`);
      }
      from = i;
      wps.push({ name: s.name, msg: s.msg, i });
    });

    // tratti: nome del sentiero da un punto all'altro; ogni tratto finisce dove indicato da "fino"
    const tratti = [];
    let start = 0;
    (r.tratti || [{ name: r.name }]).forEach(t => {
      tratti.push({ name: t.name, i: start });
      if (!t.fino) return;
      const f = proj({ lat: t.fino[0], lon: t.fino[1] });
      let best = Infinity, bi = start;
      for (let j = start; j < pts.length; j++) {
        const d = Math.hypot(pts[j].x - f.x, pts[j].y - f.y);
        if (d < best) { best = d; bi = j; }
      }
      if (best > 60) console.warn(`  attenzione: la fine di "${t.name}" è a ${Math.round(best)} m dal tracciato`);
      start = bi;
    });

    out.push({
      id: r.id,
      name: r.name,
      sub: r.sub,
      len: Math.round(cum),
      pts: pts.flatMap(p => [Math.round(p.lat * 1e6), Math.round(p.lon * 1e6)]),
      ele: pts.map(p => Math.round(p.ele ?? 0)),
      wps,
      tratti,
    });
    console.log(`${r.id}: ${trk.length} -> ${pts.length} punti, ${(cum / 1000).toFixed(2)} km, ${wps.length} tappe`);
    wps.forEach(w => console.log(`  ${w.name.padEnd(22)} km ${(pts[w.i].d / 1000).toFixed(2)}  ${w.msg}`));
    tratti.forEach(t => console.log(`  tratto ${t.name.padEnd(15)} da km ${(pts[t.i].d / 1000).toFixed(2)}`));
  }
  return out;
}

module.exports = { buildRoutes, readConfig, ROOT };
