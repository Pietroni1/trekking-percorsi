import Toybox.Lang;
import Toybox.WatchUi;

// I tasti durante la camminata:
//   START     avvia la registrazione; poi la mette in pausa e apre Riprendi / Salva / Scarta
//   SU, GIÙ   cambiano pagina: mappa, dati, profilo
//   BACK      prima di partire torna all'elenco; in cammino passa dalla mappa
//             vicina a tutto il percorso e viceversa
//   MENU      (SU tenuto premuto) le impostazioni della mappa
// Lo schermo tattile non fa nulla, così non si mette in pausa per sbaglio.
class NavDelegate extends WatchUi.BehaviorDelegate {

    private var _vista as NavView;
    private var _guida as Guida;
    private var _tessere as Tessere;

    function initialize(vista as NavView, guida as Guida, tessere as Tessere) {
        BehaviorDelegate.initialize();
        _vista = vista;
        _guida = guida;
        _tessere = tessere;
    }

    function onKey(evento as WatchUi.KeyEvent) as Boolean {
        if (evento.getKey() != WatchUi.KEY_ENTER) { return false; }
        if (Registra.stato == Registra.FERMA) {
            Registra.avvia(_guida.p.nome);
            Avvisi.tasto(true);
        } else {
            Registra.pausa();
            Avvisi.tasto(false);
            var menu = new WatchUi.Menu2({ :title => "In pausa" });
            menu.addItem(new WatchUi.MenuItem("Riprendi", null, :riprendi, null));
            menu.addItem(new WatchUi.MenuItem("Salva", "e torna all'elenco", :salva, null));
            menu.addItem(new WatchUi.MenuItem("Scarta", null, :scarta, null));
            WatchUi.pushView(menu, new PausaDelegate(_vista), WatchUi.SLIDE_UP);
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onTap(evento as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    function onSwipe(evento as WatchUi.SwipeEvent) as Boolean {
        return true;
    }

    function onNextPage() as Boolean {
        _vista.cambiaPagina(1);
        return true;
    }

    function onPreviousPage() as Boolean {
        _vista.cambiaPagina(-1);
        return true;
    }

    function onBack() as Boolean {
        if (_vista.pagina != 0) {
            _vista.pagina = 0;
        } else if (Registra.stato == Registra.FERMA && !_vista.tutto) {
            _vista.chiudi();
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            return true;
        } else {
            _vista.tutto = !_vista.tutto;
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onMenu() as Boolean {
        var p = _guida.p;
        var menu = new WatchUi.Menu2({ :title => "Mappa" });
        menu.addItem(new WatchUi.MenuItem("Sfondo", Imp.nomeMappa(), :sfondo, null));
        menu.addItem(new WatchUi.MenuItem("Vista", _vista.tutto ? "Tutto il percorso" : "Vicina", :vista, null));
        menu.addItem(new WatchUi.MenuItem("In alto", Imp.nord ? "Il nord" : "Il percorso", :alto, null));
        menu.addItem(new WatchUi.MenuItem("Avvisi ai bivi", Imp.soloDecisivi ? "Solo i decisivi" : "Tutti", :avvisi, null));
        menu.addItem(new WatchUi.MenuItem("Scarica mappe", _tessere.statoMappe(p), :scarica, null));
        menu.addItem(new WatchUi.MenuItem("Elimina mappe", "di questo percorso", :elimina, null));
        WatchUi.pushView(menu, new MappaDelegate(_vista, p, _tessere), WatchUi.SLIDE_UP);
        return true;
    }
}

// Il menu della pausa.
class PausaDelegate extends WatchUi.Menu2InputDelegate {

    private var _vista as NavView;

    function initialize(vista as NavView) {
        Menu2InputDelegate.initialize();
        _vista = vista;
    }

    function onSelect(voce as WatchUi.MenuItem) as Void {
        var id = voce.getId();
        if (id == :riprendi) {
            onBack();
        } else if (id == :salva) {
            Registra.salva();
            _esci();
        } else if (id == :scarta) {
            var menu = new WatchUi.Menu2({ :title => "Scartare?" });
            menu.addItem(new WatchUi.MenuItem("No", "torna indietro", :no, null));
            menu.addItem(new WatchUi.MenuItem("Sì, scarta", "l'attività si perde", :si, null));
            WatchUi.pushView(menu, new ScartaDelegate(_vista), WatchUi.SLIDE_UP);
        }
    }

    function onBack() as Void {
        Registra.riprendi();
        Avvisi.tasto(true);
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    // Chiude il menu e la camminata: si torna all'elenco dei percorsi.
    private function _esci() as Void {
        _vista.chiudi();
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

// La conferma prima di scartare l'attività.
class ScartaDelegate extends WatchUi.Menu2InputDelegate {

    private var _vista as NavView;

    function initialize(vista as NavView) {
        Menu2InputDelegate.initialize();
        _vista = vista;
    }

    function onSelect(voce as WatchUi.MenuItem) as Void {
        if (voce.getId() == :si) {
            Registra.scarta();
            _vista.chiudi();
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        } else {
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        }
    }
}

// Il menu della mappa: ogni voce cambia valore a ogni pressione.
class MappaDelegate extends WatchUi.Menu2InputDelegate {

    private var _vista as NavView;
    private var _p as Percorso;
    private var _tessere as Tessere;

    function initialize(vista as NavView, p as Percorso, tessere as Tessere) {
        Menu2InputDelegate.initialize();
        _vista = vista;
        _p = p;
        _tessere = tessere;
    }

    function onSelect(voce as WatchUi.MenuItem) as Void {
        var id = voce.getId();
        if (id == :sfondo) {
            Imp.mappa = (Imp.mappa + 1) % 3;
            voce.setSubLabel(Imp.nomeMappa());
        } else if (id == :vista) {
            _vista.tutto = !_vista.tutto;
            voce.setSubLabel(_vista.tutto ? "Tutto il percorso" : "Vicina");
        } else if (id == :alto) {
            Imp.nord = !Imp.nord;
            voce.setSubLabel(Imp.nord ? "Il nord" : "Il percorso");
        } else if (id == :avvisi) {
            Imp.soloDecisivi = !Imp.soloDecisivi;
            voce.setSubLabel(Imp.soloDecisivi ? "Solo i decisivi" : "Tutti");
        } else if (id == :scarica) {
            if (Imp.mappa == Imp.MAPPA_NESSUNA) {
                voce.setSubLabel("scegli prima lo sfondo");
            } else {
                _tessere.scaricaPercorso(_p, Imp.mappa);
                WatchUi.pushView(new AttesaView(_tessere), new AttesaDelegate(_tessere), WatchUi.SLIDE_LEFT);
                return;
            }
        } else if (id == :elimina) {
            _tessere.elimina(_p);
            voce.setSubLabel("eliminate");
        }
        Imp.salva();
        WatchUi.requestUpdate();
    }
}
