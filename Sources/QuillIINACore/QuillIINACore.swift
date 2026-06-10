import Foundation
import QuillFoundation
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
    @State private var playlist: [PlaylistItem]
    @State private var selectedID: PlaylistItem.ID?
    @State private var isPlaying = false

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let playlist = QuillIINAFixtures.playlist
        _playlist = State(initialValue: playlist)
        _selectedID = State(initialValue:
            QuillIINAInitialSelection.selectedPlaylistID(in: playlist, environment: environment)
            ?? playlist.first?.id
        )
    }

    nonisolated public var body: some View {
        QuillMainActorView.assumeIsolated {
            VStack(spacing: 0) {
                nowPlaying
                Divider()
                HStack(spacing: 0) {
                    playlistSidebar
                        .frame(width: 280)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                    Divider()
                    playerCanvas
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
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

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(playlist) { item in
                        playlistRow(item)
                            .onTapGesture {
                                selectedID = item.id
                            }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(QuillDesktopChromeStyle.sidebarBackground)
    }

    private func playlistRow(_ item: PlaylistItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title).font(.subheadline).lineLimit(1)
            Text(item.subtitle).font(.caption).foregroundColor(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(height: 74, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectedID == item.id ? QuillDesktopChromeStyle.selectedRowBackground : Color.clear)
        .cornerRadius(QuillDesktopChromeStyle.selectedRowCornerRadius)
        .contentShape(Rectangle())
    }

    private var playerCanvas: some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                Image(systemName: QuillSystemSymbol.compatibleName(isPlaying ? "play.fill" : "pause.fill"))
                    .renderingMode(Image.TemplateRenderingMode.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.secondary)
                    .frame(width: 38, height: 38)
                Text(isPlaying ? "Playing" : "Paused")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(.secondary)
            }
            if let item = currentItem {
                Text(item.title)
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(QuillDesktopChromeStyle.detailBackground)
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

public enum QuillIINAInitialSelection {
    public static let selectedPlaylistIndexEnvironmentKey = "QUILLUI_IINA_SELECTED_PLAYLIST_INDEX_ON_START"

    public static func selectedPlaylistID(
        in playlist: [PlaylistItem],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PlaylistItem.ID? {
        QuillInitialSelection.selectedID(
            in: playlist,
            environmentKeys: [selectedPlaylistIndexEnvironmentKey],
            environment: environment
        )
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
