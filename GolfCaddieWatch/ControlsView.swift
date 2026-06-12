import SwiftUI

/// Secondary page: label picker (set once per protocol block), start/stop,
/// and session vitals (elapsed, delivered Hz, battery, transfer queue).
struct ControlsView: View {
    @EnvironmentObject private var controller: SpikeSessionController
    @ObservedObject private var transfer = WatchTransfer.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Picker("Label", selection: $controller.selectedLabel) {
                    ForEach(RepLabel.allCases) { label in
                        Text(label.display).tag(label)
                    }
                }
                .frame(height: 64)

                Button {
                    Task { await controller.toggle() }
                } label: {
                    Text(controller.phase == .recording ? "End Session" : "Start Session")
                        .frame(maxWidth: .infinity)
                }
                .tint(controller.phase == .recording ? .red : .green)

                VStack(alignment: .leading, spacing: 3) {
                    if let startedAt = controller.startedAt {
                        row("Elapsed", Text(startedAt, style: .timer))
                    }
                    row("Battery", Text("\(controller.batteryPercent)%"))
                    if controller.phase == .recording {
                        row("Rate", Text(String(format: "%.0f Hz", controller.deliveredHz)))
                    }
                    if transfer.outstanding > 0 {
                        row("Queued", Text("\(transfer.outstanding) files"))
                    }
                }
                .font(.caption2)

                if let error = controller.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }

                if controller.phase == .idle {
                    Button {
                        transfer.resendAll()
                    } label: {
                        Text("Resend sessions")
                            .frame(maxWidth: .infinity)
                    }
                }

                if transfer.deliveredCount > 0 {
                    Text("\(transfer.deliveredCount) files delivered")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                if let transferError = transfer.lastTransferError {
                    Text(transferError)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                }

                Text(transfer.debugStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func row(_ label: String, _ value: Text) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            value
        }
    }
}
