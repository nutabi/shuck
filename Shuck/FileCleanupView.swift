import ShuckKit
import SwiftUI

/// File Cleanup's landing page: what every finished scan could reclaim together (FCL-007), then each sub-tool with its
/// one-line summary, last scan time, reclaimable estimate and its own Scan button (FCL-004).
struct FileCleanupView: View {
    let info: ToolInfo
    let model: FileCleanupModel

    var body: some View {
        List {
            Section {
                CombinedTotalRow(total: model.combinedTotal)
            }
            Section {
                ForEach(model.subTools, id: \.id) { subTool in
                    SubToolRow(subTool: subTool, model: model)
                }
            } header: {
                Text(info.summary)
            }
        }
        .navigationTitle(Text(info.name))
        .toolbar {
            Button("Scan All", systemImage: "magnifyingglass") {
                model.scanAll()
            }
            .disabled(!model.canScanAll)
            .help("Scan with every sub-tool. Scanning never removes anything.")
        }
    }
}

/// The total of every finished scan, each file counted once (FCL-007).
private struct CombinedTotalRow: View {
    let total: FileCleanupModel.CombinedTotal?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sum")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if let total {
                    Text("\(total.reclaimableBytes, format: .byteCount(style: .file)) reclaimable in total")
                        .font(.headline)
                    Text("Each file counts once, even if several sub-tools list it.")
                        .foregroundStyle(.secondary)
                    if total.scannedCount < total.availableCount {
                        Text(
                            "From \(total.scannedCount) of \(total.availableCount) sub-tools. Scan the others to complete it."
                        )
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No total yet")
                        .font(.headline)
                    Text("Scan to see how much space File Cleanup could reclaim.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct SubToolRow: View {
    let subTool: any SubTool
    let model: FileCleanupModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: subTool.info.symbolName)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(subTool.info.name)
                    .font(.headline)
                Text(subTool.info.summary)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            status
                .font(.callout)
                .foregroundStyle(.secondary)
            if model.state(of: subTool.id) == .scanning {
                Button("Stop") {
                    model.cancelScan(subTool)
                }
                .accessibilityLabel(Text("Stop scanning \(String(localized: subTool.info.name))"))
            } else {
                Button("Scan") {
                    model.scan(subTool)
                }
                .disabled(!model.canScan(subTool))
                .accessibilityLabel(Text("Scan \(String(localized: subTool.info.name))"))
            }
        }
        .padding(.vertical, 6)
    }

    private var status: some View {
        VStack(alignment: .trailing, spacing: 2) {
            switch model.state(of: subTool.id) {
            case .notScanned:
                if case .planned(let milestone) = subTool.info.availability {
                    Text("Planned for milestone \(milestone).")
                } else {
                    Text("Not scanned yet")
                }
            case .scanning:
                ProgressView()
                    .controlSize(.small)
                Text("Scanning…")
            case .stopped:
                Text("Scan stopped")
            case .scanned(let summary):
                Text("\(summary.reclaimableBytes, format: .byteCount(style: .file)) reclaimable")
                // A live time source lets SwiftUI refresh the age without a new scan or a page redraw (FCL-004).
                let age = Text(
                    .currentDate,
                    format: .reference(
                        to: summary.finished, allowedFields: [.year, .month, .day, .hour, .minute, .second],
                        maxFieldCount: 1)
                )
                Text("Scanned \(age)")
                    .accessibilityIdentifier("scan-age-\(subTool.id.rawValue)")
                if summary.notAccessibleCount > 0 {
                    Label("Some folders were not accessible", systemImage: "exclamationmark.triangle")
                }
                if summary.unreadableCount > 0 {
                    Label("Some folders could not be read", systemImage: "exclamationmark.triangle")
                }
            }
        }
    }
}

#Preview {
    if let info = ToolRegistry.standard.info(.fileCleanup) {
        FileCleanupView(
            info: info,
            model: FileCleanupModel(
                subTools: ToolRegistry.standard.subTools, context: ScanContext(home: .temporaryDirectory)))
    }
}
