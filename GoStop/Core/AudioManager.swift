import Foundation
import AVFoundation

class AudioManager {
    static let shared = AudioManager()
    private var backgroundMusicPlayer: AVAudioPlayer?
    private var effectPlayers: [AVAudioPlayer] = []
    private var isAudioSessionConfigured = false
    
    private init() {}
    
    func startBackgroundMusic() {
        configureAudioSessionIfNeeded()

        guard let url = Bundle.main.url(forResource: "Pixel_Paradise_Groove", withExtension: "mp3") else {
            print("AudioManager: Could not find Pixel_Paradise_Groove.mp3")
            return
        }
        
        do {
            backgroundMusicPlayer = try AVAudioPlayer(contentsOf: url)
            backgroundMusicPlayer?.numberOfLoops = -1 // Infinite loop
            backgroundMusicPlayer?.prepareToPlay()
            backgroundMusicPlayer?.play()
            print("AudioManager: Started background music")
        } catch {
            print("AudioManager: Could not play audio file - \(error.localizedDescription)")
        }
    }
    
    func stopBackgroundMusic() {
        backgroundMusicPlayer?.stop()
    }
    
    func toggleMusic() {
        if let player = backgroundMusicPlayer {
            if player.isPlaying {
                player.pause()
            } else {
                player.play()
            }
        }
    }

    func playHwatuCardHitEffect() {
        playEffect(resource: "hwatu_card_hit", fileExtension: "wav", volume: 1.0)
    }

    func playHwatuBlanketPuckEffect() {
        playEffect(resource: "hwatu_blanket_puck", fileExtension: "wav", volume: 1.0)
    }

    func playHwatuTableImpactEffect(isMatch: Bool) {
        if isMatch {
            playHwatuCardHitEffect()
        } else {
            playHwatuBlanketPuckEffect()
        }
    }

    private func playEffect(resource: String, fileExtension: String, volume: Float) {
        configureAudioSessionIfNeeded()

        guard let url = Bundle.main.url(forResource: resource, withExtension: fileExtension) else {
            print("AudioManager: Could not find \(resource).\(fileExtension)")
            return
        }

        do {
            effectPlayers.removeAll { !$0.isPlaying }
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.prepareToPlay()
            player.play()
            effectPlayers.append(player)
            if effectPlayers.count > 12 {
                effectPlayers.removeFirst(effectPlayers.count - 12)
            }
        } catch {
            print("AudioManager: Could not play effect \(resource).\(fileExtension) - \(error.localizedDescription)")
        }
    }

    private func configureAudioSessionIfNeeded() {
        guard !isAudioSessionConfigured else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            isAudioSessionConfigured = true
            print("AudioManager: AVAudioSession configured as playback")
        } catch {
            print("AudioManager: Could not configure AVAudioSession - \(error.localizedDescription)")
        }
    }
}
