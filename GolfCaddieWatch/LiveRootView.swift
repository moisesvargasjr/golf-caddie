import SwiftUI

/// M3 watch UI: a live-status page + a validation page. The production glance
/// UI (big distance-to-green + Crown club picker + add/remove/putt) lands in M6
/// and replaces the status page; validation controls stay as a debug page.
struct LiveRootView: View {
    @EnvironmentObject private var controller: LiveSessionController

    var body: some View {
        TabView {
            LiveStatusView()
            ValidationView()
        }
        .tabViewStyle(.verticalPage)
    }
}

private struct LiveStatusView: View {
    @EnvironmentObject private var controller: LiveSessionController
    @ObservedObject private var session = WatchSession.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Glance preview (proper layout comes in M6).
                if let yards = session.phoneState.distanceToGreenYards {
                    Text("\(yards)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("yds to green").font(.caption2).foregroundStyle(.secondary)
                }
                Text(controller.effectiveClubShort ?? "—")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Divider()

                HStack {
                    Image(systemName: controller.running ? "dot.radiowaves.left.and.right" : "pause.circle")
                        .foregroundStyle(controller.running ? .green : .secondary)
                    Text(controller.running ? "Detecting" : "Idle").font(.caption)
                    Spacer()
                    Text("\(controller.detectionCount) shots").font(.caption).foregroundStyle(.secondary)
                }
                if controller.running {
                    Text(String(format: "%.0f Hz · %d%%", controller.deliveredHz, controller.batteryPercent))
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                Button {
                    Task { await controller.toggle() }
                } label: {
                    Text(controller.running ? "End Round" : "Start Round")
                        .frame(maxWidth: .infinity)
                }
                .tint(controller.running ? .red : .green)

                if let error = controller.lastError {
                    Text(error).font(.caption2).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

private struct ValidationView: View {
    @EnvironmentObject private var controller: LiveSessionController
    @ObservedObject private var session = WatchSession.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Toggle("Validation mode", isOn: $controller.validationMode)
                    .font(.caption)
                    .disabled(controller.running)

                if controller.validationMode {
                    Picker("Label", selection: $controller.selectedLabel) {
                        ForEach(RepLabel.allCases) { Text($0.display).tag($0) }
                    }
                    .frame(height: 60)

                    Button {
                        controller.mark()
                    } label: {
                        Text("MARK \(controller.selectedLabel.display)")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!controller.running)
                }

                if session.outstanding > 0 {
                    Button("Resend (\(session.outstanding))") { session.resendAll() }
                        .font(.caption2)
                }
                if session.deliveredCount > 0 {
                    Text("\(session.deliveredCount) files delivered").font(.caption2).foregroundStyle(.green)
                }
                if let err = session.lastTransferError {
                    Text(err).font(.system(size: 10)).foregroundStyle(.red)
                }
                Text(session.debugStatus).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
        }
    }
}
