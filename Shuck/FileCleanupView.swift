import ShuckKit
import SwiftUI

/// File Cleanup's landing page: each sub-tool with its one-line summary, last scan time, reclaimable estimate and its
/// own Scan button (FCL-004).
struct FileCleanupView: View {
    let info: ToolInfo
    let model: FileCleanupModel

    var body: some View {
        List {
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
            Button("Scan") {
                model.scan(subTool)
            }
            .disabled(!model.canScan(subTool))
            .accessibilityLabel(Text("Scan \(String(localized: subTool.info.name))"))
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
            case .scanned(let summary):
                Text("\(summary.reclaimableBytes, format: .byteCount(style: .file)) reclaimable")
                Text("Scanned \(summary.finished, format: .relative(presentation: .named))")
                if summary.notAccessibleCount > 0 {
                    Label("Some folders were not accessible", systemImage: "exclamationmark.triangle")
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
