//
//  InfiLooperApp.swift
//  InfiLooper
//
//  Created by Omkar Kolangade on 3/15/26.
//

import SwiftUI

@main
struct InfiLooperApp: App {
    var body: some Scene {
        MenuBarExtra("InfiLooper", systemImage: "repeat.circle") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
