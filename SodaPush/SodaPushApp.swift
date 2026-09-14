//
//  SodaPushApp.swift
//  SodaPush
//
//  Created by Phineas Guo on 2026/9/13.
//

import SwiftUI

@main
struct SodaPushApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
