//
//  InfiLooperApp.swift
//  InfiLooper
//
//  Created by Omkar Kolangade on 3/15/26.
//

import SwiftUI

@main
struct InfiLooperApp: App {
    @State private var controller = NowPlayingController()

    var body: some Scene {
        MenuBarExtra {
            ContentView(controller: controller)
        } label: {
            Image(nsImage: menuBarIcon(looping: controller.isLooping))
                .accessibilityLabel("InfiLooper")
        }
        .menuBarExtraStyle(.window)
    }

    /// Renders the menu bar icon, tinted orange when looping is active.
    private func menuBarIcon(looping: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        let symbol = NSImage(systemSymbolName: "infinity", accessibilityDescription: "InfiLooper")!
            .withSymbolConfiguration(config)!

        if looping {
            // Tint the symbol orange by drawing it and compositing color on top
            let tinted = NSImage(size: symbol.size, flipped: false) { rect in
                symbol.draw(in: rect)
                NSColor.orange.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.isTemplate = false
            return tinted
        } else {
            symbol.isTemplate = true
            return symbol
        }
    }
}
