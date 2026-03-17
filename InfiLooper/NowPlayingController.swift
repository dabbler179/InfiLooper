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
/// Supports multiple simultaneous media player apps with focus management.
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
    var volume: Int = 100
    /// True when Apple Events permission was denied — shows guidance in the UI.
    var permissionDenied: Bool = false

    // MARK: - Multi-Source State

    /// Media player apps currently running on the system.
    var runningSources: [MediaSource] = []

    /// The source InfiLooper is currently focused on. Nil when no media apps are running.
    var activeSource: MediaSource? = nil

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
    /// Tracks which sources were running on the previous poll cycle, for detecting launches/quits.
    private var previousRunningIDs: Set<String> = []
    /// When true, the user explicitly chose a source — don't auto-switch away from it.
    private var userSelectedSource = false
    /// When true, skip overwriting volume from polls (user is dragging the slider).
    var isAdjustingVolume = false
    /// Remembers the last-known volume for each source so switching back restores it.
    private var volumePerSource: [String: Int] = [:]

    init() {
        MediaBridge.warmup()
        startPolling()
    }

    /// Switch focus to a specific source. Resets loop state since we're changing apps.
    func selectSource(_ source: MediaSource) {
        guard source != activeSource else { return }
        // Save outgoing source's volume
        if let outgoing = activeSource {
            volumePerSource[outgoing.id] = volume
        }
        activeSource = source
        userSelectedSource = true
        // Restore incoming source's volume if we have it
        if let savedVolume = volumePerSource[source.id] {
            volume = savedVolume
        }
        resetTrackState()
        // Immediately fetch info from the new source
        fetchNowPlayingInfo()
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
            // Detect which apps are running
            let running = MediaBridge.runningSources()
            let runningIDs = Set(running.map(\.id))

            self.runningSources = running

            // --- Focus management ---
            updateFocus(running: running, runningIDs: runningIDs)

            self.previousRunningIDs = runningIDs

            // Fetch info from the active source
            guard let source = self.activeSource else {
                clearTrackState()
                self.isFetching = false
                return
            }

            var info = await MediaBridge.getNowPlayingInfo(for: source)
            var resolvedSource = source

            // Clear the user-selected flag once that source starts playing
            if self.userSelectedSource && info.isPlaying {
                self.userSelectedSource = false
            }

            // If active source stopped playing, not looping, user hasn't explicitly chosen it,
            // and other apps are running, check if exactly one other source is playing and switch to it.
            if !info.isPlaying && !self.isLooping && !self.userSelectedSource && running.count > 1 {
                let others = running.filter { $0 != source }
                var playingSource: MediaSource?
                for other in others {
                    let otherInfo = await MediaBridge.getNowPlayingInfo(for: other)
                    if otherInfo.isPlaying {
                        if playingSource == nil {
                            playingSource = other
                            info = otherInfo
                        } else {
                            // Multiple others are playing — don't auto-switch
                            playingSource = nil
                            break
                        }
                    }
                }
                if let newSource = playingSource {
                    // Save outgoing source's volume before auto-switching
                    self.volumePerSource[source.id] = self.volume
                    resolvedSource = newSource
                    self.activeSource = newSource
                    // Restore saved volume for the new source
                    if let savedVolume = self.volumePerSource[newSource.id] {
                        self.volume = savedVolume
                    }
                }
            }

            // Track changed — reset loop
            if info.title != self.title || info.artist != self.artist || resolvedSource != source {
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
            if !self.isAdjustingVolume {
                self.volume = info.volume
            }
            // Keep per-source volume map up to date
            if let src = self.activeSource {
                self.volumePerSource[src.id] = self.volume
            }
            // Check if permission was denied
            self.permissionDenied = MediaBridge.permissionDenied
            self.isFetching = false
        }
    }

    /// Determines which source should have focus based on running apps and current state.
    private func updateFocus(running: [MediaSource], runningIDs: Set<String>) {
        // If the active source just quit, we must switch away
        if let current = activeSource, !runningIDs.contains(current.id) {
            volumePerSource[current.id] = volume
            isLooping = false
            // Fall back to the first remaining running source, or nil
            activeSource = running.first
            if let newSource = activeSource, let savedVolume = volumePerSource[newSource.id] {
                volume = savedVolume
            }
            resetTrackState()
            return
        }

        // If we have no active source, pick the first running one
        if activeSource == nil {
            activeSource = running.first
            return
        }

        // If actively looping, never auto-switch — user is working with this source
        if isLooping {
            return
        }

        // Detect newly launched apps (present now but not on previous poll)
        let newlyLaunched = running.filter { !previousRunningIDs.contains($0.id) }
        if let newApp = newlyLaunched.first {
            // A new media app just started — switch focus to it (since we're not looping)
            activeSource = newApp
            resetTrackState()
        }
    }

    /// Clear now-playing fields without touching loop state.
    private func clearTrackState() {
        title = ""
        artist = ""
        album = ""
        duration = 0
        elapsedTime = 0
        isPlaying = false
        playerApp = ""
        artworkURL = ""
    }

    /// Reset loop state and clear track info (used when switching sources).
    private func resetTrackState() {
        isLooping = false
        loopStart = 0
        loopEnd = 0
        clearTrackState()
    }

    /// Locally interpolate elapsed time between polls for smoother UI.
    private func tickElapsed() {
        guard isPlaying, duration > 0 else { return }
        elapsedTime = min(elapsedTime + 0.2, duration)
    }

    // MARK: - Loop Boundary Check

    private func checkLoopBoundary() {
        guard isLooping, isPlaying, duration > 0 else { return }

        // Seek early enough to account for AppleScript command latency (~150-250ms).
        // Triggering at loopEnd - 0.6 gives the seek command time to execute
        // before playback actually reaches loopEnd, reducing the audible skip.
        let seekThreshold = 0.6
        let driftThreshold = 0.5

        if elapsedTime >= loopEnd - seekThreshold || elapsedTime < loopStart - driftThreshold {
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

    func setVolume(_ level: Int) {
        volume = level
        let app = playerApp
        Task.detached {
            await MediaBridge.setVolume(level, app: app)
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
