import Toybox.Application;
import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Le tessere di mappa: immagini di 256 pixel di lato che l'orologio scarica dal
// telefono e conserva in Application.Storage, per usarle anche senza telefono.
//
// "Scarica mappe" prende in blocco quelle lungo un percorso. Durante la
// camminata, se il telefono è collegato, quelle che mancano si scaricano una
// alla volta mentre servono (al più EXTRA, poi le più vecchie si cancellano).
//
// Chiavi in Application.Storage:
//   t<fonte>/<colonna>/<riga>   una tessera
//   td:<fonte>:<id>             quante tessere del percorso <id> sono già scaricate
//   tx                          le chiavi delle tessere scaricate durante le camminate
class Tessere {

    const IN_MEMORIA = 8;       // tessere tenute pronte per il disegno
    const EXTRA = 30;           // tessere scaricate al volo da conservare
    const RIPROVA = 60;         // secondi prima di richiedere una tessera non arrivata

    // per la schermata d'attesa dello scarico in blocco
    var titolo as String = "";
    var stato as String = "";
    var finito as Boolean = true;

    private var _mem as Dictionary<String, Graphics.BitmapType> = {} as Dictionary<String, Graphics.BitmapType>;
    private var _uso as Array<String> = [] as Array<String>;    // chiavi in memoria, dalla meno usata
    private var _manca as Dictionary<String, Number> = {} as Dictionary<String, Number>;    // chiave => secondo dell'ultima richiesta, 0 mai chiesta
    private var _letta as Boolean = false;      // in questo disegno si è già letta una tessera dall'archivio

    // la richiesta in corso (una alla volta)
    private var _chiave as String? = null;
    private var _inBlocco as Boolean = false;

    // lo scarico in blocco
    private var _coda as Array<Number> = [] as Array<Number>;   // colonna e riga di ogni tessera
    private var _fonte as Number = 0;
    private var _zoom as Number = 0;
    private var _fatte as Number = 0;
    private var _prove as Number = 0;
    private var _segno as String = "";

    function initialize() {
    }

    function chiave(fonte as Number, col as Number, riga as Number) as String {
        return "t" + fonte + "/" + col + "/" + riga;
    }

    // Da chiamare all'inizio di ogni disegno.
    function inizioDisegno() as Void {
        _letta = false;
    }

    // La tessera, se c'è; altrimenti null, e se si può la chiede al telefono.
    function prendi(fonte as Number, zoom as Number, col as Number, riga as Number) as Graphics.BitmapType? {
        var k = chiave(fonte, col, riga);
        var b = _mem[k];
        if (b != null) {
            if (_uso.size() > 0 && !k.equals(_uso[_uso.size() - 1])) {
                _uso.remove(k);
                _uso.add(k);
            }
            return b;
        }
        var chiesta = _manca[k];
        if (chiesta == null) {
            // la lettura è lenta: una per disegno
            if (_letta) { return null; }
            _letta = true;
            var v = Application.Storage.getValue(k);
            if (v != null) {
                _ricorda(k, v as Graphics.BitmapType);
                return v as Graphics.BitmapType;
            }
            if (_manca.size() > 60) { _manca = {} as Dictionary<String, Number>; }
            _manca[k] = 0;
            chiesta = 0;
        }
        var ora = System.getTimer() / 1000;
        if (_chiave == null && (chiesta == 0 || ora - chiesta > RIPROVA) && System.getDeviceSettings().phoneConnected) {
            _manca[k] = ora + 1;
            _chiedi(k, fonte, zoom, col, riga, false);
        }
        return null;
    }

    // Quante tessere del percorso sono già scaricate, per la fonte data.
    function scaricate(p as Percorso, fonte as Number) as Number {
        var v = Application.Storage.getValue("td:" + fonte + ":" + p.id);
        return v instanceof Number ? v : 0;
    }

    // Quante tessere ha il percorso.
    function totale(p as Percorso) as Number {
        var m = p.map;
        if (m == null) { return 0; }
        return (m["l"] as Array).size() / 2;
    }

    // Per il menu: quante tessere dello sfondo scelto sono già sull'orologio.
    function statoMappe(p as Percorso) as String {
        if (Imp.mappa == Imp.MAPPA_NESSUNA) { return "scegli prima lo sfondo"; }
        var n = totale(p);
        var fatte = scaricate(p, Imp.mappa);
        if (fatte >= n) { return Imp.nomeMappa() + ": già scaricata"; }
        return Imp.nomeMappa() + ": " + fatte.format("%d") + " di " + n.format("%d");
    }

    // Scarica in blocco le tessere del percorso che mancano.
    function scaricaPercorso(p as Percorso, fonte as Number) as Void {
        var m = p.map;
        if (m == null || fonte == Imp.MAPPA_NESSUNA) { return; }
        Communications.cancelAllRequests();
        _chiave = null;
        var l = m["l"] as Array<Number>;
        var x0 = m["x"] as Number;
        var y0 = m["y"] as Number;
        _coda = [] as Array<Number>;
        for (var i = 0; i + 1 < l.size(); i += 2) {
            _coda.add(x0 + l[i]);
            _coda.add(y0 + l[i + 1]);
        }
        _fonte = fonte;
        _zoom = m["z"] as Number;
        _segno = "td:" + fonte + ":" + p.id;
        _fatte = scaricate(p, fonte);
        _prove = 0;
        titolo = fonte == Imp.MAPPA_SATELLITE ? "Mappa satellitare" : "Mappa topografica";
        finito = false;
        _prossima();
    }

    // Ferma lo scarico in blocco; quello già scaricato resta.
    function annulla() as Void {
        if (!finito) {
            Communications.cancelAllRequests();
            _chiave = null;
            finito = true;
        }
    }

    // Cancella le tessere del percorso, di tutte le fonti.
    function elimina(p as Percorso) as Void {
        var m = p.map;
        if (m == null) { return; }
        var l = m["l"] as Array<Number>;
        var x0 = m["x"] as Number;
        var y0 = m["y"] as Number;
        for (var fonte = Imp.MAPPA_SATELLITE; fonte <= Imp.MAPPA_TOPO; fonte++) {
            for (var i = 0; i + 1 < l.size(); i += 2) {
                var k = chiave(fonte, x0 + l[i], y0 + l[i + 1]);
                Application.Storage.deleteValue(k);
                _dimentica(k);
            }
            Application.Storage.deleteValue("td:" + fonte + ":" + p.id);
        }
        _manca = {} as Dictionary<String, Number>;
    }

    private function _prossima() as Void {
        var n = _coda.size() / 2;
        if (_fatte >= n) {
            stato = n.format("%d") + " tessere\npronte";
            finito = true;
            WatchUi.requestUpdate();
            return;
        }
        if (!System.getDeviceSettings().phoneConnected) {
            stato = "Telefono non\ncollegato";
            finito = true;
            WatchUi.requestUpdate();
            return;
        }
        stato = (_fatte + 1).format("%d") + " di " + n.format("%d");
        WatchUi.requestUpdate();
        var col = _coda[2 * _fatte];
        var riga = _coda[2 * _fatte + 1];
        _chiedi(chiave(_fonte, col, riga), _fonte, _zoom, col, riga, true);
    }

    private function _chiedi(k as String, fonte as Number, zoom as Number, col as Number, riga as Number, inBlocco as Boolean) as Void {
        var url;
        var retino;
        if (fonte == Imp.MAPPA_SATELLITE) {
            url = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/" + zoom + "/" + riga + "/" + col;
            retino = Communications.IMAGE_DITHERING_FLOYD_STEINBERG;
        } else {
            url = "https://tile.opentopomap.org/" + zoom + "/" + col + "/" + riga + ".png";
            retino = Communications.IMAGE_DITHERING_NONE;
        }
        _chiave = k;
        _inBlocco = inBlocco;
        Communications.makeImageRequest(url, null, { :maxWidth => 256, :maxHeight => 256, :dithering => retino }, method(:onTessera));
    }

    function onTessera(codice as Number, dati as WatchUi.BitmapResource or Graphics.BitmapReference or Null) as Void {
        var k = _chiave;
        _chiave = null;
        if (k == null) { return; }
        if (!_inBlocco) {
            if (codice == 200 && dati != null) {
                _manca.remove(k);
                _ricorda(k, dati);
                _conserva(k, dati);
                WatchUi.requestUpdate();
            }
            return;
        }
        if (finito) { return; }
        if (codice == 200 && dati != null) {
            try {
                Application.Storage.setValue(k, dati);
            } catch (e) {
                stato = "Memoria piena:\nelimina le mappe\ndi un altro percorso";
                finito = true;
                WatchUi.requestUpdate();
                return;
            }
            _manca.remove(k);
            _togliExtra(k);
            _fatte++;
            _prove = 0;
            Application.Storage.setValue(_segno, _fatte);
            _prossima();
        } else if (_prove < 2) {
            _prove++;
            _prossima();
        } else {
            stato = (codice == Communications.BLE_CONNECTION_UNAVAILABLE ? "Telefono non\ncollegato" : "Errore " + codice.format("%d")) + "\nfatte " + _fatte.format("%d") + " di " + (_coda.size() / 2).format("%d");
            finito = true;
            WatchUi.requestUpdate();
        }
    }

    // Tiene la tessera in memoria per il disegno, togliendo la meno usata.
    private function _ricorda(k as String, b as Graphics.BitmapType) as Void {
        if (_uso.size() >= IN_MEMORIA) {
            _mem.remove(_uso[0]);
            _uso.remove(_uso[0]);
        }
        _mem[k] = b;
        _uso.add(k);
    }

    private function _dimentica(k as String) as Void {
        if (_mem.hasKey(k)) {
            _mem.remove(k);
            _uso.remove(k);
        }
    }

    // Salva una tessera scaricata al volo e cancella le più vecchie.
    private function _conserva(k as String, b as WatchUi.BitmapResource or Graphics.BitmapReference) as Void {
        var v = Application.Storage.getValue("tx");
        var extra = v instanceof Array ? v as Array<String> : [] as Array<String>;
        try {
            while (extra.size() >= EXTRA) {
                Application.Storage.deleteValue(extra[0]);
                extra.remove(extra[0]);
            }
            Application.Storage.setValue(k, b);
            extra.add(k);
            Application.Storage.setValue("tx", extra);
        } catch (e) {
            // memoria piena: la tessera resta solo per questa camminata
        }
    }

    // Una tessera scaricata in blocco non va più cancellata con quelle al volo.
    private function _togliExtra(k as String) as Void {
        var v = Application.Storage.getValue("tx");
        if (v instanceof Array && v.indexOf(k) >= 0) {
            v.remove(k);
            Application.Storage.setValue("tx", v as Array<String>);
        }
    }
}
