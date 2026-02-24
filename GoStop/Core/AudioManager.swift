import Foundation
import AVFoundation

class AudioManager {
    static let shared = AudioManager()
    private var audioPlayer: AVAudioPlayer?
    
    private init() {}
    
    func startBackgroundMusic() {
        guard let url = Bundle.main.url(forResource: "Pixel_Paradise_Groove", withExtension: "mp3") else {
            print("AudioManager: Could not find Pixel_Paradise_Groove.mp3")
            return
        }
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1 // Infinite loop
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            print("AudioManager: Started background music")
        } catch {
            print("AudioManager: Could not play audio file - \(error.localizedDescription)")
        }
    }
    
    func stopBackgroundMusic() {
        audioPlayer?.stop()
    }
    
    func toggleMusic() {
        if let player = audioPlayer {
            if player.isPlaying {
                player.pause()
            } else {
                player.play()
            }
        }
    }
}
