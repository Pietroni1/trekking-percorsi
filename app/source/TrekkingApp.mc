import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.WatchUi;

// Trekking 2: guida lungo i percorsi di https://pietroni1.github.io/trekking-percorsi/
// con avvisi a ogni bivio e registra l'attività come Escursionismo.
class TrekkingApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        Imp.leggi();
    }

    // Se l'app si chiude con un'attività in corso, la salva: non si perde niente.
    function onStop(state as Dictionary?) as Void {
        if (Registra.stato != Registra.FERMA) { Registra.salva(); }
        Position.enableLocationEvents(Position.LOCATION_DISABLE, null);
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new BaseView(new Tessere())];
    }
}
