import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

// Segue la posizione lungo il percorso: dove siamo, quanto manca al prossimo
// bivio, se siamo usciti dal percorso. Decide anche quando avvisare.
//
// Il percorso può passare due volte dallo stesso sentiero (andata e ritorno):
// per questo la posizione si cerca prima vicino a dove eravamo, e in tutto il
// percorso solo se lì non c'è più.
class Guida {

    const LARGO = 35.0;         // oltre questi metri dal tratto vicino si cerca in tutto il percorso
    const FUORI = 30.0;         // oltre questi metri dal percorso è "fuori percorso"
    const RIENTRO = 12.0;       // sotto questi metri si è di nuovo sul percorso
    const PREAVVISO = 60.0;     // primo avviso prima di un bivio decisivo
    const ADESSO = 15.0;        // secondo avviso, al bivio
    const LIEVE = 35.0;         // avviso unico per un bivio con una via laterale
    const VISTA = 80.0;         // da qui il bivio si vede ingrandito
    const TAPPA = 20.0;         // una tappa è raggiunta a questi metri

    var p as Percorso;

    // posizione
    var haFix as Boolean = false;
    var px as Float = 0.0;          // dove siamo, metri a est e a nord dell'inizio
    var py as Float = 0.0;
    var dir as Float = 0.0;         // direzione di marcia, radianti da nord
    var seg as Number = 0;          // siamo fra i punti seg e seg + 1
    var lungo as Float = 0.0;       // metri fatti lungo il percorso
    var fuori as Float = 0.0;       // metri dal percorso
    var nx as Float = 0.0;          // il punto del percorso più vicino
    var ny as Float = 0.0;
    var agganciato as Boolean = false;  // siamo stati sul percorso almeno una volta
    var perso as Boolean = false;       // fuori percorso
    var ramo as Boolean = false;        // fuori percorso su un ramo sbagliato di un bivio
    var contromano as Boolean = false;  // sul percorso, ma camminando nel verso opposto
    var orient as Float = 0.0;      // direzione del percorso qui, per orientare la mappa

    // bivi
    var ka as Number = -1;          // il prossimo bivio da segnalare (livello 1 o 2), -1 se non ce ne sono
    var distBivio as Float = 0.0;   // metri che mancano al bivio ka
    var fase as Number = 0;         // avvisi già dati per il bivio ka: 0 nessuno, 1 preavviso, 2 "adesso"
    var vicino as Boolean = false;  // c'è un bivio da guardare ingrandito
    var giustoFino as Number = 0;   // fino a questo momento (ms) si mostra "direzione giusta"

    // tappe
    var msgTappa as String? = null; // la tappa appena raggiunta: nome
    var msgTappa2 as String? = null;    // e la sua indicazione
    var msgFino as Number = 0;      // fino a questo momento (ms) si mostra la tappa
    var arrivato as Boolean = false;

    private var _kb as Number = 0;          // primo bivio non ancora superato, di qualunque livello
    private var _kw as Number = 0;          // prossima tappa
    private var _conferma as Number = -1;   // bivio decisivo appena superato, da confermare
    private var _passato as Number = -1;    // ultimo bivio segnalato superato
    private var _fasi as Array<Number>;     // avvisi già dati a ogni bivio: 1 preavviso, 2 "adesso", 3 confermato
    private var _inMoto as Boolean = false;
    private var _ds as Float = 0.0;         // seno e coseno della direzione di marcia
    private var _dc as Float = 1.0;
    private var _fermoVerso as Number = 0;  // secondi in cui non si cambia passaggio per il verso
    private var _nRetro as Number = 0;
    private var _saltato as Boolean = false;    // siamo rientrati sul percorso in un altro punto
    private var _nFuori as Number = 0;
    private var _nRamo as Number = 0;
    private var _nContro as Number = 0;
    private var _passi as Number = 0;
    private var _ultimoAllarme as Number = 0;
    // risultato di _cerca
    private var _bj as Number = 0;
    private var _bt as Float = 0.0;
    private var _bd2 as Float = 0.0;
    // risultato di _puntoA
    private var _qx as Float = 0.0;
    private var _qy as Float = 0.0;

    function initialize(percorso as Percorso) {
        p = percorso;
        px = p.xy[0].toFloat();
        py = p.xy[1].toFloat();
        nx = px;
        ny = py;
        _fasi = new Array<Number>[p.bivi.size()];
        for (var k = 0; k < _fasi.size(); k++) { _fasi[k] = 0; }
        _aggiornaBivi();
    }

    // Una nuova posizione GPS. lat e lon in gradi, direzione in radianti da nord
    // (null se non si sa), velocità in m/s, buona: false se il segnale è scarso.
    function onFix(lat as Double, lon as Double, direzione as Float?, vel as Float?, buona as Boolean) as Void {
        var ora = System.getTimer();
        haFix = true;
        px = p.xDi(lon);
        py = p.yDi(lat);
        var inMoto = vel != null && vel > 0.5;
        if (direzione != null && (inMoto || !agganciato)) { dir = direzione; }
        _inMoto = inMoto;
        _ds = Math.sin(dir).toFloat();
        _dc = Math.cos(dir).toFloat();

        var prima = lungo;
        _aggancia(inMoto);
        // un salto lungo il percorso: abbiamo tagliato, o siamo finiti su un altro tratto
        var salto = lungo - prima;
        var saltoOra = false;
        if (agganciato && fuori <= FUORI && (salto > 300.0 || salto < -300.0)) {
            msgTappa = salto > 0.0 ? "Saltati " + _km(salto) : "Indietro di " + _km(-salto);
            msgTappa2 = "controlla dove sei";
            msgFino = ora + 10000;
            _saltato = true;
            saltoOra = true;
            Avvisi.tappa();
        }

        if (!agganciato) {
            if (fuori <= 20.0) {
                agganciato = true;
                orient = _direzionePercorso();
            }
        } else if (!perso) {
            // con il segnale scarso l'allarme arriva lo stesso, ma dopo il doppio delle conferme
            var conferme = buona ? 3 : 6;
            if (fuori > FUORI) { _nFuori++; } else { _nFuori = 0; }
            if (inMoto && fuori > 15.0 && _suUnRamo()) { _nRamo++; } else { _nRamo = 0; }
            if (_nFuori >= conferme || _nRamo >= conferme) {
                perso = true;
                ramo = _nRamo >= conferme;
                _conferma = -1;
                _ultimoAllarme = ora;
                Avvisi.perso();
            }
        } else if (fuori < RIENTRO) {
            perso = false;
            ramo = false;
            _nFuori = 0;
            _nRamo = 0;
            if (!_saltato) {
                giustoFino = ora + 4000;
                Avvisi.giusto();
            }
            _saltato = false;
        } else if (ora - _ultimoAllarme > 25000) {
            _ultimoAllarme = ora;
            Avvisi.perso();
        }

        if (!agganciato) { return; }

        // contromano: sul percorso, ma da venti secondi in cammino nel verso opposto
        if (inMoto) {
            if (!perso && _contrario(seg)) { _nRetro++; } else { _nRetro = 0; }
        }
        if (_nRetro >= 20) {
            if (!contromano) {
                contromano = true;
                Avvisi.perso();
            }
        } else {
            contromano = false;
        }

        // la mappa gira piano verso la direzione del percorso
        if (!perso) {
            var d = _direzionePercorso() - orient;
            while (d > Math.PI) { d -= 2 * Math.PI; }
            while (d < -Math.PI) { d += 2 * Math.PI; }
            if (d > 0.35) { d = 0.35; } else if (d < -0.35) { d = -0.35; }
            orient += d;
        }

        _aggiornaBivi();
        if (saltoOra) { _conferma = -1; }
        if (perso || contromano || saltoOra) { return; }

        if (ka >= 0) {
            var liv = (p.bivi[ka] as Array)[1] as Number;
            if (liv >= 2) {
                if (fase < 1 && distBivio <= PREAVVISO) {
                    fase = 1;
                    if (distBivio > ADESSO) { Avvisi.preavviso(); }
                }
                if (fase < 2 && distBivio <= ADESSO) { fase = 2; Avvisi.adesso(); }
            } else if (fase < 1 && distBivio <= LIEVE) {
                fase = 1;
                if (!Imp.soloDecisivi) { Avvisi.lieve(); }
            }
            if (fase > _fasi[ka]) { _fasi[ka] = fase; }
        }
        if (_conferma >= 0 && lungo > p.mBivio(_conferma) + 20.0) {
            var k = _conferma;
            _conferma = -1;
            if (fuori < RIENTRO && _fasi[k] < 3) {
                _fasi[k] = 3;
                giustoFino = ora + 4000;
                Avvisi.giusto();
            }
        }

        // tappe: quelle saltate non si annunciano
        var nw = p.wps.size();
        while (_kw < nw - 1 && lungo > _mTappa(_kw) + 60.0) { _kw++; }
        if (_kw < nw && lungo >= _mTappa(_kw) - TAPPA) {
            var w = p.wps[_kw] as Array;
            msgTappa = w[1] as String;
            msgTappa2 = w[2] as String;
            msgFino = ora + 9000;
            _kw++;
            if (_kw >= nw) { arrivato = true; }
            Avvisi.tappa();
        }
    }

    // true se il prossimo bivio da segnalare è abbastanza vicino da mostrarlo.
    function bivioInVista() as Boolean {
        return ka >= 0 && distBivio <= VISTA;
    }

    // Una distanza in chilometri: "3,7 km".
    private function _km(m as Float) as String {
        var etti = Math.round(m / 100.0).toNumber();
        return (etti / 10).format("%d") + "," + (etti % 10).format("%d") + " km";
    }

    // Metri che mancano alla fine.
    function restano() as Float {
        return p.lung - lungo;
    }

    // Metri di salita che mancano alla fine.
    function salitaRestante() as Number {
        var s = 0;
        for (var i = seg + 1; i < p.n - 1; i++) {
            var d = p.ele[i + 1] - p.ele[i];
            if (d > 0) { s += d; }
        }
        return s;
    }

    // Il nome del sentiero su cui siamo.
    function tratto() as String {
        return p.tratto(seg);
    }

    private function _mTappa(k as Number) as Float {
        return p.cum[(p.wps[k] as Array)[0] as Number];
    }

    // Trova il tratto del percorso più vicino e aggiorna seg, lungo, fuori, nx, ny.
    private function _aggancia(inMoto as Boolean) as Void {
        var ultimo = p.n - 2;
        var da = seg;
        var a = seg;
        while (da > 0 && lungo - p.cum[da] < 40.0) { da--; }
        while (a < ultimo && p.cum[a + 1] - lungo < 150.0) { a++; }
        _cerca(da, a, false);
        _passi++;
        var j = _bj;
        var t = _bt;
        var d2 = _bd2;
        if (d2 > LARGO * LARGO && (!agganciato || _passi % 5 == 0)) {
            // non siamo più vicino a dove eravamo: forse abbiamo tagliato o saltato un
            // pezzo. Se anche il resto del percorso è lontano, vale il tratto di prima.
            _cerca(0, ultimo, false);
            if (_bd2 > FUORI * FUORI && Math.sqrt(d2) - Math.sqrt(_bd2) < 20.0) { _bj = j; _bt = t; _bd2 = d2; }
        }

        // andata e ritorno sullo stesso sentiero: se camminiamo da un po' contro il
        // verso del tratto, forse siamo sull'altro passaggio
        if (inMoto && _bd2 < 400.0 && _contrario(_bj)) { _nContro++; } else { _nContro = 0; }
        if (_fermoVerso > 0) { _fermoVerso--; }
        if (_nContro >= 8 && _fermoVerso == 0) {
            _nContro = 0;
            j = _bj;
            t = _bt;
            d2 = _bd2;
            _cerca(0, ultimo, true);
            if (_bd2 > 100.0 && _bd2 > d2) { _bj = j; _bt = t; _bd2 = d2; } else { _fermoVerso = 60; }
        }

        seg = _bj;
        lungo = p.cum[seg] + _bt * (p.cum[seg + 1] - p.cum[seg]);
        fuori = Math.sqrt(_bd2).toFloat();
        var xy = p.xy;
        nx = xy[2 * seg] + _bt * (xy[2 * seg + 2] - xy[2 * seg]);
        ny = xy[2 * seg + 1] + _bt * (xy[2 * seg + 3] - xy[2 * seg + 1]);
    }

    // Il tratto più vicino alla posizione fra da e a: mette in _bj il tratto, in _bt
    // la frazione lungo il tratto e in _bd2 la distanza al quadrato.
    // Fra due tratti a distanza simile vince quello che, lungo il percorso, è più
    // vicino a dove eravamo: così nei tornanti e sull'andata e ritorno la posizione
    // non salta da un passaggio all'altro. Un tratto che va nel verso opposto a
    // quello di marcia conta come se fosse lontano il doppio; con soloVerso non si
    // guarda affatto.
    private function _cerca(da as Number, a as Number, soloVerso as Boolean) as Void {
        var xy = p.xy;
        var best = 999999999.0;     // la distanza al quadrato del migliore
        var bestE = 999999999.0;    // la stessa, per il confronto: almeno 25 (5 m)
        var bestL = 0.0;            // quanto dista, lungo il percorso, da dove eravamo
        var bj = da;
        var bt = 0.0;
        for (var j = da; j <= a; j++) {
            var ax = xy[2 * j];
            var ay = xy[2 * j + 1];
            var dx = xy[2 * j + 2] - ax;
            var dy = xy[2 * j + 3] - ay;
            var l2 = dx * dx + dy * dy;
            var contro = _inMoto && dx * _ds + dy * _dc < -0.5 * Math.sqrt(l2);
            if (soloVerso && contro) { continue; }
            var t = 0.0;
            if (l2 > 0) {
                t = ((px - ax) * dx + (py - ay) * dy) / l2;
                if (t < 0.0) { t = 0.0; } else if (t > 1.0) { t = 1.0; }
            }
            var ex = ax + t * dx - px;
            var ey = ay + t * dy - py;
            var d2 = ex * ex + ey * ey;
            var e = d2 < 25.0 ? 25.0 : d2;
            if (contro) { e = e * 4; }
            var l = p.cum[j] + t * (p.cum[j + 1] - p.cum[j]) - lungo;
            if (l < 0.0) { l = -l; }
            if (e < bestE * 0.75 || (e < bestE * 1.33 && l < bestL)) {
                best = d2; bestE = e; bestL = l; bj = j; bt = t;
            }
        }
        _bj = bj;
        _bt = bt;
        _bd2 = best;
    }

    // true se il tratto j va in direzione opposta a quella di marcia.
    private function _contrario(j as Number) as Boolean {
        var xy = p.xy;
        var dx = xy[2 * j + 2] - xy[2 * j];
        var dy = xy[2 * j + 3] - xy[2 * j + 1];
        return dx * _ds + dy * _dc < -0.5 * Math.sqrt(dx * dx + dy * dy);
    }

    // Il punto del percorso a s metri dall'inizio, in _qx e _qy.
    private function _puntoA(s as Float) as Void {
        var j = seg;
        if (s >= p.cum[j]) {
            while (j < p.n - 2 && p.cum[j + 1] < s) { j++; }
        } else {
            while (j > 0 && p.cum[j] > s) { j--; }
        }
        var l = p.cum[j + 1] - p.cum[j];
        var t = l > 0.0 ? (s - p.cum[j]) / l : 0.0;
        if (t < 0.0) { t = 0.0; } else if (t > 1.0) { t = 1.0; }
        var xy = p.xy;
        _qx = xy[2 * j] + t * (xy[2 * j + 2] - xy[2 * j]);
        _qy = xy[2 * j + 1] + t * (xy[2 * j + 3] - xy[2 * j + 1]);
    }

    // La direzione del percorso intorno a dove siamo, in radianti da nord.
    private function _direzionePercorso() as Float {
        _puntoA(lungo - 8.0);
        var ax = _qx;
        var ay = _qy;
        _puntoA(lungo + 30.0);
        if (_qx == ax && _qy == ay) { return orient; }
        return Math.atan2(_qx - ax, _qy - ay).toFloat();
    }

    // La direzione del percorso subito dopo il bivio k, in radianti da nord.
    function uscita(k as Number) as Float {
        var m = p.mBivio(k);
        _puntoA(m + 12.0);
        var ax = _qx;
        var ay = _qy;
        _puntoA(m + 30.0);
        return Math.atan2(_qx - ax, _qy - ay).toFloat();
    }

    // Il punto del percorso metri dopo il bivio k: [x, y].
    function dopoBivio(k as Number, metri as Float) as Array<Float> {
        _puntoA(p.mBivio(k) + metri);
        return [_qx, _qy];
    }

    // Aggiorna il prossimo bivio e la distanza che manca.
    private function _aggiornaBivi() as Void {
        var nb = p.bivi.size();
        while (_kb > 0 && lungo <= p.mBivio(_kb - 1) + 8.0) { _kb--; }
        while (_kb < nb && lungo > p.mBivio(_kb) + 8.0) {
            var liv = (p.bivi[_kb] as Array)[1] as Number;
            if (liv >= 1) { _passato = _kb; }
            if (liv >= 2 && !perso) { _conferma = _kb; }
            _kb++;
        }
        var k = _kb;
        while (k < nb && ((p.bivi[k] as Array)[1] as Number) < 1) { k++; }
        if (k >= nb) { k = -1; }
        distBivio = k >= 0 ? p.mBivio(k) - lungo : 0.0;
        // lontani dal bivio: se ci si ripassa, avvisa di nuovo
        if (k >= 0 && distBivio > 150.0) { _fasi[k] = 0; }
        if (k != ka) {
            ka = k;
            fase = k >= 0 ? (_fasi[k] > 2 ? 2 : _fasi[k]) : 0;
        }
        var dopo = _passato >= 0 ? lungo - p.mBivio(_passato) : 1000.0;
        vicino = (ka >= 0 && distBivio <= VISTA) || (dopo >= 0.0 && dopo < 25.0);
    }

    // true se siamo più vicini a un ramo sbagliato di un bivio qui intorno che al
    // percorso, e ci stiamo camminando sopra allontanandoci dal bivio.
    private function _suUnRamo() as Boolean {
        var nb = p.bivi.size();
        for (var k = _kb - 2; k <= _kb; k++) {
            if (k >= 0 && k < nb && _vicinoAiRami(k)) { return true; }
        }
        return false;
    }

    private function _vicinoAiRami(k as Number) as Boolean {
        var b = p.bivi[k] as Array;
        var i = b[0] as Number;
        var jx = p.xy[2 * i];
        var jy = p.xy[2 * i + 1];
        var ddx = px - jx;
        var ddy = py - jy;
        if (ddx > 80.0 || ddx < -80.0 || ddy > 80.0 || ddy < -80.0) { return false; }
        var limite = fuori - 8.0;   // più vicini al ramo che al percorso, con un margine
        var r = b[5] as Array<Number>;
        var q = 0;
        while (q + 1 < r.size()) {
            var np = r[q + 1];
            for (var m = 0; m < np - 1; m++) {
                var ax = jx + r[q + 2 + 2 * m];
                var ay = jy + r[q + 3 + 2 * m];
                var dx = jx + r[q + 4 + 2 * m] - ax;
                var dy = jy + r[q + 5 + 2 * m] - ay;
                var l2 = dx * dx + dy * dy;
                var t = 0.0;
                if (l2 > 0) {
                    t = ((px - ax) * dx + (py - ay) * dy) / l2;
                    if (t < 0.0) { t = 0.0; } else if (t > 1.0) { t = 1.0; }
                }
                var ex = ax + t * dx - px;
                var ey = ay + t * dy - py;
                // vicini al ramo e in cammino nel suo verso
                if (Math.sqrt(ex * ex + ey * ey) < limite && dx * _ds + dy * _dc > 0.5 * Math.sqrt(l2)) { return true; }
            }
            q += 2 + 2 * np;
        }
        return false;
    }
}
