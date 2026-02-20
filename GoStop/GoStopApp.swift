import SwiftUI

@main
struct GoStopApp: App {
    private var bridge: SimulatorBridge?
    
    init() {
        #if targetEnvironment(simulator)
        // Ensure GameManager exists by creating a temporary one if needed, 
        // but typically the first View will create it.
        // For the bridge to find it, we need to wait until it's initialized.
        // Simple hack: start bridge and it will poll or wait for shared instance.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if let gm = GameManager.shared {
                SimulatorBridge.shared = SimulatorBridge(gameManager: gm)
                SimulatorBridge.shared?.start()
                print("SimulatorBridge: Started on port 8080")
            } else {
                print("SimulatorBridge: FAILED to start - GameManager.shared is nil")
            }
        }
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
