import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// L'elenco dei percorsi: la prima cosa che si vede aprendo l'app.
module Elenco {

    var menu as WatchUi.Menu2? = null;

    function crea() as WatchUi.Menu2 {
        var m = new WatchUi.Menu2({ :title => "Percorsi" });
        menu = m;
        riempi();
        return m;
    }

    // Rifà le voci: i percorsi salvati e, in fondo, "Aggiorna percorsi".
    function riempi() as Void {
        var m = menu;
        if (m == null) { return; }
        while (m.getItem(0) != null) { m.deleteItem(0); }
        var e = Archivio.elenco();
        for (var i = 0; i < e.size(); i++) {
            m.addItem(new WatchUi.MenuItem(e[i]["name"] as String, e[i]["sub"] as String, e[i]["id"] as String, null));
        }
        m.addItem(new WatchUi.MenuItem("Aggiorna percorsi", e.size() == 0 ? "per cominciare" : "dal telefono", :aggiorna, null));
    }
}

class ElencoDelegate extends WatchUi.Menu2InputDelegate {

    private var _tessere as Tessere;

    function initialize(tessere as Tessere) {
        Menu2InputDelegate.initialize();
        _tessere = tessere;
    }

    function onSelect(voce as WatchUi.MenuItem) as Void {
        var id = voce.getId();
        if (id instanceof String) {
            var p = Archivio.carica(id);
            if (p == null) {
                voce.setSubLabel("da riscaricare: Aggiorna");
                WatchUi.requestUpdate();
                return;
            }
            var guida = new Guida(p);
            var vista = new NavView(guida, _tessere);
            vista.apri();
            WatchUi.pushView(vista, new NavDelegate(vista, guida, _tessere), WatchUi.SLIDE_LEFT);
        } else {
            var lavoro = new Aggiorna();
            lavoro.avvia();
            WatchUi.pushView(new AttesaView(lavoro), new AttesaDelegate(lavoro), WatchUi.SLIDE_LEFT);
        }
    }
}

// La schermata sotto l'elenco: apre l'elenco e, quando ci si torna con BACK,
// chiude l'app.
class BaseView extends WatchUi.View {

    private var _tessere as Tessere;
    private var _aperto as Boolean = false;

    function initialize(tessere as Tessere) {
        View.initialize();
        _tessere = tessere;
    }

    function onShow() as Void {
        if (!_aperto) {
            _aperto = true;
            WatchUi.pushView(Elenco.crea(), new ElencoDelegate(_tessere), WatchUi.SLIDE_IMMEDIATE);
        } else {
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
    }
}
