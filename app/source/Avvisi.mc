import Toybox.Attention;
import Toybox.Lang;

// Vibrazioni e suoni. Ogni avviso ha un ritmo diverso, per riconoscerlo senza
// guardare l'orologio; tutti accendono la luce dello schermo.
module Avvisi {

    // Tra poco c'è un bivio decisivo: due colpi.
    function preavviso() as Void {
        _vibra([new Attention.VibeProfile(75, 250), new Attention.VibeProfile(0, 150), new Attention.VibeProfile(75, 250)]);
        _suona(Attention.TONE_ALERT_HI);
    }

    // Il bivio è qui: tre colpi forti.
    function adesso() as Void {
        _vibra([new Attention.VibeProfile(100, 300), new Attention.VibeProfile(0, 120), new Attention.VibeProfile(100, 300),
            new Attention.VibeProfile(0, 120), new Attention.VibeProfile(100, 300)]);
        _suona(Attention.TONE_LOUD_BEEP);
    }

    // Un bivio dove si prosegue: un colpo.
    function lieve() as Void {
        _vibra([new Attention.VibeProfile(50, 200)]);
    }

    // Direzione giusta dopo un bivio, o di nuovo sul percorso: un colpetto.
    function giusto() as Void {
        _vibra([new Attention.VibeProfile(50, 100)]);
        _suona(Attention.TONE_SUCCESS);
    }

    // Fuori percorso: due colpi lunghi.
    function perso() as Void {
        _vibra([new Attention.VibeProfile(100, 900), new Attention.VibeProfile(0, 250), new Attention.VibeProfile(100, 900)]);
        _suona(Attention.TONE_ALARM);
    }

    // Una tappa raggiunta.
    function tappa() as Void {
        _vibra([new Attention.VibeProfile(75, 500)]);
        _suona(Attention.TONE_MSG);
    }

    // Registrazione avviata, in pausa o ripresa.
    function tasto(avvio as Boolean) as Void {
        _vibra([new Attention.VibeProfile(75, 250)]);
        _suona(avvio ? Attention.TONE_START : Attention.TONE_STOP);
    }

    function _vibra(ritmo as Array<Attention.VibeProfile>) as Void {
        if (Attention has :vibrate) { Attention.vibrate(ritmo); }
        if (Attention has :backlight) {
            try { Attention.backlight(true); } catch (e) { }
        }
    }

    function _suona(tono as Attention.Tone) as Void {
        if (Attention has :playTone) { Attention.playTone(tono); }
    }
}
