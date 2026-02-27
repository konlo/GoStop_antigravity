import SwiftUI

@main
struct GoStopApp: App {
    init() {
        // Start background music only when enabled in animation.yaml
        if AnimationManager.shared.config.background_music_enabled {
            AudioManager.shared.startBackgroundMusic()
        } else {
            print("AudioManager: Background music disabled by configuration")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
