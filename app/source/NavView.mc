import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// La schermata della camminata. Tre pagine, con SU e GIÙ:
//   0  la mappa: percorso, posizione, rami sbagliati ai bivi e in alto
//      l'indicazione per il prossimo bivio
//   1  i dati: tempo, distanza, battito, quota, salita, quanto manca
//   2  il profilo altimetrico
class NavView extends WatchUi.View {

    const MAPPA = 0;
    const DATI = 1;
    const PROFILO = 2;
    const PAGINE = 3;

    const ROSA = 0xFF00FF;      // il percorso ancora da fare
    const GIALLO = 0xFFFF00;
    const ROSSO = 0xFF0000;
    const VERDE = 0x00AA00;
    const BLU = 0x00AAFF;
    const GRIGIO = 0xAAAAAA;
    const SCURO = 0x555555;

    var pagina as Number = MAPPA;
    var tutto as Boolean = false;   // la mappa mostra tutto il percorso, col nord in alto
    var prova as Boolean = false;   // prova a casa: la posizione cammina da sola lungo il percorso

    const PASSO_PROVA = 5.0;        // metri al secondo della prova a casa
    const LONTANO = 500.0;          // oltre questi metri dal percorso si mostra tutto il percorso

    private var _g as Guida;
    private var _t as Tessere;
    private var _timer as Timer.Timer;
    private var _xf as Graphics.AffineTransform;
    private var _w as Number = 260;
    private var _h as Number = 260;

    // dalla mappa allo schermo: il punto (_ox, _oy) va in (_cx, _cy), ruotato e ridotto
    private var _cx as Float = 130.0;
    private var _cy as Float = 130.0;
    private var _ox as Float = 0.0;
    private var _oy as Float = 0.0;
    private var _cos as Float = 1.0;
    private var _sin as Float = 0.0;
    private var _ang as Float = 0.0;
    private var _scala as Float = 1.7;  // metri per pixel
    // il risultato di _schermo
    private var _sx as Float = 0.0;
    private var _sy as Float = 0.0;
    // il centro dello schermo sulla mappa
    private var _mx as Float = 0.0;
    private var _my as Float = 0.0;

    // il rettangolo che contiene il percorso
    private var _minX as Number = 0;
    private var _maxX as Number = 0;
    private var _minY as Number = 0;
    private var _maxY as Number = 0;
    private var _minEle as Number = 0;
    private var _maxEle as Number = 0;

    private var _provaM as Float = 0.0;     // metri fatti nella prova a casa
    private var _intero as Boolean = false; // in questo disegno si vede tutto il percorso
    private var _tessereViste as Number = 0;    // tessere disegnate in questo disegno
    private var _conSfondo as Boolean = false;  // in questo disegno lo sfondo era richiesto

    function initialize(guida as Guida, tessere as Tessere) {
        View.initialize();
        _g = guida;
        _t = tessere;
        _timer = new Timer.Timer();
        _xf = new Graphics.AffineTransform();
        var p = guida.p;
        _minX = p.xy[0];
        _maxX = p.xy[0];
        _minY = p.xy[1];
        _maxY = p.xy[1];
        _minEle = p.ele[0];
        _maxEle = p.ele[0];
        for (var i = 1; i < p.n; i++) {
            var x = p.xy[2 * i];
            var y = p.xy[2 * i + 1];
            var e = p.ele[i];
            if (x < _minX) { _minX = x; } else if (x > _maxX) { _maxX = x; }
            if (y < _minY) { _minY = y; } else if (y > _maxY) { _maxY = y; }
            if (e < _minEle) { _minEle = e; } else if (e > _maxEle) { _maxEle = e; }
        }
    }

    // Accende il GPS: va chiamata una volta, quando si apre il percorso.
    function apri() as Void {
        var opzioni = { :acquisitionType => Position.LOCATION_CONTINUOUS };
        if ((Position has :CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1) && (Position has :hasConfigurationSupport) &&
                Position.hasConfigurationSupport(Position.CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1)) {
            // tutti i sistemi di satelliti: nel bosco la posizione è più stabile
            opzioni[:configuration] = Position.CONFIGURATION_GPS_GLONASS_GALILEO_BEIDOU_L1;
        }
        Position.enableLocationEvents(opzioni, method(:onPosizione));
    }

    // Spegne il GPS: va chiamata quando si torna all'elenco.
    function chiudi() as Void {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
    }

    // Avvia o ferma la prova a casa: riparte da dove eravamo sul percorso, o dall'inizio.
    function impostaProva(attiva as Boolean) as Void {
        prova = attiva;
        _provaM = (attiva && _g.agganciato) ? _g.lungo : 0.0;
    }

    function onPosizione(info as Position.Info) as Void {
        if (prova) { return; }
        var loc = info.position;
        if (loc == null || info.accuracy == Position.QUALITY_NOT_AVAILABLE || info.accuracy == Position.QUALITY_LAST_KNOWN) {
            return;
        }
        var gradi = loc.toDegrees();
        _g.onFix(gradi[0].toDouble(), gradi[1].toDouble(), info.heading, info.speed, info.accuracy != Position.QUALITY_POOR);
    }

    // Passa alla pagina dopo (passo 1) o a quella prima (passo -1).
    function cambiaPagina(passo as Number) as Void {
        pagina = (pagina + passo + PAGINE) % PAGINE;
        WatchUi.requestUpdate();
    }

    function onShow() as Void {
        _timer.start(method(:onSecondo), 1000, true);
    }

    function onHide() as Void {
        _timer.stop();
    }

    function onSecondo() as Void {
        if (prova) {
            var g = _g;
            _provaM += PASSO_PROVA;
            if (_provaM >= g.p.lung) {
                _provaM = g.p.lung;
                prova = false;
            }
            var qui = g.punto(_provaM);
            var avanti = g.punto(_provaM + 6.0);
            var verso = (avanti[0] == qui[0] && avanti[1] == qui[1]) ? null : Math.atan2(avanti[0] - qui[0], avanti[1] - qui[1]).toFloat();
            g.onLocale(qui[0], qui[1], verso, PASSO_PROVA, true);
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();
        _h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (pagina == DATI) {
            _paginaDati(dc);
        } else if (pagina == PROFILO) {
            _paginaProfilo(dc);
        } else {
            _paginaMappa(dc);
        }
    }

    // ---------------------------------------------------------------- mappa

    private function _paginaMappa(dc as Graphics.Dc) as Void {
        var g = _g;
        var p = g.p;
        var m = p.map;
        var base = m != null ? (m["mx"] as Numeric).toFloat() : 1.7;   // a questa scala le tessere sono 1:1
        // lontani dal percorso (per esempio a casa) la mappa intorno a noi non serve:
        // si mostra tutto il percorso
        _intero = tutto || (g.haFix && !g.agganciato && g.fuori > LONTANO);
        _tessereViste = 0;
        _conSfondo = false;
        if (_intero) {
            var lw = (_maxX - _minX).toFloat();
            var lh = (_maxY - _minY).toFloat();
            _scala = (lw > lh ? lw : lh) / (_w * 0.72);
            if (_scala < base) { _scala = base; }
            _ox = (_minX + _maxX) / 2.0;
            _oy = (_minY + _maxY) / 2.0;
            _cx = _w / 2.0;
            _cy = _h / 2.0 + 8;
            _ang = 0.0;
        } else {
            _scala = (g.vicino || (g.perso && g.fuori < 90.0)) ? base / 2 : base;
            if (g.haFix && ((g.perso && g.fuori >= 90.0) || (!g.agganciato && g.fuori > 60.0))) {
                // lontani dal percorso: la mappa si allarga finché il percorso si vede
                var larga = g.fuori / (_w * 0.3);
                if (larga > _scala) { _scala = larga; }
            }
            _ox = g.px;
            _oy = g.py;
            _cx = _w / 2.0;
            _ang = (Imp.nord || !g.agganciato) ? 0.0 : g.orient;
            _cy = _ang == 0.0 && Imp.nord ? _h * 0.54 : _h * 0.62;
        }
        _cos = Math.cos(_ang).toFloat();
        _sin = Math.sin(_ang).toFloat();
        // il centro dello schermo sulla mappa
        var a = (_w / 2.0 - _cx) * _scala;
        var b = (_cy - _h / 2.0) * _scala;
        _mx = _ox + a * _cos + b * _sin;
        _my = _oy - a * _sin + b * _cos;
        var raggio = (_w / 2.0) * _scala;

        // lo sfondo solo da vicino: a scala piccola servirebbero troppe tessere
        if (!_intero && m != null && Imp.mappa != Imp.MAPPA_NESSUNA && _scala <= base * 1.2) {
            _conSfondo = true;
            _disegnaTessere(dc, m, raggio - 6 * _scala);
        }
        if (!_intero) { _disegnaRami(dc, raggio + 60.0); }
        _disegnaPercorso(dc, raggio + 120.0);
        _disegnaTappe(dc, raggio);
        if (!_intero && g.bivioInVista() && !g.perso && !g.contromano && g.agganciato) { _disegnaUscita(dc); }

        if (g.haFix) {
            if (g.perso || !g.agganciato) {
                // la linea verso il percorso
                _schermo(g.px, g.py);
                var x1 = _sx;
                var y1 = _sy;
                _schermo(g.nx, g.ny);
                dc.setPenWidth(5);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(x1, y1, _sx, _sy);
                dc.setPenWidth(2);
                dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(x1, y1, _sx, _sy);
                dc.drawCircle(_sx, _sy, 7);
            }
            _schermo(g.px, g.py);
            _segnaposto(dc, _sx, _sy, g.dir - _ang);
        }
        dc.setPenWidth(1);
        _fascia(dc);
        _piede(dc);
    }

    // Mette in _sx e _sy il punto dello schermo del punto (x, y) della mappa.
    private function _schermo(x as Numeric, y as Numeric) as Void {
        var dx = x - _ox;
        var dy = y - _oy;
        _sx = _cx + (dx * _cos - dy * _sin) / _scala;
        _sy = _cy - (dx * _sin + dy * _cos) / _scala;
    }

    private function _disegnaTessere(dc as Graphics.Dc, m as Dictionary, raggio as Float) as Void {
        _t.inizioDisegno();
        var zoom = m["z"] as Number;
        var x0 = m["x"] as Number;
        var y0 = m["y"] as Number;
        var ox = (m["ox"] as Numeric).toFloat();
        var mpx = (m["mx"] as Numeric).toFloat();
        var ry = m["ry"] as Array<Numeric>;
        var lato = 256.0 * mpx;
        var alto = (ry[0] - ry[1]).toFloat();
        var c0 = Math.floor((_mx - raggio - ox) / lato).toNumber();
        var c1 = Math.floor((_mx + raggio - ox) / lato).toNumber();
        var r0 = Math.floor((ry[0] - (_my + raggio)) / alto).toNumber();
        var r1 = Math.floor((ry[0] - (_my - raggio)) / alto).toNumber();
        var r2 = raggio * raggio;
        for (var riga = r0; riga <= r1; riga++) {
            var su = _bordo(ry, riga, alto);
            var giu = _bordo(ry, riga + 1, alto);
            for (var col = c0; col <= c1; col++) {
                var sinistra = ox + col * lato;
                // la tessera tocca il cerchio dello schermo?
                var qx = _mx < sinistra ? sinistra : (_mx > sinistra + lato ? sinistra + lato : _mx);
                var qy = _my > su ? su : (_my < giu ? giu : _my);
                if ((qx - _mx) * (qx - _mx) + (qy - _my) * (qy - _my) > r2) { continue; }
                var bmp = _t.prendi(Imp.mappa, zoom, x0 + col, y0 + riga);
                if (bmp == null) { continue; }
                _tessereViste++;
                _schermo(sinistra, su);
                // la tessera può arrivare più piccola di 256 pixel: la scala segue i suoi pixel veri
                var ax = lato / bmp.getWidth() / _scala;
                var ay = (su - giu) / bmp.getHeight() / _scala;
                if (_ang == 0.0 && ax > 0.98 && ax < 1.02) {
                    dc.drawBitmap(Math.round(_sx), Math.round(_sy), bmp);
                } else {
                    _xf.setMatrix([ax * _cos, ay * _sin, _sx, -ax * _sin, ay * _cos, _sy]);
                    dc.drawBitmap2(0, 0, bmp, { :transform => _xf, :filterMode => Graphics.FILTER_MODE_POINT });
                }
            }
        }
    }

    // Il bordo superiore della riga di tessere k, contata dalla prima del percorso.
    private function _bordo(ry as Array<Numeric>, k as Number, alto as Float) as Float {
        var ultimo = ry.size() - 1;
        if (k < 0) { return ry[0].toFloat() - k * alto; }
        if (k > ultimo) { return ry[ultimo].toFloat() - (k - ultimo) * alto; }
        return ry[k].toFloat();
    }

    // Il percorso: grigio quello già fatto, rosa quello da fare, col bordo nero.
    private function _disegnaPercorso(dc as Graphics.Dc, raggio as Float) as Void {
        var g = _g;
        var xy = g.p.xy;
        var n = g.p.n;
        var r2 = raggio * raggio;
        var seg = g.agganciato ? g.seg : -1;
        for (var passata = 0; passata < 2; passata++) {
            var prima = false;      // il punto prima era nello schermo
            var haA = false;        // (ax, ay) è il punto prima, già sullo schermo
            var ax = 0.0;
            var ay = 0.0;
            var colore = -1;
            if (passata == 0) {
                dc.setPenWidth(7);
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            }
            for (var i = 0; i < n; i++) {
                var x = xy[2 * i];
                var y = xy[2 * i + 1];
                var dx = x - _mx;
                var dy = y - _my;
                var dentro = _intero || dx * dx + dy * dy < r2;
                if (dentro || prima) {
                    if (i > 0) {
                        if (!haA) {
                            _schermo(xy[2 * i - 2], xy[2 * i - 1]);
                            ax = _sx;
                            ay = _sy;
                        }
                        _schermo(x, y);
                        if (passata == 1) {
                            var c = (i - 1 < seg) ? GRIGIO : ROSA;
                            if (c != colore) {
                                colore = c;
                                dc.setPenWidth(c == ROSA ? 4 : 3);
                                dc.setColor(c, Graphics.COLOR_TRANSPARENT);
                            }
                        }
                        dc.drawLine(ax, ay, _sx, _sy);
                        ax = _sx;
                        ay = _sy;
                        haA = true;
                    }
                } else {
                    haA = false;
                }
                prima = dentro;
            }
        }
    }

    // I rami da non prendere, in rosso con una croce in fondo.
    private function _disegnaRami(dc as Graphics.Dc, raggio as Float) as Void {
        var p = _g.p;
        var xy = p.xy;
        var r2 = raggio * raggio;
        for (var k = 0; k < p.bivi.size(); k++) {
            var b = p.bivi[k] as Array;
            var i = b[0] as Number;
            var jx = xy[2 * i];
            var jy = xy[2 * i + 1];
            var dx = jx - _mx;
            var dy = jy - _my;
            if (dx * dx + dy * dy > r2) { continue; }
            var rami = b[5] as Array<Number>;
            var q = 0;
            while (q + 1 < rami.size()) {
                var np = rami[q + 1];
                for (var passata = 0; passata < 2; passata++) {
                    dc.setPenWidth(passata == 0 ? 6 : 3);
                    dc.setColor(passata == 0 ? Graphics.COLOR_BLACK : ROSSO, Graphics.COLOR_TRANSPARENT);
                    var ax = 0.0;
                    var ay = 0.0;
                    for (var m = 0; m < np; m++) {
                        _schermo(jx + rami[q + 2 + 2 * m], jy + rami[q + 3 + 2 * m]);
                        if (m > 0) { dc.drawLine(ax, ay, _sx, _sy); }
                        ax = _sx;
                        ay = _sy;
                    }
                    // la croce in fondo al ramo
                    var c = passata == 0 ? 6 : 5;
                    dc.drawLine(ax - c, ay - c, ax + c, ay + c);
                    dc.drawLine(ax - c, ay + c, ax + c, ay - c);
                }
                q += 2 + 2 * np;
            }
        }
    }

    // Le tappe: un pallino bianco.
    private function _disegnaTappe(dc as Graphics.Dc, raggio as Float) as Void {
        var p = _g.p;
        var r2 = raggio * raggio;
        for (var k = 0; k < p.wps.size(); k++) {
            var i = (p.wps[k] as Array)[0] as Number;
            var x = p.xy[2 * i];
            var y = p.xy[2 * i + 1];
            var dx = x - _mx;
            var dy = y - _my;
            if (!_intero && dx * dx + dy * dy > r2) { continue; }
            _schermo(x, y);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(_sx, _sy, 6);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(_sx, _sy, 4);
        }
    }

    // Il prossimo bivio: un cerchio giallo e la punta di freccia sull'uscita giusta.
    private function _disegnaUscita(dc as Graphics.Dc) as Void {
        var g = _g;
        var i = (g.p.bivi[g.ka] as Array)[0] as Number;
        _schermo(g.p.xy[2 * i], g.p.xy[2 * i + 1]);
        dc.setPenWidth(2);
        dc.setColor(GIALLO, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(_sx, _sy, 10);
        var q = g.dopoBivio(g.ka, 26.0);
        _schermo(q[0], q[1]);
        _punta(dc, _sx, _sy, g.uscita(g.ka) - _ang, 11, Graphics.COLOR_BLACK);
        _punta(dc, _sx, _sy, g.uscita(g.ka) - _ang, 8, GIALLO);
    }

    // Una punta di freccia piena con il centro in (x, y), rivolta verso ang
    // (radianti, 0 in alto, in senso orario).
    private function _punta(dc as Graphics.Dc, x as Float, y as Float, ang as Float, r as Number, colore as Number) as Void {
        var s = Math.sin(ang);
        var c = Math.cos(ang);
        dc.setColor(colore, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [x + r * s, y - r * c],
            [x + r * (0.8 * c - 0.7 * s), y + r * (0.8 * s + 0.7 * c)],
            [x - r * (0.8 * c + 0.7 * s), y - r * (0.8 * s - 0.7 * c)]
        ]);
    }

    // Dove siamo: una freccia azzurra bordata di bianco, rivolta verso ang.
    private function _segnaposto(dc as Graphics.Dc, x as Float, y as Float, ang as Float) as Void {
        var s = Math.sin(ang);
        var c = Math.cos(ang);
        for (var passata = 0; passata < 2; passata++) {
            var k = passata == 0 ? 1.45 : 1.0;
            dc.setColor(passata == 0 ? Graphics.COLOR_WHITE : BLU, Graphics.COLOR_TRANSPARENT);
            // punta, destra, rientro, sinistra
            dc.fillPolygon([
                [x + k * 12 * s, y - k * 12 * c],
                [x + k * (8 * c - 9 * s), y + k * (8 * s + 9 * c)],
                [x - k * 4 * s, y + k * 4 * c],
                [x + k * (-8 * c - 9 * s), y + k * (-8 * s + 9 * c)]
            ]);
        }
    }

    // La freccia di svolta: il gambo sale e poi piega di ang (radianti, positivo a destra).
    private function _freccia(dc as Graphics.Dc, x as Number, y as Number, r as Number, ang as Float, colore as Number) as Void {
        var s = Math.sin(ang);
        var c = Math.cos(ang);
        var fx = x + r * s;
        var fy = y - r * c;
        dc.setColor(colore, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(4);
        dc.drawLine(x, y + r, x, y);
        dc.drawLine(x, y, fx, fy);
        dc.fillPolygon([
            [fx + 7 * s, fy - 7 * c],
            [fx + 6 * c, fy + 6 * s],
            [fx - 6 * c, fy - 6 * s]
        ]);
        dc.setPenWidth(1);
    }

    // La larghezza dello schermo rotondo all'altezza y.
    private function _corda(y as Number) as Number {
        var r = _w / 2.0;
        var d = r - y;
        if (d < 0) { d = -d; }
        if (d >= r) { return 0; }
        return (2 * Math.sqrt(r * r - d * d)).toNumber() - 14;
    }

    // Spezza il testo in al più due righe, la prima larga l1.
    private function _spezza(dc as Graphics.Dc, testo as String, font as Graphics.FontType, l1 as Number) as Array<String> {
        if (dc.getTextWidthInPixels(testo, font) <= l1) { return [testo]; }
        var lettere = testo.toCharArray();
        var taglio = -1;
        for (var i = 1; i < lettere.size(); i++) {
            if (lettere[i] == ' ') {
                if (dc.getTextWidthInPixels(testo.substring(0, i) as String, font) > l1) { break; }
                taglio = i;
            }
        }
        if (taglio < 0) { return [testo]; }
        return [testo.substring(0, taglio) as String, testo.substring(taglio + 1, testo.length()) as String];
    }

    // La fascia in alto: l'indicazione più importante del momento.
    private function _fascia(dc as Graphics.Dc) as Void {
        var g = _g;
        var ora = System.getTimer();
        var fondo = Graphics.COLOR_BLACK;
        var testo = Graphics.COLOR_WHITE;
        var riga1 = "";
        var riga2 = null;
        var svolta = null;      // l'angolo della freccia di svolta, se c'è
        var verso = null;       // l'angolo sullo schermo della freccia verso il percorso, se c'è

        if (!g.haFix) {
            riga1 = "Attendo il GPS";
        } else if (!g.agganciato) {
            riga1 = "Al percorso";
            riga2 = _metri(g.fuori);
            verso = _versoPercorso();
        } else if (g.perso) {
            fondo = ROSSO;
            // in alto lo schermo è stretto: lì va la riga corta
            riga1 = "torna " + _metri(g.fuori);
            riga2 = g.ramo ? "RAMO SBAGLIATO" : "FUORI PERCORSO";
            verso = _versoPercorso();
        } else if (g.contromano) {
            fondo = ROSSO;
            riga1 = "CONTROMANO";
            riga2 = "stai tornando indietro";
        } else if (g.msgTappa != null && ora < g.msgFino) {
            fondo = 0x0055AA;
            riga1 = g.msgTappa as String;
            riga2 = g.msgTappa2;
        } else if (g.arrivato) {
            fondo = VERDE;
            riga1 = "Arrivo";
            riga2 = Registra.stato != Registra.FERMA ? "START per salvare" : null;
        } else if (ora < g.giustoFino) {
            fondo = VERDE;
            riga1 = "Direzione giusta";
        } else if (g.bivioInVista()) {
            var b = g.p.bivi[g.ka] as Array;
            if ((b[1] as Number) >= 2 && g.fase >= 2) {
                fondo = GIALLO;
                testo = Graphics.COLOR_BLACK;
            }
            riga1 = g.distBivio <= 8.0 ? "ora" : _metri(g.distBivio);
            riga2 = b[4] as String;
            svolta = Math.toRadians(_giro((b[3] as Number) - (b[2] as Number))).toFloat();
        } else if (g.ka >= 0) {
            riga1 = "bivio " + _metri(g.distBivio);
            riga2 = g.tratto();
        } else {
            riga1 = "arrivo " + _metri(g.restano());
            riga2 = g.tratto();
        }

        // lo schermo è rotondo: in alto c'è poco spazio, la prima riga è la più corta
        var conFreccia = svolta != null || verso != null;
        var y1 = 13;
        var f1 = Graphics.FONT_TINY;
        var f2 = Graphics.FONT_XTINY;
        if (dc.getTextWidthInPixels(riga1, f1) + (conFreccia ? 34 : 0) > _corda(y1 + 6)) { f1 = f2; }
        var h1 = dc.getFontHeight(f1);
        var h2 = dc.getFontHeight(f2);
        var y2 = y1 + h1 - 2;
        var righe = [] as Array<String>;
        if (riga2 != null) { righe = _spezza(dc, riga2, f2, _corda(y2 + 2)); }
        var alta = y2 + righe.size() * (h2 - 2) + 5;
        if (righe.size() == 0) { alta = y1 + h1 + 4; }

        dc.setColor(fondo, fondo);
        dc.fillRectangle(0, 0, _w, alta);
        // la prima riga, con la freccia a sinistra del testo
        var l1 = dc.getTextWidthInPixels(riga1, f1);
        var x = (_w - l1) / 2 + (conFreccia ? 17 : 0);
        dc.setColor(testo, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y1, f1, riga1, Graphics.TEXT_JUSTIFY_LEFT);
        if (svolta != null) {
            _freccia(dc, x - 20, y1 + h1 / 2 + 2, 11, svolta, testo);
        } else if (verso != null) {
            _punta(dc, (x - 20).toFloat(), (y1 + h1 / 2).toFloat(), verso, 10, testo);
        }
        dc.setColor(testo, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < righe.size(); i++) {
            dc.drawText(_w / 2, y2 + i * (h2 - 2), f2, righe[i], Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // L'angolo sullo schermo verso il punto più vicino del percorso.
    private function _versoPercorso() as Float {
        var g = _g;
        return (Math.atan2(g.nx - g.px, g.ny - g.py) - _ang).toFloat();
    }

    // Un angolo in gradi fra -180 e 180.
    private function _giro(gradi as Number) as Number {
        return ((gradi + 540) % 360) - 180;
    }

    // La riga in basso: tempo e chilometri che mancano.
    private function _piede(dc as Graphics.Dc) as Void {
        var g = _g;
        var testo;
        if (_conSfondo && _tessereViste == 0) {
            // lo sfondo è acceso ma qui non c'è: si dice perché
            var e = _t.errore;
            if (!System.getDeviceSettings().phoneConnected) {
                testo = "mappa: manca il telefono";
            } else if (e != 0) {
                testo = "mappa: errore " + e.format("%d");
            } else {
                testo = "mappa in arrivo...";
            }
        } else if (prova) {
            testo = "PROVA  -" + _metri(g.restano());
        } else if (_intero && !tutto) {
            // lontani dal percorso: si può vedere l'app al lavoro anche da qui
            testo = "tieni SU: prova a casa";
        } else if (Registra.stato == Registra.FERMA) {
            testo = "START per partire";
        } else {
            var info = Activity.getActivityInfo();
            var ms = info != null ? info.timerTime : null;
            testo = (Registra.stato == Registra.PAUSA ? "PAUSA " : "") + _tempo(ms);
            if (g.agganciato) { testo += "  -" + _metri(g.restano()); }
        }
        // in fondo allo schermo rotondo c'è poco spazio: la riga sta in alto nella fascia
        var f = Graphics.FONT_XTINY;
        var alta = dc.getFontHeight(f) + 20;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, _h - alta, _w, alta);
        dc.setColor(Registra.stato == Registra.ATTIVA ? Graphics.COLOR_WHITE : GIALLO, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_w / 2, _h - alta + 2, f, testo, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // ----------------------------------------------------------------- dati

    private function _paginaDati(dc as Graphics.Dc) as Void {
        var g = _g;
        var info = Activity.getActivityInfo();
        var ora = System.getClockTime();
        var fEtichetta = Graphics.FONT_XTINY;
        var fValore = Graphics.FONT_MEDIUM;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_w / 2, 8, Graphics.FONT_TINY, ora.hour.format("%d") + ":" + ora.min.format("%02d"), Graphics.TEXT_JUSTIFY_CENTER);

        var etichette = ["Tempo", "Distanza", "Battito", "Quota", "Salita", "Mancano"];
        var valori = ["--", "--", "--", "--", "--", "--"];
        if (info != null) {
            if (Registra.stato != Registra.FERMA) {
                valori[0] = _tempo(info.timerTime);
                var d = info.elapsedDistance;
                if (d != null) { valori[1] = _metri(d); }
                var su = info.totalAscent;
                if (su != null) { valori[4] = su.format("%d") + " m"; }
            }
            var hr = info.currentHeartRate;
            if (hr != null) { valori[2] = hr.format("%d"); }
            var quota = info.altitude;
            if (quota != null) { valori[3] = quota.toNumber().format("%d") + " m"; }
        }
        if (g.agganciato) { valori[5] = _metri(g.restano()); }

        var top = (_h * 0.17).toNumber();
        var passo = (_h * 0.235).toNumber();
        var hE = dc.getFontHeight(fEtichetta);
        dc.setColor(SCURO, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(_w / 2, top + 4, _w / 2, top + 3 * passo - 4);
        for (var r = 1; r < 3; r++) { dc.drawLine(14, top + r * passo, _w - 14, top + r * passo); }
        for (var k = 0; k < 6; k++) {
            var x = (k % 2 == 0) ? _w / 4 + 8 : 3 * _w / 4 - 8;
            var y = top + (k / 2) * passo + 3;
            dc.setColor(GRIGIO, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, fEtichetta, etichette[k], Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(k == 2 ? ROSSO : Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y + hE - 4, fValore, valori[k], Graphics.TEXT_JUSTIFY_CENTER);
        }
        var stato = Registra.stato == Registra.ATTIVA ? "registra" : (Registra.stato == Registra.PAUSA ? "PAUSA" : "non registra");
        dc.setColor(Registra.stato == Registra.ATTIVA ? VERDE : GIALLO, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_w / 2, top + 3 * passo + 2, fEtichetta, stato + "  " + System.getSystemStats().battery.toNumber().format("%d") + "%", Graphics.TEXT_JUSTIFY_CENTER);
    }

    // -------------------------------------------------------------- profilo

    private function _paginaProfilo(dc as Graphics.Dc) as Void {
        var g = _g;
        var p = g.p;
        var x0 = (_w * 0.13).toNumber();
        var x1 = _w - x0;
        var yBase = (_h * 0.70).toNumber();
        var yCima = (_h * 0.36).toNumber();
        var dEle = _maxEle - _minEle;
        if (dEle < 20) { dEle = 20; }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_w / 2, 10, Graphics.FONT_TINY, "mancano " + (g.agganciato ? _metri(g.restano()) : _metri(p.lung)), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(GRIGIO, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_w / 2, 10 + dc.getFontHeight(Graphics.FONT_TINY) - 2, Graphics.FONT_XTINY,
            "salita " + g.salitaRestante().format("%d") + " m   cima " + _maxEle.format("%d") + " m", Graphics.TEXT_JUSTIFY_CENTER);

        // una colonna per pixel: grigio il già fatto, verde il da fare
        var j = 0;
        var qui = g.agganciato ? g.lungo : -1.0;
        var xQui = -1;
        var yQui = yBase;
        for (var x = x0; x <= x1; x++) {
            var s = p.lung * (x - x0) / (x1 - x0);
            while (j < p.n - 2 && p.cum[j + 1] < s) { j++; }
            var l = p.cum[j + 1] - p.cum[j];
            var t = l > 0.0 ? (s - p.cum[j]) / l : 0.0;
            var e = p.ele[j] + t * (p.ele[j + 1] - p.ele[j]);
            var y = yBase - (e - _minEle) * (yBase - yCima) / dEle;
            dc.setColor(s <= qui ? SCURO : VERDE, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(x, yBase, x, y);
            if (xQui < 0 && s >= qui && qui >= 0.0) {
                xQui = x;
                yQui = y.toNumber();
            }
        }
        if (xQui >= 0) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(2);
            dc.drawLine(xQui, yCima - 8, xQui, yBase);
            dc.setPenWidth(1);
            dc.fillCircle(xQui, yQui, 4);
        }
        dc.setColor(GRIGIO, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x0, yBase + 2, Graphics.FONT_XTINY, _minEle.format("%d") + " m", Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(x1, yBase + 2, Graphics.FONT_XTINY, _metri(p.lung), Graphics.TEXT_JUSTIFY_RIGHT);
        var info = Activity.getActivityInfo();
        var quota = info != null ? info.altitude : null;
        if (quota != null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_w / 2, yBase + dc.getFontHeight(Graphics.FONT_XTINY), Graphics.FONT_SMALL, "quota " + quota.toNumber().format("%d") + " m", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    // ------------------------------------------------------------- formati

    // Una distanza: "85 m", "350 m", "1,2 km".
    private function _metri(m as Float) as String {
        if (m < 0.0) { m = 0.0; }
        if (m < 100.0) { return (Math.round(m / 5.0).toNumber() * 5).format("%d") + " m"; }
        if (m < 1000.0) { return (Math.round(m / 10.0).toNumber() * 10).format("%d") + " m"; }
        var etti = Math.round(m / 100.0).toNumber();
        return (etti / 10).format("%d") + "," + (etti % 10).format("%d") + " km";
    }

    // Un tempo in millisecondi: "1:23:45".
    private function _tempo(ms as Number?) as String {
        if (ms == null) { return "0:00:00"; }
        var s = ms / 1000;
        return (s / 3600).format("%d") + ":" + ((s % 3600) / 60).format("%02d") + ":" + (s % 60).format("%02d");
    }
}
