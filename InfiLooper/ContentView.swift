//
//  ContentView.swift
//  InfiLooper
//
//  Created by Omkar Kolangade on 3/15/26.
//

import SwiftUI

struct ContentView: View {
    @Bindable var controller: NowPlayingController
    @State private var showingHelp = false

    var body: some View {
        VStack(spacing: 12) {
            if showingHelp {
                helpSection
            } else {
                // Source selector — only visible when multiple media apps are running
                if controller.runningSources.count > 1 {
                    sourceSelector
                }

                // Track info
                trackInfoSection

                if !controller.title.isEmpty && controller.duration <= 0 {
                    streamingWarning
                } else if controller.duration > 0 {
                    // Seek bar with loop range overlay
                    seekBarSection

                    // Time labels
                    timeLabelsSection

                    // Loop controls
                    loopControlsSection
                } else {
                    noMediaSection
                }

                // Media controls
                mediaControlsSection
            }

            Divider()

            // Footer: help button + quit button
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingHelp.toggle()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: showingHelp ? "xmark.circle" : "questionmark.circle")
                        Text(showingHelp ? "Close" : "Help")
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel(showingHelp ? "Close help" : "Show help")

                Spacer()

                Button("Quit InfiLooper") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    // MARK: - Source Selector

    private var sourceSelector: some View {
        HStack(spacing: 4) {
            Text("Looping from")
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                ForEach(controller.runningSources) { source in
                    Button {
                        controller.selectSource(source)
                    } label: {
                        Label {
                            Text(source.name)
                        } icon: {
                            Image(nsImage: source.appIcon)
                        }
                    }
                }
            } label: {
                if let active = controller.activeSource {
                    HStack(spacing: 4) {
                        Image(nsImage: active.appIcon)
                            .resizable()
                            .frame(width: 14, height: 14)
                        Text(active.name)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Choose which media player to loop")
        }
    }

    // MARK: - Track Info

    private var trackInfoSection: some View {
        HStack(spacing: 10) {
            // Album artwork
            if let url = URL(string: controller.artworkURL), !controller.artworkURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        artworkPlaceholder
                    case .empty:
                        ProgressView()
                            .frame(width: 48, height: 48)
                    @unknown default:
                        artworkPlaceholder
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("Album artwork")
            } else if !controller.title.isEmpty {
                artworkPlaceholder
            }

            VStack(alignment: .leading, spacing: 2) {
                if controller.title.isEmpty {
                    Text("No media playing")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(controller.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityLabel("Track: \(controller.title)")

                    if !controller.artist.isEmpty {
                        Text(controller.artist)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .accessibilityLabel("Artist: \(controller.artist)")
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.gray.opacity(0.2))
            .frame(width: 48, height: 48)
            .overlay {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
    }

    // MARK: - Seek Bar with Loop Range

    private var seekBarSection: some View {
        LoopRangeSlider(
            duration: controller.duration,
            elapsed: controller.elapsedTime,
            loopStart: $controller.loopStart,
            loopEnd: $controller.loopEnd,
            isLooping: controller.isLooping,
            onSeek: { time in
                controller.seekTo(time)
            }
        )
        .frame(height: 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Playback progress")
        .accessibilityValue(
            "\(NowPlayingController.formatTime(controller.elapsedTime)) of \(NowPlayingController.formatTime(controller.duration))"
        )
    }

    // MARK: - Time Labels

    private var timeLabelsSection: some View {
        HStack {
            Text(NowPlayingController.formatTime(controller.elapsedTime))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityLabel("Elapsed: \(NowPlayingController.formatTime(controller.elapsedTime))")

            Spacer()

            if controller.isLooping {
                Text("Loop: \(NowPlayingController.formatTime(controller.loopStart)) - \(NowPlayingController.formatTime(controller.loopEnd))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Loop range from \(NowPlayingController.formatTime(controller.loopStart)) to \(NowPlayingController.formatTime(controller.loopEnd))")
            }

            Spacer()

            Text(NowPlayingController.formatTime(controller.duration))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityLabel("Duration: \(NowPlayingController.formatTime(controller.duration))")
        }
    }

    // MARK: - Loop Controls

    private var loopControlsSection: some View {
        HStack(spacing: 12) {
            Button {
                controller.toggleLoop()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "repeat")
                    Text(controller.isLooping ? "Looping" : "Loop")
                        .font(.caption)
                }
                .foregroundStyle(controller.isLooping ? .orange : .primary)
            }
            .buttonStyle(.bordered)
            .tint(controller.isLooping ? .orange : nil)
            .accessibilityLabel(controller.isLooping ? "Disable loop" : "Enable loop")
            .accessibilityHint("Loops playback between the selected start and end times")
        }
    }

    // MARK: - Media Controls

    private var mediaControlsSection: some View {
        HStack(spacing: 20) {
            // Restart / go to loop start
            Button {
                controller.startOver()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(controller.isLooping ? "Go to loop start" : "Start over")

            // Play / Pause
            Button {
                controller.togglePlayPause()
            } label: {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(controller.isPlaying ? "Pause" : "Play")
        }
        .padding(.top, 4)
    }

    // MARK: - Streaming Warning

    private var streamingWarning: some View {
        VStack(spacing: 4) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Streaming media detected.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Looping is not supported for streaming content.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Streaming media detected. Looping is not supported for streaming content.")
    }

    // MARK: - No Media

    private var noMediaSection: some View {
        Text("Play something to get started")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }

    // MARK: - Help

    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How to Use InfiLooper")
                .font(.headline)

            helpItem(
                icon: "play.circle",
                title: "Play a track",
                detail: "Open Spotify or Apple Music and play a song. InfiLooper detects it automatically."
            )

            helpItem(
                icon: "repeat",
                title: "Set a loop",
                detail: "Tap Loop to enable looping. Drag the green handle to set the start and the red handle to set the end."
            )

            helpItem(
                icon: "slider.horizontal.below.rectangle",
                title: "Seek",
                detail: "Tap anywhere on the progress bar to jump to that point in the track."
            )

            helpItem(
                icon: "backward.end.fill",
                title: "Restart",
                detail: "Tap the restart button to jump back to the loop start, or to the beginning if looping is off."
            )

            helpItem(
                icon: "antenna.radiowaves.left.and.right",
                title: "Streaming",
                detail: "Live radio and streams without a fixed duration cannot be looped."
            )
        }
        .padding(.vertical, 4)
    }

    private func helpItem(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Loop Range Slider

/// A custom slider that shows the media seek position and allows setting loop start/end
/// with two draggable round thumb handles.
struct LoopRangeSlider: View {
    let duration: Double
    let elapsed: Double
    @Binding var loopStart: Double
    @Binding var loopEnd: Double
    let isLooping: Bool
    let onSeek: (Double) -> Void

    private let trackHeight: CGFloat = 6
    private let thumbSize: CGFloat = 16

    @State private var isDraggingStart = false
    @State private var isDraggingEnd = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let midY = geometry.size.height / 2

            ZStack {
                // Background track
                Capsule()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: trackHeight)
                    .position(x: width / 2, y: midY)

                // Elapsed progress (seek bar)
                let elapsedFraction = duration > 0 ? min(elapsed / duration, 1) : 0
                Capsule()
                    .fill(Color.accentColor.opacity(0.5))
                    .frame(width: max(0, width * elapsedFraction), height: trackHeight)
                    .position(x: width * elapsedFraction / 2, y: midY)

                if isLooping && duration > 0 {
                    // Loop region highlight
                    let startFraction = loopStart / duration
                    let endFraction = loopEnd / duration
                    let regionX = width * startFraction
                    let regionWidth = width * (endFraction - startFraction)

                    RoundedRectangle(cornerRadius: trackHeight / 2)
                        .fill(Color.orange.opacity(0.35))
                        .frame(width: max(0, regionWidth), height: trackHeight)
                        .position(x: regionX + regionWidth / 2, y: midY)

                    // Start thumb
                    Circle()
                        .fill(Color.green)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(radius: 2)
                        .position(x: width * startFraction, y: midY)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isDraggingStart = true
                                    let fraction = min(max(value.location.x / width, 0), 1)
                                    let newStart = fraction * duration
                                    if newStart < loopEnd - 1 {
                                        loopStart = max(0, newStart)
                                    }
                                }
                                .onEnded { _ in
                                    isDraggingStart = false
                                }
                        )
                        .accessibilityLabel("Loop start")
                        .accessibilityValue(NowPlayingController.formatTime(loopStart))

                    // End thumb
                    Circle()
                        .fill(Color.red)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(radius: 2)
                        .position(x: width * endFraction, y: midY)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isDraggingEnd = true
                                    let fraction = min(max(value.location.x / width, 0), 1)
                                    let newEnd = fraction * duration
                                    if newEnd > loopStart + 1 {
                                        loopEnd = min(duration, newEnd)
                                    }
                                }
                                .onEnded { _ in
                                    isDraggingEnd = false
                                }
                        )
                        .accessibilityLabel("Loop end")
                        .accessibilityValue(NowPlayingController.formatTime(loopEnd))
                }

                // Seek position indicator (small white line)
                if duration > 0 {
                    let seekX = width * elapsedFraction
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white)
                        .frame(width: 2, height: trackHeight + 6)
                        .position(x: seekX, y: midY)
                }
            }
            // Tap to seek on the track area (only when not dragging thumbs)
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard duration > 0, !isDraggingStart, !isDraggingEnd else { return }
                let fraction = min(max(location.x / width, 0), 1)
                let seekTime = fraction * duration
                onSeek(seekTime)
            }
        }
    }
}

#Preview {
    ContentView(controller: NowPlayingController())
        .frame(width: 320, height: 250)
}
