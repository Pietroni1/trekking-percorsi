import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// La schermata d'attesa mostra un lavoro lungo: Aggiorna (i percorsi) o Tessere
// (le mappe). Di tutti e due legge titolo, stato e finito, e con BACK chiama
// annulla().

// Titolo, a che punto è il lavoro e come uscire.
class AttesaView extends WatchUi.View {

    private var _lavoro;

    function initialize(lavoro) {
        View.initialize();
        _lavoro = lavoro;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.16, Graphics.FONT_XTINY, _lavoro.titolo, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2, Graphics.FONT_SMALL, _lavoro.stato, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(0xAAAAAA, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h * 0.80, Graphics.FONT_XTINY, _lavoro.finito ? "BACK per tornare" : "BACK per fermare", Graphics.TEXT_JUSTIFY_CENTER);
    }
}

// BACK ferma il lavoro, se non è finito, e torna indietro.
class AttesaDelegate extends WatchUi.BehaviorDelegate {

    private var _lavoro;

    function initialize(lavoro) {
        BehaviorDelegate.initialize();
        _lavoro = lavoro;
    }

    function onBack() as Boolean {
        _lavoro.annulla();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
