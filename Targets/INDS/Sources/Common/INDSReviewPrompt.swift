//
//  INDSReviewPrompt.swift
//  eNDS
//
//  Cuándo pedir una valoración sin resultar pesado.
//
//  El botón de Ajustes › Acerca de abre directamente la ficha de reseña,
//  porque ahí el usuario ya vino a eso. Esto es lo contrario: el aviso que
//  aparece sin que nadie lo pida, y por eso usa `SKStoreReviewController`,
//  que iOS limita a unas tres veces al año y puede decidir no enseñar nada.
//  Esa limitación es una función, no un problema: aquí solo se decide si
//  *merece la pena* preguntar.
//
//  Se pide al volver a la biblioteca después de jugar un rato — nunca en
//  mitad de una partida, que es donde molesta y donde se contestan tres
//  estrellas por quitarlo de en medio.
//

import Foundation
import StoreKit
import UIKit

enum INDSReviewPrompt {
    private enum Keys {
        static let sessions = "eNDSReviewSessions"
        static let playTime = "eNDSReviewPlayTime"
        static let lastAsked = "eNDSReviewLastAsked"
    }

    /// Tres días, tres partidas y veinte minutos jugados. Por debajo de eso
    /// nadie tiene una opinión formada de un emulador, y preguntar antes es
    /// como se cosechan las valoraciones de una estrella.
    private static let minDaysInstalled: TimeInterval = 3 * 24 * 3600
    private static let minSessions = 3
    private static let minPlayTime: TimeInterval = 20 * 60
    private static let minSecondsBetweenAsks: TimeInterval = 60 * 24 * 3600

    /// Una sesión que no llega al minuto es abrir y cerrar: no cuenta ni como
    /// partida ni como tiempo jugado.
    private static let minSessionLength: TimeInterval = 60

    static func recordSession(playedFor seconds: TimeInterval) {
        guard seconds >= minSessionLength else { return }
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: Keys.sessions) + 1, forKey: Keys.sessions)
        defaults.set(defaults.double(forKey: Keys.playTime) + seconds, forKey: Keys.playTime)
    }

    /// La decisión, aparte del estado. El fallo temido aquí es el silencioso
    /// —no preguntar nunca— y sin separarlo no hay forma de comprobarlo sin
    /// ensuciar los UserDefaults de verdad.
    static func shouldAsk(sessions: Int, playTime: TimeInterval,
                          installedFor: TimeInterval, sinceLastAsk: TimeInterval?) -> Bool {
        guard sessions >= minSessions,
              playTime >= minPlayTime,
              installedFor >= minDaysInstalled else { return false }
        if let sinceLastAsk, sinceLastAsk < minSecondsBetweenAsks { return false }
        return true
    }

    /// Llamar al volver a la biblioteca. Devuelve sin hacer nada si aún no
    /// toca; no hay señal de vuelta porque iOS tampoco dice si enseñó algo.
    @MainActor
    static func askIfEarned() {
        let defaults = UserDefaults.standard
        guard let firstLaunch = INDSHoneymoon.firstLaunchDate else { return }
        let last = defaults.object(forKey: Keys.lastAsked) as? Date
        guard shouldAsk(sessions: defaults.integer(forKey: Keys.sessions),
                        playTime: defaults.double(forKey: Keys.playTime),
                        installedFor: Date().timeIntervalSince(firstLaunch),
                        sinceLastAsk: last.map { Date().timeIntervalSince($0) }) else { return }

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }

        // Se apunta la fecha aunque iOS decida no enseñar el aviso: no hay
        // forma de saberlo, y reintentar en cada salida de partida sería
        // exactamente el comportamiento pesado que esto evita.
        defaults.set(Date(), forKey: Keys.lastAsked)
        AppStore.requestReview(in: scene)
    }

#if DEBUG
    /// Corre sola al arrancar en Debug. El fallo que vigila es el que no se
    /// ve: umbrales mal puestos que hacen que el aviso no salga nunca.
    static func selfCheck() {
        let day: TimeInterval = 24 * 3600
        let ok = shouldAsk(sessions: 3, playTime: 20 * 60, installedFor: 3 * day, sinceLastAsk: nil)
        assert(ok, "con los mínimos exactos tiene que preguntar")
        assert(!shouldAsk(sessions: 2, playTime: 60 * 60, installedFor: 30 * day, sinceLastAsk: nil))
        assert(!shouldAsk(sessions: 9, playTime: 60, installedFor: 30 * day, sinceLastAsk: nil))
        assert(!shouldAsk(sessions: 9, playTime: 60 * 60, installedFor: day, sinceLastAsk: nil))
        // Ya preguntado hace poco: no se insiste.
        assert(!shouldAsk(sessions: 9, playTime: 60 * 60, installedFor: 30 * day, sinceLastAsk: day))
        assert(shouldAsk(sessions: 9, playTime: 60 * 60, installedFor: 30 * day, sinceLastAsk: 90 * day))
    }
#endif
}
