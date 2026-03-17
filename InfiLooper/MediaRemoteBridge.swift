//
//  MediaRemoteBridge.swift
//  InfiLooper
//
//  Created by Omkar Kolangade on 3/15/26.
//

import Foundation
import AppKit

// MARK: - Now Playing Info

/// Info about the currently playing media from an external app.
struct NowPlayingInfo: Sendable {
    nonisolated init(title: String = "", artist: String = "", album: String = "", duration: Double = 0, elapsed: Double = 0, isPlaying: Bool = false, playerApp: String = "", artworkURL: String = "", volume: Int = 100) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.isPlaying = isPlaying
        self.playerApp = playerApp
        self.artworkURL = artworkURL
        self.volume = volume
    }
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var duration: Double = 0       // seconds
    var elapsed: Double = 0        // seconds
    var isPlaying: Bool = false
    var playerApp: String = ""     // e.g. "Spotify", "Music"
    var artworkURL: String = ""    // URL to album artwork
    var volume: Int = 100          // 0–100
}

// MARK: - Media Source

/// A media player app that InfiLooper can communicate with.
struct MediaSource: Identifiable, Hashable, Sendable {
    let id: String       // bundle identifier
    let name: String     // display name (e.g. "Spotify")

    /// Returns the app's actual icon from the system, or a fallback SF Symbol.
    @MainActor
    var appIcon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "music.note", accessibilityDescription: name)
            ?? NSImage()
    }
}

// MARK: - Media Bridge

/// Communicates with media player apps (Spotify, Apple Music) to get now-playing info
/// and send playback commands using NSAppleScript, which is compatible with App Sandbox
/// when the appropriate scripting-targets entitlement is present.
enum MediaBridge {

    // MARK: - Supported Apps

    /// All apps InfiLooper knows how to talk to, in default priority order.
    static let allSources: [MediaSource] = [
        MediaSource(id: "com.apple.Music", name: "Music"),
        MediaSource(id: "com.spotify.client", name: "Spotify"),
    ]

    // MARK: - Running App Detection

    /// Returns the subset of `allSources` whose apps are currently running.
    @MainActor
    static func runningSources() -> [MediaSource] {
        allSources.filter { isAppRunning(bundleID: $0.id) }
    }

    /// Check whether a given app is running.
    @MainActor
    private static func isAppRunning(bundleID: String) -> Bool {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleID
        ).first?.isTerminated == false
    }

    // MARK: - Query

    /// Fetch now-playing info from a specific media source.
    nonisolated static func getNowPlayingInfo(for source: MediaSource) async -> NowPlayingInfo {
        if let info = await queryApp(source.name) {
            return info
        }
        return NowPlayingInfo()
    }

    /// Fetch now-playing info from the first running supported media app (legacy convenience).
    nonisolated static func getNowPlayingInfo() async -> NowPlayingInfo {
        let running = await MainActor.run { runningSources() }
        for source in running {
            if let info = await queryApp(source.name) {
                return info
            }
        }
        return NowPlayingInfo()
    }

    /// Query a specific app for its now-playing info.
    nonisolated private static func queryApp(_ appName: String) async -> NowPlayingInfo? {
        let script: String
        switch appName {
        case "Spotify":
            script = """
            tell application "Spotify"
                if player state is playing or player state is paused then
                    set trackName to name of current track
                    set trackArtist to artist of current track
                    set trackAlbum to album of current track
                    set trackDuration to duration of current track
                    set trackPosition to player position
                    set pState to player state
                    set artURL to artwork url of current track
                    set vol to sound volume
                    return trackName & "\n" & trackArtist & "\n" & trackAlbum & "\n" & (trackDuration as text) & "\n" & (trackPosition as text) & "\n" & (pState as text) & "\n" & artURL & "\n" & (vol as text)
                else
                    return ""
                end if
            end tell
            """
        case "Music":
            script = """
            tell application "Music"
                if player state is playing or player state is paused then
                    set trackName to name of current track
                    set trackArtist to artist of current track
                    set trackAlbum to album of current track
                    set trackDuration to duration of current track
                    set trackPosition to player position
                    set pState to player state as text
                    set vol to sound volume
                    return trackName & "\n" & trackArtist & "\n" & trackAlbum & "\n" & (trackDuration as text) & "\n" & (trackPosition as text) & "\n" & pState & "\n" & "\n" & (vol as text)
                else
                    return ""
                end if
            end tell
            """
        default:
            return nil
        }

        guard let output = await runAppleScript(script), !output.isEmpty else {
            return nil
        }

        let lines = output.components(separatedBy: "\n")
        guard lines.count >= 6 else { return nil }

        let title = lines[0]
        let artist = lines[1]
        let album = lines[2]

        // Spotify returns duration in milliseconds, Music in seconds
        let rawDuration = Double(lines[3]) ?? 0
        let duration: Double
        if appName == "Spotify" {
            duration = rawDuration / 1000.0
        } else {
            duration = rawDuration
        }

        let elapsed = Double(lines[4]) ?? 0
        let stateStr = lines[5].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isPlaying = stateStr.contains("playing") || stateStr.contains("kpsp")
        let artworkURL = lines.count >= 7 ? lines[6].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let volume = lines.count >= 8 ? Int(lines[7].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 100 : 100

        return NowPlayingInfo(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            elapsed: elapsed,
            isPlaying: isPlaying,
            playerApp: appName,
            artworkURL: artworkURL,
            volume: volume
        )
    }

    // MARK: - Warmup

    /// Pre-compile frequently used command scripts so the first invocation is fast.
    nonisolated static func warmup() {
        commandQueue.async {
            let commands = [
                "tell application \"Spotify\" to playpause",
                "tell application \"Spotify\" to play",
                "tell application \"Spotify\" to pause",
                "tell application \"Music\" to playpause",
                "tell application \"Music\" to play",
                "tell application \"Music\" to pause",
            ]
            for cmd in commands {
                _ = compiledScript(for: cmd)
            }
        }
    }

    // MARK: - Commands

    nonisolated static func togglePlayPause(app: String) async {
        switch app {
        case "Spotify":
            await runCommand("tell application \"Spotify\" to playpause")
        case "Music":
            await runCommand("tell application \"Music\" to playpause")
        default:
            break
        }
    }

    nonisolated static func play(app: String) async {
        switch app {
        case "Spotify":
            await runCommand("tell application \"Spotify\" to play")
        case "Music":
            await runCommand("tell application \"Music\" to play")
        default:
            break
        }
    }

    nonisolated static func pause(app: String) async {
        switch app {
        case "Spotify":
            await runCommand("tell application \"Spotify\" to pause")
        case "Music":
            await runCommand("tell application \"Music\" to pause")
        default:
            break
        }
    }

    nonisolated static func seekTo(_ position: Double, app: String) async {
        switch app {
        case "Spotify":
            await runCommand("tell application \"Spotify\" to set player position to \(position)")
        case "Music":
            await runCommand("tell application \"Music\" to set player position to \(position)")
        default:
            break
        }
    }

    nonisolated static func setVolume(_ level: Int, app: String) async {
        let clamped = max(0, min(100, level))
        switch app {
        case "Spotify":
            await runCommand("tell application \"Spotify\" to set sound volume to \(clamped)")
        case "Music":
            await runCommand("tell application \"Music\" to set sound volume to \(clamped)")
        default:
            break
        }
    }

    // MARK: - NSAppleScript Runner

    /// Serial queue for polling (low priority, can be slow).
    nonisolated private static let pollQueue = DispatchQueue(label: "com.infilooper.applescript.poll")

    /// Serial queue for commands (high priority, must be fast).
    nonisolated private static let commandQueue = DispatchQueue(
        label: "com.infilooper.applescript.command",
        qos: .userInteractive
    )

    /// Lock-protected cache of pre-compiled NSAppleScript instances.
    nonisolated(unsafe) private static var compiledScripts: [String: NSAppleScript] = [:]
    nonisolated private static let cacheLock = NSLock()

    /// Returns a compiled NSAppleScript, caching for reuse. Thread-safe.
    nonisolated private static func compiledScript(for source: String) -> NSAppleScript? {
        cacheLock.lock()
        if let cached = compiledScripts[source] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let script = NSAppleScript(source: source) else { return nil }
        var compileError: NSDictionary?
        script.compileAndReturnError(&compileError)
        if compileError != nil { return nil }

        cacheLock.lock()
        compiledScripts[source] = script
        cacheLock.unlock()
        return script
    }

    /// Whether Apple Events permission has been denied by the user.
    /// When true, AppleScript commands will fail with -1743.
    nonisolated(unsafe) static var permissionDenied = false

    /// Execute a script on the poll queue (for getNowPlayingInfo).
    @discardableResult
    nonisolated private static func runAppleScript(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            pollQueue.async {
                let script = compiledScript(for: source)
                var error: NSDictionary?
                let descriptor = script?.executeAndReturnError(&error)
                if let error = error,
                   let errorNumber = error[NSAppleScript.errorNumber] as? Int,
                   errorNumber == -1743 {
                    permissionDenied = true
                }
                continuation.resume(returning: error == nil ? descriptor?.stringValue : nil)
            }
        }
    }

    /// Execute a script on the command queue (for play/pause/seek — fast path).
    @discardableResult
    nonisolated private static func runCommand(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            commandQueue.async {
                let script = compiledScript(for: source)
                var error: NSDictionary?
                let descriptor = script?.executeAndReturnError(&error)
                if let error = error,
                   let errorNumber = error[NSAppleScript.errorNumber] as? Int,
                   errorNumber == -1743 {
                    permissionDenied = true
                }
                continuation.resume(returning: error == nil ? descriptor?.stringValue : nil)
            }
        }
    }
}
