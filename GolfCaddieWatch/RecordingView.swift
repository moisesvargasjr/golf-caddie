import SwiftUI

/// Primary page while recording: the entire screen is the ground-truth mark
/// button so it works one-handed with a glove, without looking.
struct RecordingView: View {
    @EnvironmentObject private var controller: SpikeSessionController
    @ObservedObject private var transfer = WatchTransfer.shared

    var body: some View {
        if controller.phase == .recording {
            Button {
                controller.mark()
            } label: {
                VStack(spacing: 4) {
                    Text(controller.selectedLabel.display.uppercased())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("MARK")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                    Text("rep \((controller.repCounts[controller.selectedLabel] ?? 0) + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0f Hz", controller.deliveredHz))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.green.opacity(0.18))
            .ignoresSafeArea()
        } else {
            VStack(spacing: 8) {
                Image(systemName: "record.circle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text("Not recording")
                    .font(.headline)
                Text("Scroll down to start")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if transfer.outstanding > 0 {
                    Text("\(transfer.outstanding) files queued to phone")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}
