//
//  fragmentsApp.swift
//  fragments
//
//  Created by Muhammad Bintang Al-Fath on 9/12/26.
//

import SwiftUI
import SwiftData

@main
struct fragmentsApp: App {
    @State private var isSplashScreenDone: Bool = false

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SDFragment.self,
            SDMoment.self,
            SDMomentItem.self
        ])
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: isPreview,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Fallback to in-memory container so Previews and development builds never crash
            let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            if let fallbackContainer = try? ModelContainer(for: schema, configurations: [fallbackConfig]) {
                return fallbackContainer
            }
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isSplashScreenDone {
                    ContentView()
                        .transition(.opacity)
                } else {
                    SplashScreenView {
                        withAnimation(.easeInOut(duration: 0.45)) {
                            isSplashScreenDone = true
                        }
                    }
                    .transition(.opacity)
                }
            }
            .tint(Color.primary)
        }
        .modelContainer(sharedModelContainer)
    }
}
