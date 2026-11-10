// Trova i bivi lungo un percorso confrontando il GPX con OpenStreetMap e scrive
// routes/<id>.bivi.json, che tools/gpx_to_route.js unisce al percorso.
//
// Uso (dalla cartella del repository):
//   node tools/osm_bivi.js <id> [--osm <file.osm>]
//
// Senza --osm scarica con curl l'estratto da api.openstreetmap.org (serve la rete).
//
// Un bivio è un nodo di OpenStreetMap sul tracciato da cui parte almeno una via
// che il percorso NON prende. Se il percorso ci passa due volte (andata e
// ritorno) sono due bivi, ognuno con la sua direzione. I bivi a meno di 25 m
// l'uno dall'altro diventano uno solo. Per ogni bivio:
//   m          metri dall'inizio del tracciato
//   lat, lon   il punto
//   in, out    direzione di arrivo e di uscita, gradi da nord
//   liv        2 decisivo: il percorso svolta, cambia sentiero o c'è un ramo
//                sbagliato che invita; l'orologio avvisa e ingrandisce la mappa
//              1 si prosegue, con una via laterale: avviso breve
//              0 una via si unisce da dietro: solo disegnata sulla mappa
//   msg        l'indicazione per l'orologio; si può correggere a mano
//   rami       le vie da non prendere: tipo (s sentiero, c carraia, r strada) e
//              il disegno dei primi metri, in metri a est e a nord del bivio; il
//              primo punto è dove il ramo si stacca dal percorso
//
// Rigenerare il file sovrascrive le correzioni fatte a mano.
const fs = require("fs");
const path = require("path");
const { parseGpx, readConfig, ROOT } = require("./gpx_to_route");

const VICINO = 10;      // un nodo è sul percorso entro questi metri
const PASSO = 20;       // metri prima e dopo il bivio per misurare le direzioni
const RAMO = 50;        // metri di ogni ramo sbagliato da disegnare
const GRUPPO = 25;     // bivi più vicini di così diventano uno solo
const NON_A_PIEDI = new Set(["motorway", "motorway_link", "trunk", "trunk_link", "proposed", "construction", "razed", "abandoned"]);

const rad = x => x * Math.PI / 180;
const norm = a => ((a + 540) % 360) - 180;
const bearing = (a, b) => (Math.atan2(b.x - a.x, b.y - a.y) * 180 / Math.PI + 360) % 360;

function parseOsm(xml) {
  const nodes = new Map();
  for (const m of xml.matchAll(/<node id="(\d+)"[^>]*? lat="([-\d.]+)" lon="([-\d.]+)"/g)) nodes.set(m[1], { lat: +m[2], lon: +m[3] });
  const tagsOf = s => { const t = {}; for (const m of s.matchAll(/<tag k="([^"]*)" v="([^"]*)"/g)) t[m[1]] = m[2]; return t; };
  const ways = new Map();
  for (const m of xml.matchAll(/<way id="(\d+)"[^>]*>([\s\S]*?)<\/way>/g)) {
    const tags = tagsOf(m[2]);
    if (!tags.highway || NON_A_PIEDI.has(tags.highway) || tags.area === "yes") continue;
    ways.set(m[1], { id: m[1], nd: [...m[2].matchAll(/<nd ref="(\d+)"/g)].map(x => x[1]), tags, refs: [] });
  }
  for (const m of xml.matchAll(/<relation id="(\d+)"[^>]*>([\s\S]*?)<\/relation>/g)) {
    const tags = tagsOf(m[2]);
    if (tags.route !== "hiking" && tags.route !== "foot") continue;
    const ref = tags.ref || tags.name;
    if (!ref) continue;
    for (const w of m[2].matchAll(/<member type="way" ref="(\d+)"/g)) {
      const way = ways.get(w[1]);
      if (way && !way.refs.includes(ref)) way.refs.push(ref);
    }
  }
  return { nodes, ways };
}

// Posizione lungo una polilinea con distanze cumulate (campo d), a s metri dall'inizio.
function along(line, s) {
  if (s <= 0) return line[0];
  const last = line[line.length - 1];
  if (s >= last.d) return last;
  let lo = 0, hi = line.length - 1;
  while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (line[mid].d <= s) lo = mid; else hi = mid; }
  const a = line[lo], b = line[hi], t = (s - a.d) / (b.d - a.d || 1);
  return { x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y), d: s };
}

function segProj(p, a, b) {
  const dx = b.x - a.x, dy = b.y - a.y, L = dx * dx + dy * dy;
  let t = L ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / L : 0;
  t = Math.max(0, Math.min(1, t));
  return { dist: Math.hypot(a.x + t * dx - p.x, a.y + t * dy - p.y), t };
}

// Distanza di p dal tratto di tracciato fra s0 e s1 metri.
function distToTrack(trk, p, s0, s1) {
  let best = Infinity;
  for (let i = 0; i < trk.length - 1; i++) {
    if (trk[i + 1].d < s0 || trk[i].d > s1) continue;
    const d = segProj(p, trk[i], trk[i + 1]).dist;
    if (d < best) best = d;
  }
  return best;
}

function tipoVia(tags) {
  const h = tags.highway;
  if (h === "path" || h === "footway" || h === "steps" || h === "bridleway" || h === "cycleway" || h === "pedestrian") return "s";
  if (h === "track") return "c";
  return "r";
}

// Semplifica una polilinea di [x, y] (Douglas-Peucker).
function sfoltisci(pts, tol) {
  if (pts.length < 3) return pts;
  const a = pts[0], b = pts[pts.length - 1];
  let idx = -1, md = tol;
  for (let i = 1; i < pts.length - 1; i++) {
    const d = segProj({ x: pts[i][0], y: pts[i][1] }, { x: a[0], y: a[1] }, { x: b[0], y: b[1] }).dist;
    if (d > md) { md = d; idx = i; }
  }
  if (idx < 0) return [a, b];
  return sfoltisci(pts.slice(0, idx + 1), tol).slice(0, -1).concat(sfoltisci(pts.slice(idx), tol));
}

// Il numero del sentiero CAI di una via, se ne ha uno solo (per esempio "110A").
function sentiero(vie) {
  const refs = new Set();
  for (const w of vie) for (const r of w.refs) if (/^\d+[A-Za-z]?$/.test(r)) refs.add(r);
  return refs.size === 1 ? [...refs][0] : null;
}

function trovaBivi(trkLatLon, osm) {
  const lat0 = trkLatLon[0].lat, lon0 = trkLatLon[0].lon;
  const kx = 111320 * Math.cos(rad(lat0)), ky = 110950;
  const proj = p => ({ x: (p.lon - lon0) * kx, y: (p.lat - lat0) * ky });
  const trk = trkLatLon.map(proj);
  let cum = 0;
  trk.forEach((p, i) => { if (i) cum += Math.hypot(p.x - trk[i - 1].x, p.y - trk[i - 1].y); p.d = cum; });

  // grafo: per ogni nodo, i vicini e la via che li collega
  const adj = new Map();
  const link = (a, b, way) => { if (!adj.has(a)) adj.set(a, new Map()); if (!adj.get(a).has(b)) adj.get(a).set(b, way); };
  for (const way of osm.ways.values()) {
    for (let i = 0; i < way.nd.length - 1; i++) {
      if (!osm.nodes.has(way.nd[i]) || !osm.nodes.has(way.nd[i + 1]) || way.nd[i] === way.nd[i + 1]) continue;
      link(way.nd[i], way.nd[i + 1], way); link(way.nd[i + 1], way.nd[i], way);
    }
  }
  const P = new Map();
  const pos = id => { let p = P.get(id); if (!p) { p = proj(osm.nodes.get(id)); P.set(id, p); } return p; };

  // Segue una via dal bivio j verso il vicino n per al più max metri: dove c'è una
  // sola prosecuzione va avanti, a un altro bivio si ferma.
  const segui = (j, n, max) => {
    const line = [{ ...pos(j), d: 0 }];
    let prev = j, cur = n, d = 0, cieca = false;
    for (;;) {
      const a = line[line.length - 1], b = pos(cur), step = Math.hypot(b.x - a.x, b.y - a.y);
      if (d + step >= max) { const t = (max - d) / step; line.push({ x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y), d: max }); break; }
      d += step; line.push({ ...b, d });
      const next = [...adj.get(cur).keys()].filter(k => k !== prev);
      if (next.length !== 1) { cieca = next.length === 0; break; }
      prev = cur; cur = next[0];
    }
    return { line, cieca };
  };

  // Posizione lungo il tracciato (metri) del punto più vicino a p fra s0 e s1.
  const lungo = (p, s0, s1) => {
    let best = Infinity, bs = null;
    for (let i = 0; i < trk.length - 1; i++) {
      if (trk[i + 1].d < s0 || trk[i].d > s1) continue;
      const pr = segProj(p, trk[i], trk[i + 1]);
      if (pr.dist < best) { best = pr.dist; bs = trk[i].d + pr.t * (trk[i + 1].d - trk[i].d); }
    }
    return { dist: best, s: bs };
  };

  const nodi = [];
  for (const [id, vicini] of adj) {
    if (vicini.size < 3) continue;
    const J = pos(id);
    // passaggi: minimi della distanza dal tracciato, a più di 50 m l'uno dall'altro
    const passaggi = [];
    let run = null;
    for (let i = 0; i < trk.length - 1; i++) {
      const pr = segProj(J, trk[i], trk[i + 1]);
      if (pr.dist > VICINO) continue;
      const s = trk[i].d + pr.t * (trk[i + 1].d - trk[i].d);
      if (run && s - run.last <= 50) { if (pr.dist < run.dist) { run.dist = pr.dist; run.s = s; } run.last = s; }
      else { run = { dist: pr.dist, s, last: s }; passaggi.push(run); }
    }
    for (const { s } of passaggi) {
      if (s >= 15 && s <= cum - 15) nodi.push({ id, J, s, vicini }); // partenza e arrivo: lì parla la tappa
    }
  }
  nodi.sort((a, b) => a.s - b.s);

  // Per ogni nodo: direzioni di arrivo e di uscita e rami che il percorso non prende.
  // Fra bivi vicini le direzioni si misurano su un tratto più corto.
  nodi.forEach((n, k) => {
    const { id, J, s } = n;
    const prima = Math.max(8, Math.min(PASSO, k ? s - nodi[k - 1].s : PASSO));
    const dopo = Math.max(8, Math.min(PASSO, k < nodi.length - 1 ? nodi[k + 1].s - s : PASSO));
    n.in = bearing(along(trk, s - prima), J);
    n.out = bearing(J, along(trk, s + dopo));
    n.rami = []; n.vieIn = []; n.vieOut = [];
    for (const [v, way] of n.vicini) {
      const { line, cieca } = segui(id, v, RAMO);
      const len = line[line.length - 1].d, probe = along(line, Math.min(PASSO, len));
      const a = lungo(probe, s - PASSO - 30, s + PASSO + 30);
      const meta = lungo(along(line, Math.min(PASSO, len) / 2), s - PASSO - 30, s + PASSO + 30);
      if (a.dist < 8 && meta.dist < 8) { (a.s < s ? n.vieIn : n.vieOut).push(way); continue; } // è il percorso
      if (cieca && len < 15) continue; // moncone
      n.rami.push({ b: bearing(J, probe), tipo: tipoVia(way.tags), way, pts: line.slice(1).map(p => [p.x - J.x, p.y - J.y]) });
    }
    Object.assign(n, indicazione(n));
  });

  // gruppi di bivi vicini
  const gruppi = [];
  for (const n of nodi.filter(n => n.rami.length)) {
    const g = gruppi[gruppi.length - 1];
    if (g && n.s - g[g.length - 1].s < GRUPPO) g.push(n); else gruppi.push([n]);
  }

  const bivi = gruppi.map(g => {
    const primo = g[0];
    const liv = Math.max(...g.map(n => n.liv));
    // l'indicazione: quelle dei bivi del gruppo dove c'è da scegliere, in ordine
    const scelte = g.filter(n => n.liv > 0);
    // dà le direzioni della freccia: fra i bivi più importanti del gruppo, la svolta più decisa
    const svolta = n => Math.abs(norm(n.out - n.in));
    const guida = scelte.filter(n => n.liv === liv).sort((a, b) => svolta(b) - svolta(a))[0] || primo;
    // due indicazioni di seguito dalla stessa parte sono una svolta sola: resta la più
    // decisa; dopo una svolta, "dritto" è sottinteso
    const parte = m => (/^(?:Tieni la|Gira a|Svolta stretta a|Leggermente a|Tutto a) (destra|sinistra)/.exec(m) || [])[1];
    const frasi = [];
    for (const n of scelte) {
      const u = frasi[frasi.length - 1], T = Math.abs(norm(n.out - n.in));
      if (!u) frasi.push({ T, msg: n.msg });
      else if (parte(n.msg) && parte(n.msg) === parte(u.msg)) { if (T > u.T) frasi[frasi.length - 1] = { T, msg: n.msg }; }
      else if (parte(n.msg)) frasi.push({ T, msg: n.msg });
    }
    const msg = frasi.length ? frasi.map((f, i) => i ? f.msg[0].toLowerCase() + f.msg.slice(1) : f.msg).join(", poi ") : primo.msg;
    const rami = [];
    for (const n of g) for (const r of n.rami) {
      rami.push({ tipo: r.tipo, pts: sfoltisci([[0, 0], ...r.pts], 2)
        .map(([x, y]) => [Math.round(x + n.J.x - primo.J.x), Math.round(y + n.J.y - primo.J.y)]) });
    }
    const nd = osm.nodes.get(primo.id);
    return { m: Math.round(primo.s), lat: nd.lat, lon: nd.lon, in: Math.round(guida.in), out: Math.round(guida.out), liv, msg, rami };
  });
  return { bivi, len: cum };
}

// Livello e testo dell'indicazione a un nodo. R è la direzione di un ramo sbagliato
// rispetto a quella di arrivo (0 dritto, positivo a destra), T quella del percorso.
function indicazione(n) {
  const T = norm(n.out - n.in), aT = Math.abs(T), lato = x => x > 0 ? "destra" : "sinistra";
  const da = sentiero(n.vieIn), a = sentiero(n.vieOut);
  const avanti = n.rami.map(r => ({ R: norm(r.b - n.in), way: r.way })).filter(r => Math.abs(r.R) <= 120);
  let msg = aT < 20 ? "Dritto" : aT < 45 ? `Tieni la ${lato(T)}` : aT < 120 ? `Gira a ${lato(T)}` : `Svolta stretta a ${lato(T)}`;
  if (!avanti.length) return { liv: 0, msg }; // le altre vie si uniscono da dietro
  const cambia = a && a !== da;
  const tenta = aT >= 45 || avanti.some(r => Math.abs(r.R) <= 60 || Math.abs(r.R - T) <= 45 || (cambia && r.way.refs.includes(da)));
  const dx = avanti.filter(r => r.R > T), sx = avanti.filter(r => r.R < T); // rami a destra e a sinistra dell'uscita
  let no = "";
  if (aT >= 45) {
    const stesso = avanti.filter(r => (r.R > 0) === (T > 0) && Math.abs(r.R) >= 25 && Math.abs(r.R - T) <= 60);
    if (avanti.some(r => Math.abs(r.R) < 25)) no = ", non dritto";
    else if (stesso.length) msg = `${stesso.some(r => Math.abs(r.R) > aT) ? "Leggermente" : "Tutto"} a ${lato(T)}`;
  } else if (dx.length && sx.length) {
    msg = "Dritto al centro";
  } else {
    const rami = dx.length ? dx : sx, vicino = Math.min(...rami.map(r => Math.abs(r.R - T)));
    if (vicino <= 35 || (aT >= 12 && vicino <= 90)) msg = `Tieni la ${dx.length ? "sinistra" : "destra"}`;
    else { msg = "Dritto"; no = `, non a ${dx.length ? "destra" : "sinistra"}`; }
  }
  if (cambia) msg += ` sul ${a}`;
  return { liv: tenta ? 2 : 1, msg: msg + no };
}

function scarica(trk, file) {
  const m = 0.003; // circa 300 m intorno al tracciato
  const lats = trk.map(p => p.lat), lons = trk.map(p => p.lon);
  const bbox = [Math.min(...lons) - m, Math.min(...lats) - m, Math.max(...lons) + m, Math.max(...lats) + m].map(v => v.toFixed(5)).join(",");
  require("child_process").execFileSync("curl", ["-sS", "--fail", "-m", "180", "-o", file, `https://api.openstreetmap.org/api/0.6/map?bbox=${bbox}`], { stdio: "inherit" });
}

function scrivi(file, bivi) {
  const righe = bivi.map(b => "    " + JSON.stringify(b));
  fs.writeFileSync(file, `{\n  "fonte": "OpenStreetMap, ${new Date().toISOString().slice(0, 10)}",\n  "bivi": [\n${righe.join(",\n")}\n  ]\n}\n`);
}

module.exports = { parseOsm, trovaBivi };

if (require.main === module) {
  const args = process.argv.slice(2);
  const r = readConfig().find(x => x.id === args[0]);
  if (!r) { console.error(`uso: node tools/osm_bivi.js <id> [--osm <file.osm>]\npercorso "${args[0]}" non trovato in routes.config.json`); process.exit(1); }
  const { trk } = parseGpx(fs.readFileSync(path.join(ROOT, r.gpx), "utf8"));
  const io = args.indexOf("--osm");
  let osmFile = io >= 0 ? args[io + 1] : null;
  if (!osmFile) {
    osmFile = path.join(require("os").tmpdir(), `${r.id}.osm`);
    scarica(trk, osmFile);
  }
  const { bivi } = trovaBivi(trk, parseOsm(fs.readFileSync(osmFile, "utf8")));
  const out = path.join(ROOT, r.gpx.replace(/\.gpx$/, ".bivi.json"));
  scrivi(out, bivi);
  for (const b of bivi) console.log(`km ${(b.m / 1000).toFixed(2)}  ${"·!‼"[b.liv]}  ${b.msg.padEnd(34)} ${b.rami.length} ${b.rami.length === 1 ? "ramo" : "rami"}`);
  const n = l => bivi.filter(b => b.liv === l).length;
  console.log(`${bivi.length} bivi (${n(2)} decisivi, ${n(1)} con vie laterali, ${n(0)} confluenze) in ${path.relative(ROOT, out)}`);
}
