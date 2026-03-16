//
//  NowPlayingController.swift
//  InfiLooper
//
//  Created by Omkar Kolangade on 3/15/26.
//

import Foundation
import Observation

/// Manages polling of now-playing state from the active media app
/// and handles the looping logic between two user-set timestamps.
@Observable
@MainActor
final class NowPlayingController {
    // MARK: - Now Playing State
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var duration: Double = 0
    var elapsedTime: Double = 0
    var isPlaying: Bool = false
    var playerApp: String = ""
    var artworkURL: String = ""

    // MARK: - Loop Range (in seconds)
    var loopStart: Double = 0 {
        didSet {
            if loopStart >= loopEnd && duration > 0 {
                loopStart = max(0, loopEnd - 1)
            }
        }
    }
    var loopEnd: Double = 0 {
        didSet {
            if loopEnd <= loopStart && duration > 0 {
                loopEnd = min(duration, loopStart + 1)
            }
        }
    }
    var isLooping: Bool = false

    // MARK: - Private
    private var pollTimer: Timer?
    private var loopCheckTimer: Timer?
    private var isFetching = false

    init() {
        MediaBridge.warmup()
        startPolling()
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        loopCheckTimer?.invalidate()
        loopCheckTimer = nil
    }

    // MARK: - Polling

    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.fetchNowPlayingInfo()
            }
        }
        // Faster timer for loop boundary checking — interpolates elapsed time locally
        loopCheckTimer?.invalidate()
        loopCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.tickElapsed()
                self?.checkLoopBoundary()
            }
        }

        // Initial fetch
        fetchNowPlayingInfo()
    }

    private func fetchNowPlayingInfo() {
        guard !isFetching else { return }
        isFetching = true

        Task {
            let info = await MediaBridge.getNowPlayingInfo()

            // Track changed — reset loop
            if info.title != self.title || info.artist != self.artist {
                self.isLooping = false
                self.loopStart = 0
                self.loopEnd = info.duration
            }

            self.title = info.title
            self.artist = info.artist
            self.album = info.album
            self.duration = info.duration
            self.elapsedTime = info.elapsed
            self.isPlaying = info.isPlaying
            self.playerApp = info.playerApp
            self.artworkURL = info.artworkURL
            self.isFetching = false
        }
    }

    /// Locally interpolate elapsed time between polls for smoother UI.
    private func tickElapsed() {
        guard isPlaying, duration > 0 else { return }
        elapsedTime = min(elapsedTime + 0.2, duration)
    }

    // MARK: - Loop Boundary Check

    private func checkLoopBoundary() {
        guard isLooping, isPlaying, duration > 0 else { return }

        if elapsedTime >= loopEnd - 0.4 || elapsedTime < loopStart - 0.5 {
            elapsedTime = loopStart
            let start = loopStart
            let app = playerApp
            Task.detached {
                await MediaBridge.seekTo(start, app: app)
            }
        }
    }

    // MARK: - Media Controls

    func togglePlayPause() {
        isPlaying.toggle()  // Optimistic UI update
        let app = playerApp
        Task.detached {
            await MediaBridge.togglePlayPause(app: app)
        }
        // Sync actual state after a short delay
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            fetchNowPlayingInfo()
        }
    }

    func play() {
        isPlaying = true
        let app = playerApp
        Task.detached {
            await MediaBridge.play(app: app)
        }
    }

    func pause() {
        isPlaying = false
        let app = playerApp
        Task.detached {
            await MediaBridge.pause(app: app)
        }
    }

    func seekTo(_ time: Double) {
        elapsedTime = time
        let app = playerApp
        Task.detached {
            await MediaBridge.seekTo(time, app: app)
        }
    }

    func startOver() {
        if isLooping {
            seekTo(loopStart)
        } else {
            seekTo(0)
        }
    }

    func toggleLoop() {
        isLooping.toggle()
        if isLooping && duration > 0 {
            if loopStart == 0 && loopEnd == 0 {
                loopEnd = duration
            }
            // Only seek to loop start if current position is outside the loop range
            if elapsedTime < loopStart || elapsedTime >= loopEnd {
                seekTo(loopStart)
            }
            if !isPlaying {
                play()
            }
        }
    }

    /// Progress fraction (0...1) of elapsed time within the full track.
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsedTime / duration, 0), 1)
    }

    /// Format seconds into mm:ss.
    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let totalSeconds = Int(seconds)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
