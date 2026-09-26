//
//  SpeechManager.swift
//  Homework4Timers
//
//  Created by Papp Zoltán on 2026. 09. 25..
//

import Foundation
import SwiftUI
import AVFAudio

final class SpeechManager: NSObject {
    @AppStorage("appLanguage") private var appLanguage: String = "hu-HU"

    static let shared = SpeechManager()
    private let synthesizer = AVSpeechSynthesizer()
    
    private override init() {
        super.init()
        // Beállítjuk az audio session-t az osztály inicializálásakor
        configureAudioSession()
        observeAppLifecycle()
    }
    
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("Nem sikerült az AudioSession konfigurációja: \(error)")
        }
    }
    
    private func observeAppLifecycle() {
        // Amikor az app háttérbe vonul vagy lezár a képernyő, újra megerősítjük az audio session-t
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc private func handleDidEnterBackground() {
        // Biztosítjuk, hogy az audio session aktív maradjon a háttérbe kerüléskor
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func speak(text: String) {
        // Győződjünk meg róla, hogy az AudioSession aktív
        try? AVAudioSession.sharedInstance().setActive(true)
        
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: appLanguage)
        
        synthesizer.speak(utterance)
    }
}
