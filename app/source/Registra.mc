import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Lang;
import Toybox.Sensor;

// La registrazione dell'attività, come Escursionismo: l'orologio salva traccia
// GPS, battito, quota e dislivello, passi, temperatura e calorie in un file FIT
// che finisce in Garmin Connect come le altre attività.
module Registra {

    const FERMA = 0;
    const ATTIVA = 1;
    const PAUSA = 2;

    var stato as Number = FERMA;
    var _sessione as ActivityRecording.Session? = null;

    function avvia(nome as String) as Void {
        if (stato != FERMA) { return; }
        Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE, Sensor.SENSOR_FOOTPOD, Sensor.SENSOR_TEMPERATURE] as Array<Sensor.SensorType>);
        if (nome.length() > 15) { nome = nome.substring(0, 15) as String; }
        var s = ActivityRecording.createSession({
            :name => nome,
            :sport => Activity.SPORT_HIKING,
            :subSport => Activity.SUB_SPORT_GENERIC
        });
        _sessione = s;
        if (s.start()) { stato = ATTIVA; }
    }

    function pausa() as Void {
        var s = _sessione;
        if (stato == ATTIVA && s != null) {
            s.stop();
            stato = PAUSA;
        }
    }

    function riprendi() as Void {
        var s = _sessione;
        if (stato == PAUSA && s != null) {
            s.start();
            stato = ATTIVA;
        }
    }

    function salva() as Void {
        var s = _sessione;
        if (s != null) {
            if (s.isRecording()) { s.stop(); }
            s.save();
        }
        _sessione = null;
        stato = FERMA;
    }

    function scarta() as Void {
        var s = _sessione;
        if (s != null) {
            if (s.isRecording()) { s.stop(); }
            s.discard();
        }
        _sessione = null;
        stato = FERMA;
    }
}
