import Foundation
import GRDB

/// Produces a self-contained, atomic snapshot of the on-device database for
/// share/export. Uses SQLite's `VACUUM INTO`, which writes a fully consistent
/// single-file copy with no companion WAL/SHM — safe to share live without
/// pausing writes, and immediately openable in any SQLite tool (DB Browser
/// for SQLite, sqlite3 CLI, etc.).
///
/// Recovery is manual today: copy the exported `.sqlite` back into the app's
/// Application Support directory as `golfcaddie.sqlite` via Xcode
/// "Download Container" / "Replace Container". An in-app import flow is a
/// follow-up if user demand justifies it.
extension Database {
    static func makeExport() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        let stamp = formatter.string(from: Date())

        let filename = "fairway-logbook-rounds-\(stamp).sqlite"
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)

        // VACUUM INTO refuses to overwrite; clear any leftover from a prior
        // export landing in the same second (rare, but defensive).
        try? FileManager.default.removeItem(at: exportURL)

        // SQLite string literals use single quotes; escape any embedded
        // single quote by doubling it. (Temp paths shouldn't contain
        // single quotes on iOS, but cheap to be safe.)
        let escapedPath = exportURL.path.replacingOccurrences(of: "'", with: "''")
        try Database.queue.write { db in
            try db.execute(sql: "VACUUM INTO '\(escapedPath)'")
        }
        return exportURL
    }
}
