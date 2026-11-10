import Toybox.Communications;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

// "Aggiorna percorsi": scarica dal sito l'elenco e poi, uno alla volta, i
// percorsi nuovi o cambiati (quelli con l'impronta h diversa). I percorsi che
// sul sito non ci sono più si cancellano dall'orologio.
class Aggiorna {

    const SITO = "https://pietroni1.github.io/trekking-percorsi/v2/";

    // per la schermata d'attesa
    var titolo as String = "Aggiorna percorsi";
    var stato as String = "Scarico l'elenco";
    var finito as Boolean = false;

    private var _daFare as Array<Dictionary> = [] as Array<Dictionary>;
    private var _fatti as Number = 0;

    function initialize() {
    }

    function avvia() as Void {
        Communications.makeWebRequest(SITO + "index.json", { "t" => Time.now().value() }, _opzioni(), method(:onElenco));
    }

    function annulla() as Void {
        if (!finito) {
            Communications.cancelAllRequests();
            finito = true;
        }
    }

    private function _opzioni() as Dictionary {
        return { :method => Communications.HTTP_REQUEST_METHOD_GET, :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON };
    }

    function onElenco(codice as Number, dati as Dictionary or String or Null) as Void {
        if (finito) { return; }
        if (codice != 200 || !(dati instanceof Dictionary) || !(dati["routes"] instanceof Array)) {
            _errore(codice);
            return;
        }
        var nuovi = dati["routes"] as Array<Dictionary>;
        var vecchi = Archivio.elenco();
        var tenuti = [] as Array<Dictionary>;
        for (var i = 0; i < vecchi.size(); i++) {
            var v = vecchi[i];
            var c = _trova(nuovi, v["id"] as String);
            if (c == null) {
                Archivio.elimina(v["id"] as String);
            } else if ((c["h"] as String).equals(v["h"] as String)) {
                // invariato: restano nome e descrizione nuovi, che non cambiano l'impronta
                tenuti.add({ "id" => c["id"], "name" => c["name"], "sub" => c["sub"], "h" => c["h"] });
            } else {
                tenuti.add(v);
            }
        }
        Archivio.salvaElenco(tenuti);
        for (var i = 0; i < nuovi.size(); i++) {
            var c = nuovi[i];
            var v = _trova(vecchi, c["id"] as String);
            if (v == null || !(c["h"] as String).equals(v["h"] as String)) { _daFare.add(c); }
        }
        _prossimo();
    }

    private function _trova(elenco as Array<Dictionary>, id as String) as Dictionary? {
        for (var i = 0; i < elenco.size(); i++) {
            if (id.equals(elenco[i]["id"] as String)) { return elenco[i]; }
        }
        return null;
    }

    private function _prossimo() as Void {
        if (_fatti >= _daFare.size()) {
            stato = _fatti == 0 ? "Già aggiornati" : (_fatti == 1 ? "1 percorso\naggiornato" : _fatti.format("%d") + " percorsi\naggiornati");
            finito = true;
            Elenco.riempi();
            WatchUi.requestUpdate();
            return;
        }
        var c = _daFare[_fatti];
        stato = (c["name"] as String) + "\n" + (_fatti + 1).format("%d") + " di " + _daFare.size().format("%d");
        WatchUi.requestUpdate();
        Communications.makeWebRequest(SITO + (c["file"] as String), { "h" => c["h"] }, _opzioni(), method(:onPercorso));
    }

    function onPercorso(codice as Number, dati as Dictionary or String or Null) as Void {
        if (finito) { return; }
        if (codice != 200 || !(dati instanceof Dictionary) || !(dati["xy"] instanceof Array)) {
            _errore(codice);
            return;
        }
        var c = _daFare[_fatti];
        var id = c["id"] as String;
        try {
            Archivio.salva(id, dati);
        } catch (e) {
            stato = "Memoria piena";
            finito = true;
            Elenco.riempi();
            WatchUi.requestUpdate();
            return;
        }
        // l'elenco si aggiorna a ogni percorso: se lo scarico si interrompe, quelli fatti restano
        var elenco = Archivio.elenco();
        var voce = { "id" => id, "name" => c["name"], "sub" => c["sub"], "h" => c["h"] };
        var messo = false;
        for (var i = 0; i < elenco.size(); i++) {
            if (id.equals(elenco[i]["id"] as String)) { elenco[i] = voce; messo = true; }
        }
        if (!messo) { elenco.add(voce); }
        Archivio.salvaElenco(elenco);
        _fatti++;
        _prossimo();
    }

    private function _errore(codice as Number) as Void {
        if (codice == Communications.BLE_CONNECTION_UNAVAILABLE) {
            stato = "Telefono non\ncollegato";
        } else if (codice == Communications.NETWORK_RESPONSE_TOO_LARGE) {
            stato = "Percorso troppo\ngrande";
        } else {
            stato = "Errore " + codice.format("%d");
        }
        finito = true;
        Elenco.riempi();
        WatchUi.requestUpdate();
    }
}
