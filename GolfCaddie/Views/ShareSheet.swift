import SwiftUI
import UIKit

/// Share-sheet bridge (UIActivityViewController): the anchor / spike exports
/// (DEBUG) and a finished round's Share round.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    init(items: [Any]) {
        self.items = items
    }

    init(url: URL) {
        self.init(items: [url])
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// What a share sheet is about to share, so it can drive `.sheet(item:)`.
struct ShareItems: Identifiable {
    let id = UUID()
    let items: [Any]
}
