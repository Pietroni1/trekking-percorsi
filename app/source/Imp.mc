import Toybox.Application;
import Toybox.Lang;

// Le impostazioni, salvate sull'orologio.
module Imp {

    const MAPPA_NESSUNA = 0;
    const MAPPA_SATELLITE = 1;
    const MAPPA_TOPO = 2;

    // lo sfondo della mappa
    var mappa as Number = MAPPA_SATELLITE;
    // true: nord in alto; false: il percorso davanti a te va verso l'alto
    var nord as Boolean = false;
    // true: vibra solo ai bivi decisivi, non a quelli con una semplice via laterale
    var soloDecisivi as Boolean = false;

    function leggi() as Void {
        var v = Application.Storage.getValue("imp");
        if (v instanceof Dictionary) {
            var m = v["m"];
            if (m instanceof Number) { mappa = m; }
            var n = v["n"];
            if (n instanceof Boolean) { nord = n; }
            var d = v["d"];
            if (d instanceof Boolean) { soloDecisivi = d; }
        }
    }

    function salva() as Void {
        Application.Storage.setValue("imp", { "m" => mappa, "n" => nord, "d" => soloDecisivi });
    }

    function nomeMappa() as String {
        if (mappa == MAPPA_SATELLITE) { return "Satellite"; }
        if (mappa == MAPPA_TOPO) { return "Topografica"; }
        return "Solo percorso";
    }
}
