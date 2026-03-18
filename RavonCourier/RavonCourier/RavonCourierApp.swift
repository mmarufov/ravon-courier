//
//  RavonCourierApp.swift
//  RavonCourier
//
//  Created by Muhammad Marufov on 3/17/26.
//

import SwiftUI
import Foundation
import RavonCore

@main
struct RavonCourierApp: App {
    init() {
        Task { @MainActor in
            RavonCore.configure(
                supabaseURL: URL(string: "https://imcintoicxvmvzwpmxpr.supabase.co")!,
                supabaseAnonKey: "PASTE_LATER"
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
