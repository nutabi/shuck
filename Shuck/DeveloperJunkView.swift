import ShuckKit
import SwiftUI
import os

/// Developer Junk: "What can developer tools rebuild?" So far it lists Xcode's DerivedData, one row per project (DEV-R01,
/// DEV-008), its device support files, one row per version of a platform (DEV-R02), and the simulators' caches, one row
/// for each (DEV-R04), the biggest first. A tool's rule, such as unavailable simulators (DEV-R03) or npm's cache
/// (DEV-R07), is one row with its exact command and a size estimate. Stale projects, those whose project is gone, every version but the newest and
/// every cache start selected; a row whose app is running shows a note instead of a checkbox (SAF-009, CAC-003).
///
/// Choosing rows only marks them. "Delete…" opens the summary confirmation for the selected rebuildable rows, with the
/// totals per category and the full list on demand, and nothing is deleted before the user confirms there (SAF-003).
///
/// Xcode Archives (DEV-R05) are "Your data", one row per archive in a group of their own below the rest. They never start
/// selected, "Select All" leaves them out, and each row says in words that it is moved to the Trash and can be restored.
/// "Move to Trash…" opens the itemized review for the selected archives only, so the two actions never mix tiers
/// (SAF-002, SAF-004, D-147). ``SubToolPage`` gives the page the toolbar, the scan, the messages and the sheets.
struct DeveloperJunkView: View {
    let subTool: DeveloperJunk
    let model: FileCleanupModel
    @Bindable var results: ScanResults
    /// A plan the path guard refused when the user asked to review archives; nothing moves (SAF-007).
    @State private var refusal: PlanError?

    var body: some View {
        SubToolPage(
            subTool: subTool, model: model,
            subtitle: Text("What Xcode, the simulators and package managers can build again"),
            notScanned: Text("Scan to list what developer tools can build again. Scanning never removes anything."),
            nothingFound: Text("Nothing developer tools can build again"),
            scanHelp: Text("Look for what developer tools can rebuild. Scanning never removes anything.")
        ) { actions in
            List {
                ForEach(rows(in: .rebuildable)) { item in
                    ProjectRow(item: item, home: model.home, isSelected: isSelected(item))
                }
                // "Your data" in groups of their own, one per category, after the rebuildable rows (D-147).
                ForEach(yourDataGroups, id: \.category.id) { group in
                    Section {
                        ForEach(group.rows) { item in
                            ProjectRow(item: item, home: model.home, isSelected: isSelected(item))
                        }
                    } header: {
                        Text(group.category.name)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                RebuildableFooter(
                    results: results, action: actions.confirmRebuildable,
                    help: Text("Review the totals before cleaning up the selected items."),
                    moveToTrash: actions.moveToTrash.map { moveToTrash in { review(with: moveToTrash) } })
            }
            .alert("Nothing was moved", isPresented: isRefused, presenting: refusal) { _ in
                Button("OK") {}
            } message: { refusal in
                Text(
                    "“\(URL(filePath: refusal.path).lastPathComponent)” didn't pass Shuck's safety checks, so Shuck moved nothing."
                )
            }
        }
    }

    /// The rows of one tier, the biggest first, as Large Files lists its files.
    private func rows(in tier: Tier) -> [ScanItem] {
        results.items.filter { $0.tier == tier }.sorted { $0.allocatedSize > $1.allocatedSize }
    }

    private var yourDataGroups: [(category: ItemCategory, rows: [ScanItem])] {
        let items = rows(in: .yourData)
        var categories: [ItemCategory] = []
        for item in items where !categories.contains(where: { $0.id == item.category.id }) {
            categories.append(item.category)
        }
        return categories.map { category in (category, items.filter { $0.category.id == category.id }) }
    }

    /// Opens the itemized review of the selected "Your data" rows. Nothing moves until the user confirms in it
    /// (SAF-002).
    private func review(with moveToTrash: MoveToTrash) {
        do throws(PlanError) {
            moveToTrash.review.wrappedValue = try moveToTrash.model.reviewMoveToTrash(
                moveToTrash.subTool, urls: results.selectedItems(in: .yourData).compactMap(\.url))
        } catch {
            // Private: the error names the item the plan stopped at (NFR-SEC-006).
            Logger.app.error("Refused a plan: \(String(describing: error), privacy: .private)")
            refusal = error
        }
    }

    private var isRefused: Binding<Bool> {
        Binding {
            refusal != nil
        } set: {
            if !$0 { refusal = nil }
        }
    }

    private func isSelected(_ item: ScanItem) -> Binding<Bool> {
        Binding {
            results.selection.contains(item.target)
        } set: { chosen in
            if chosen { results.selection.insert(item.target) } else { results.selection.remove(item.target) }
        }
    }
}

/// One row: a checkbox or the reason it has none, the name of a project or tool rule, why it is listed and its size.
/// A tool rule's row also shows the exact command that cleaning would run.
private struct ProjectRow: View {
    let item: ScanItem
    let home: URL
    let isSelected: Binding<Bool>

    var body: some View {
        HStack(spacing: 12) {
            SelectionMark(item: item, name: name, identifier: "project-\(name)", isSelected: isSelected)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                if let project = item.project {
                    // Two projects can share a name; the path Xcode recorded tells them apart (D-138).
                    let path = ResultRow.folder(of: project, home: home) + "/" + project.lastPathComponent
                    Text(verbatim: path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(Text(verbatim: path))
                        .textSelection(.enabled)
                }
                if let reason = item.selection.disabledReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(item.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if item.tier == .yourData {
                    // In words, not color alone: what this row is, and what choosing it does (SAF-002, NFR-A11Y-001).
                    Text("Your data. Shuck moves it to the Trash, and you can restore it from History.")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                if case .command(let command) = item.target {
                    // The exact command, as the review shows it (SAF-002).
                    Text(verbatim: command.commandLine)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            SizeText(target: item.target, bytes: item.allocatedSize)
        }
    }

    /// A project's name without Xcode's hash, a device support version with its platform, an archive's name without
    /// its extension, or a tool rule's name.
    private var name: String {
        guard let url = item.url else { return item.ruleMatch.map { String(localized: $0.rule.name) } ?? "" }
        if item.tier == .yourData { return url.deletingPathExtension().lastPathComponent }
        let device = DeviceSupportVersion.name(ofFolder: url)
        return device == url.lastPathComponent ? DerivedDataProject.name(ofFolder: device) : device
    }
}
