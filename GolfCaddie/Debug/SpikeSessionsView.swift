import SwiftUI
import WatchConnectivity

/// List of watch-recorded session folders received into a Documents
/// subdirectory. Share zips a session folder for AirDrop/Files; the folder is
/// also reachable directly via Finder (UIFileSharingEnabled). Two users:
///   - the DEBUG-only validation/spike recordings (Documents/SpikeSessions, B20);
///   - the standalone-spike GPS/battery telemetry (Documents/WatchTelemetry),
///     which ships in Release so a TestFlight field test can export it.
struct SpikeSessionsView: View {
    let root: URL
    let title: String

    struct SessionFolder: Identifiable {
        let id: String
        let url: URL
        let fileCount: Int
        let bytes: Int64
    }

    @State private var sessions: [SessionFolder] = []
    @State private var pendingShare: URL?

    var body: some View {
        List {
            if sessions.isEmpty {
                Text("No sessions received yet. End a recording on the watch, then open this app to drain the transfer queue.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text(wcDebugStatus)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            ForEach(sessions) { session in
                Button {
                    pendingShare = zipForSharing(session.url)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.id).font(.subheadline.monospaced())
                            Text("\(session.fileCount) files · \(ByteCountFormatter.string(fromByteCount: session.bytes, countStyle: .file))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete(perform: delete)
        }
        .navigationTitle(title)
        .onAppear(perform: reload)
        .sheet(item: Binding(
            get: { pendingShare.map { ShareItem(url: $0) } },
            set: { if $0 == nil { pendingShare = nil } }
        )) { item in
            ShareSheet(url: item.url)
        }
    }

    private var wcDebugStatus: String {
        guard WCSession.isSupported() else { return "WC unsupported" }
        let s = WCSession.default
        let act = ["notActivated", "inactive", "activated"][s.activationState.rawValue]
        return "WC \(act) · paired \(s.isPaired ? "yes" : "NO") · watch app \(s.isWatchAppInstalled ? "yes" : "NO") · reachable \(s.isReachable ? "yes" : "no")"
    }

    private struct ShareItem: Identifiable {
        let url: URL
        var id: String { url.path }
    }

    private func reload() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        sessions = dirs
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { dir in
                let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
                let bytes = files.reduce(Int64(0)) {
                    $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
                return SessionFolder(id: dir.lastPathComponent, url: dir, fileCount: files.count, bytes: bytes)
            }
            .sorted { $0.id > $1.id }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            try? FileManager.default.removeItem(at: sessions[index].url)
        }
        reload()
    }

    /// NSFileCoordinator's `.forUploading` produces a zipped copy of a
    /// directory — the system's own trick for sharing folders.
    private func zipForSharing(_ dir: URL) -> URL? {
        var result: URL?
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: dir, options: .forUploading, error: &coordError) { zipped in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(dir.lastPathComponent + ".zip")
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: zipped, to: dest)) != nil {
                result = dest
            }
        }
        return result
    }
}
