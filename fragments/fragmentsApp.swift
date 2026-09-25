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

    init() {
        #if DEBUG
        let (passed1, logs1) = CloudKitFoundationVerifier.runAllTests()
        print("=== CLOUDKIT FOUNDATION SELF-VERIFICATION (PHASE 1-3) ===")
        for log in logs1 {
            print(log)
        }
        print("=== RESULT (PHASE 1-3): \(passed1 ? "ALL TESTS PASSED ✅" : "SOME TESTS FAILED ❌") ===")

        let (passed2, logs2) = RoomsPhase4And5Verifier.runAllTests()
        print("=== ROOMS REPOSITORY & CLOUDKIT INFRASTRUCTURE VERIFICATION (PHASE 4-5) ===")
        for log in logs2 {
            print(log)
        }
        print("=== RESULT (PHASE 4-5): \(passed2 ? "ALL TESTS PASSED ✅" : "SOME TESTS FAILED ❌") ===")

        let (passed3, logs3) = CloudKitCollaborationValidator.runAllTests()
        print("=== REAL CLOUDKIT COLLABORATION VALIDATION (PHASE 6) ===")
        for log in logs3 {
            print(log)
        }
        print("=== RESULT (PHASE 6): \(passed3 ? "ALL TESTS PASSED ✅" : "SOME TESTS FAILED ❌") ===")

        let allLogs = (logs1 + logs2 + logs3).joined(separator: "\n")
        let logPath = NSTemporaryDirectory() + "fragments_verification.log"
        try? allLogs.write(toFile: logPath, atomically: true, encoding: .utf8)
        #endif
    }

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
