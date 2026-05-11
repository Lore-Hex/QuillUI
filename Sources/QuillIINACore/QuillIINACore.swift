import Foundation
import QuillUI

/// Quill IINA fixtures-only media-player shell.
///
/// Upstream `iina/iina` wraps `mpv` for playback. The decoder
/// backend stays behind an `IINAMediaBackend` protocol so the
/// Swift app shell can compile without bundling libmpv on
/// every build; the fixture backend just records what would
/// play and which item is selected.
///
/// Layout mirrors a typical desktop player:
/// - Top: now-playing title + transport controls.
/// - Bottom-left: playlist sidebar with a "+ Add file" button
///   (no-op so far; future slice wires a real `.fileImporter`).
@MainActor
public struct QuillIINAContentView: View {
    @State private var playlist: [PlaylistItem] = QuillIINAFixtures.playlist
    @State private var selectedID: PlaylistItem.ID? = QuillIINAFixtures.playlist.first?.id
    @State private var isPlaying = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            nowPlaying
            Divider()
            HStack(spacing: 0) {
                playlistSidebar
                    .frame(width: 280)
                Divider()
                playerCanvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(currentItem?.title ?? "Nothing selected")
                .font(.headline)
            Text(currentItem?.subtitle ?? "")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 14) {
                Button(isPlaying ? "Pause" : "Play") {
                    isPlaying.toggle()
                }
                Button("Stop") { isPlaying = false }
                Spacer()
                Text(currentItem?.duration ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
        .padding(14)
    }

    private var playlistSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Playlist").font(.headline)
                Spacer()
                Button("+ Add file") {
                    // Future: wire a `.fileImporter` and append the
                    // selected URLs as PlaylistItems.
                }
                .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            List {
                ForEach(playlist) { item in
                    Button {
                        selectedID = item.id
                    } label: {
                        playlistRow(item)
                    }
                }
            }
        }
    }

    private func playlistRow(_ item: PlaylistItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title).font(.subheadline).lineLimit(1)
            Text(item.subtitle).font(.caption).foregroundColor(.secondary).lineLimit(1)
        }
        .padding(.vertical, 4)
    }

    private var playerCanvas: some View {
        VStack {
            Spacer()
            Text(isPlaying ? "▶ Playing" : "⏸ Paused")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.secondary)
            if let item = currentItem {
                Text(item.title)
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.04))
    }

    private var currentItem: PlaylistItem? {
        guard let id = selectedID else { return nil }
        return playlist.first(where: { $0.id == id })
    }
}

// MARK: - Fixture model

public struct PlaylistItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var subtitle: String
    public var duration: String

    public init(id: UUID = UUID(), title: String, subtitle: String, duration: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.duration = duration
    }
}

public enum QuillIINAFixtures {
    public static let playlist: [PlaylistItem] = [
        PlaylistItem(title: "Big Buck Bunny", subtitle: "Open-source short, 2008", duration: "9:56"),
        PlaylistItem(title: "Sintel", subtitle: "Blender Foundation, 2010", duration: "14:48"),
        PlaylistItem(title: "Tears of Steel", subtitle: "Blender Foundation, 2012", duration: "12:14"),
        PlaylistItem(title: "Charge", subtitle: "Blender Studio, 2022", duration: "10:14"),
    ]
}
