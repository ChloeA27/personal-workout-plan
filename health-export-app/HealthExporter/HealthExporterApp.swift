import SwiftUI

@main
struct HealthExporterApp: App {
    @StateObject private var healthKitManager = HealthKitManager()

    init() {
        let manager = healthKitManager
        Task { @MainActor in
            manager.registerBackgroundObservers()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(healthKitManager)
        }
    }
}
