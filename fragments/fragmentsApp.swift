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
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

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

        let (passed4, logs4) = SupabaseAuthVerifier.runAllTests()
        print("=== SUPABASE AUTH FOUNDATION VERIFICATION (PHASE 2A) ===")
        for log in logs4 {
            print(log)
        }
        print("=== RESULT (PHASE 2A): \(passed4 ? "ALL TESTS PASSED ✅" : "SOME TESTS FAILED ❌") ===")

        let (passed12, logs12) = MemberDisplayNameAndDiscardVerifier.runAllTests()
        print("=== MEMBER DISPLAY NAME + DISCARD REGRESSION VERIFICATION (BUG 1 & 2) ===")
        for log in logs12 {
            print(log)
        }
        print("=== RESULT (BUG 1 & 2): \(passed12 ? "ALL TESTS PASSED ✅" : "SOME TESTS FAILED ❌") ===")

        Task {
            let (passed5, logs5) = await SupabaseRepositoryVerifier.runAllTests()
            print("=== SUPABASE REPOSITORY VERIFICATION (PHASE 2B) ===")
            for log in logs5 {
                print(log)
            }
            print("=== RESULT (PHASE 2B): \(passed5 ? "ALL TESTS PASSED ✅" : "SOME TESTS FAILED ❌") ===")

            let (passed6, logs6) = await SupabaseRealtimeVerifier.runAllTests()
            print("=== SUPABASE REALTIME COORDINATOR VERIFICATION (PHASE 2C-1) ===")
            for log in logs6 {
                print(log)
            }
            print("=== RESULT (PHASE 2C-1): \(passed6 ? "ALL TESTS PASSED ✅" : "SOME TESTS FAILED ❌") ===")

            let (passed7, logs7) = await RealtimeConvergenceVerifier.runAllTests()
            print("=== SUPABASE REALTIME CONVERGENCE VERIFICATION (PHASE 1) ===")
            for log in logs7 {
                print(log)
            }
            print("=== RESULT (PHASE 1 CONVERGENCE): \(passed7 ? "ALL TESTS PASSED ✅" : "SOME TESTS FAILED ❌") ===")

            let (passed8, logs8) = await RemoteMediaVerifier.runAllTests()
            print("=== REMOTE MEDIA DOWNLOAD & LOCAL CACHE VERIFICATION (PHASE 2) ===")
            for log in logs8 {
                print(log)
            }
            print("=== RESULT (PHASE 2 REMOTE MEDIA): \(passed8 ? "ALL TESTS PASSED ✅" : "SOME TESTS FAILED ❌") ===")

            let (passed9, logs9) = await UnifiedIdentityVerifier.runAllTests()
            print("=== UNIFIED SUPABASE IDENTITY VERIFICATION (PHASE 3) ===")
            for log in logs9 {
                print(log)
            }
            print("=== RESULT (PHASE 3 UNIFIED IDENTITY): \(passed9 ? "ALL TESTS PASSED ✅" : "SOME TESTS FAILED ❌") ===")

            let (passed10, logs10) = await PersonalFragmentSharingVerifier.runAllTests()
            print("=== PERSONAL FRAGMENT TO ROOM SHARING VERIFICATION (PHASE 4) ===")
            for log in logs10 {
                print(log)
            }
            print("=== RESULT (PHASE 4 SHARING): \(passed10 ? "ALL TESTS PASSED ✅" : "SOME TESTS FAILED ❌") ===")

            let (passed11, logs11) = await CollaborativeP0Verifier.runAllTests()
            print("=== COLLABORATIVE P0 BLOCKERS VERIFICATION (P0-1, P0-2, P0-3) ===")
            for log in logs11 {
                print(log)
            }
            print("=== RESULT (COLLABORATIVE P0): \(passed11 ? "ALL TESTS PASSED ✅" : "SOME TESTS FAILED ❌") ===")
        }

        let allLogs = (logs1 + logs2 + logs3 + logs4 + logs12).joined(separator: "\n")
        let logPath = NSTemporaryDirectory() + "fragments_verification.log"
        try? allLogs.write(toFile: logPath, atomically: true, encoding: .utf8)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if isSplashScreenDone {
                    if hasCompletedOnboarding {
                        ContentView()
                            .transition(.opacity)
                    } else {
                        OnboardingView { result in
                            if case .success = result {
                                withAnimation(.easeInOut(duration: 0.45)) {
                                    hasCompletedOnboarding = true
                                }
                            }
                        }
                        .transition(.opacity)
                    }
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
