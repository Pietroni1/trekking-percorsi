import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;

// Un percorso caricato in memoria, nel formato v2 del sito (vedi tools/route_v2.js).
// Le coordinate sono metri a est (x) e a nord (y) del primo punto.
class Percorso {

    var id as String;
    var nome as String;
    var n as Number;                // quanti punti
    var xy as Array<Number>;        // x0, y0, x1, y1, ...
    var cum as Array<Float>;        // metri dall'inizio, per ogni punto
    var ele as Array<Number>;       // quota di ogni punto
    var lung as Float;              // lunghezza in metri
    var wps as Array;               // tappe: [punto, nome, indicazione]
    var tratti as Array;            // [punto da cui vale, nome del sentiero]
    var bivi as Array;              // [punto, livello, arrivo, uscita, indicazione, rami]
    var map as Dictionary?;         // le tessere di mappa
    private var _lat0 as Double;
    private var _lon0 as Double;
    private var _kx as Float;
    private var _ky as Float;

    function initialize(ident as String, meta as Dictionary, punti as Array<Number>, quote as Array<Number>, incroci as Array) {
        id = ident;
        nome = meta["name"] as String;
        xy = punti;
        ele = quote;
        n = punti.size() / 2;
        wps = meta["wps"] as Array;
        tratti = meta["tratti"] as Array;
        bivi = incroci;
        map = meta["map"] as Dictionary?;
        var o = meta["o"] as Array<Number>;
        var k = meta["k"] as Array<Numeric>;
        _lat0 = o[0].toDouble() / 1000000.0d;
        _lon0 = o[1].toDouble() / 1000000.0d;
        _kx = k[0].toFloat();
        _ky = k[1].toFloat();

        cum = new Array<Float>[n];
        var d = 0.0;
        cum[0] = 0.0;
        for (var i = 1; i < n; i++) {
            var dx = xy[2 * i] - xy[2 * i - 2];
            var dy = xy[2 * i + 1] - xy[2 * i - 1];
            d += Math.sqrt(dx * dx + dy * dy).toFloat();
            cum[i] = d;
        }
        lung = d;
    }

    // Metri a est del primo punto, da una longitudine in gradi.
    function xDi(lon as Double) as Float {
        return ((lon - _lon0) * _kx).toFloat();
    }

    // Metri a nord del primo punto, da una latitudine in gradi.
    function yDi(lat as Double) as Float {
        return ((lat - _lat0) * _ky).toFloat();
    }

    // I metri dall'inizio a cui si trova il bivio k.
    function mBivio(k as Number) as Float {
        return cum[(bivi[k] as Array)[0] as Number];
    }

    // Il nome del sentiero al punto i.
    function tratto(i as Number) as String {
        var nomeTratto = nome;
        for (var k = 0; k < tratti.size(); k++) {
            var t = tratti[k] as Array;
            if ((t[0] as Number) > i) { break; }
            nomeTratto = t[1] as String;
        }
        return nomeTratto;
    }
}

// I percorsi salvati sull'orologio. Ogni valore di Application.Storage può
// occupare al più 32 KB, perciò un percorso sta in più chiavi:
//   idx          l'elenco: [{id, name, sub, h}]
//   r:<id>       nome, origine, tappe, tratti, mappa e numero di pezzi dei bivi
//   x:<id>       i punti
//   e:<id>       le quote
//   b:<id>:<k>   i bivi, a pezzi di BIVI_PER_PEZZO
module Archivio {

    const BIVI_PER_PEZZO = 40;

    function elenco() as Array<Dictionary> {
        var v = Application.Storage.getValue("idx");
        if (v instanceof Array) { return v as Array<Dictionary>; }
        return [] as Array<Dictionary>;
    }

    function salvaElenco(e as Array<Dictionary>) as Void {
        Application.Storage.setValue("idx", e as Array<Application.PropertyValueType>);
    }

    // Salva un percorso appena scaricato (il contenuto di v2/<id>.json).
    function salva(id as String, r as Dictionary) as Void {
        var bivi = r["bivi"] as Array;
        var pezzi = (bivi.size() + BIVI_PER_PEZZO - 1) / BIVI_PER_PEZZO;
        elimina(id);
        Application.Storage.setValue("x:" + id, r["xy"] as Array<Number>);
        Application.Storage.setValue("e:" + id, r["ele"] as Array<Number>);
        for (var k = 0; k < pezzi; k++) {
            var fine = (k + 1) * BIVI_PER_PEZZO;
            if (fine > bivi.size()) { fine = bivi.size(); }
            Application.Storage.setValue("b:" + id + ":" + k, bivi.slice(k * BIVI_PER_PEZZO, fine) as Array<Application.PropertyValueType>);
        }
        Application.Storage.setValue("r:" + id, {
            "name" => r["name"], "o" => r["o"], "k" => r["k"], "wps" => r["wps"],
            "tratti" => r["tratti"], "map" => r["map"], "nb" => pezzi
        } as Dictionary<String, Application.PropertyValueType>);
    }

    function carica(id as String) as Percorso? {
        var meta = Application.Storage.getValue("r:" + id);
        var punti = Application.Storage.getValue("x:" + id);
        var quote = Application.Storage.getValue("e:" + id);
        if (!(meta instanceof Dictionary) || !(punti instanceof Array) || !(quote instanceof Array) || punti.size() < 4) {
            return null;
        }
        var bivi = [] as Array;
        var pezzi = meta["nb"] as Number;
        for (var k = 0; k < pezzi; k++) {
            var pezzo = Application.Storage.getValue("b:" + id + ":" + k);
            if (pezzo instanceof Array) { bivi.addAll(pezzo); }
        }
        return new Percorso(id, meta, punti as Array<Number>, quote as Array<Number>, bivi);
    }

    function elimina(id as String) as Void {
        var meta = Application.Storage.getValue("r:" + id);
        if (meta instanceof Dictionary) {
            var pezzi = meta["nb"] as Number;
            for (var k = 0; k < pezzi; k++) { Application.Storage.deleteValue("b:" + id + ":" + k); }
        }
        Application.Storage.deleteValue("r:" + id);
        Application.Storage.deleteValue("x:" + id);
        Application.Storage.deleteValue("e:" + id);
    }
}
