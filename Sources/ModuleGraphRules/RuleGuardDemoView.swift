#if canImport(SwiftUI)
import SwiftUI

/// The demo app's root view. It audits the bundled sixteen-module sample graph
/// against `RuleSet.standard` and shows the two things a `Package.swift` cannot
/// tell you: which imports break the agreed policy, and how much of the graph
/// each module drags into a rebuild.
public struct RuleGuardDemoView: View {
    private let audits: [GraphAudit]
    @State private var selection: Int = 0

    public init(audits: [GraphAudit]? = nil) {
        self.audits = audits ?? [.asShipped, .remediated]
    }

    private var audit: GraphAudit {
        guard audits.indices.contains(selection), !audits.isEmpty else {
            return GraphAudit(title: "Empty", graph: ModuleGraph(modules: []))
        }
        return audits[selection]
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    picker
                    verdict
                    scoreboard
                    violationsSection
                    blastRadiusSection
                }
                .padding(20)
            }
            .background(Color(white: 0.96))
            .navigationTitle("Module Graph Rules")
        }
    }

    // MARK: - Pieces

    private var picker: some View {
        Picker("Graph", selection: $selection) {
            ForEach(Array(audits.enumerated()), id: \.offset) { index, item in
                Text(item.title).tag(index)
            }
        }
        .pickerStyle(.segmented)
    }

    private var verdict: some View {
        HStack(spacing: 12) {
            Image(systemName: audit.failsBuild ? "xmark.octagon.fill" : "checkmark.seal.fill")
                .font(.system(size: 28))
                .foregroundStyle(audit.failsBuild ? Color.red : Color.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(audit.failsBuild ? "CI would fail this graph" : "CI would pass this graph")
                    .font(.headline)
                Text(audit.failsBuild
                     ? "\(audit.errorCount) errors, \(audit.warningCount) warnings"
                     : "No policy breaches in \(audit.graph.edgeCount) import edges")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
    }

    private var scoreboard: some View {
        HStack(spacing: 12) {
            stat("\(audit.graph.moduleCount)", "modules")
            stat("\(audit.graph.edgeCount)", "edges")
            stat(audit.meanShareLabel, "mean rebuild")
            stat(audit.blastRadius.worst?.percentLabel ?? "—", "worst module")
        }
    }

    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
    }

    @ViewBuilder
    private var violationsSection: some View {
        section("Policy breaches") {
            if audit.violations.isEmpty {
                Text("Every import points down the stack or sideways where the band allows it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(audit.violations, id: \.self) { violation in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(violation.severity.label.uppercased())
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(
                                    Capsule().fill(violation.severity == .error
                                                   ? Color.red.opacity(0.15)
                                                   : Color.orange.opacity(0.2))
                                )
                                .foregroundStyle(violation.severity == .error ? Color.red : Color.orange)
                            Text(violation.ruleName)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Text(violation.message).font(.subheadline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    Divider()
                }
            }
        }
    }

    private var blastRadiusSection: some View {
        section("Blast radius — modules rebuilt when this one changes") {
            ForEach(audit.blastRadius.report().prefix(6), id: \.module) { entry in
                HStack(spacing: 10) {
                    Text(entry.module.name)
                        .font(.caption.monospaced())
                        .frame(width: 118, alignment: .leading)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.gray.opacity(0.15))
                            Capsule()
                                .fill(entry.share > 0.5 ? Color.red.opacity(0.65) : Color.blue.opacity(0.6))
                                .frame(width: max(6, geometry.size.width * entry.share))
                        }
                    }
                    .frame(height: 14)
                    Text("\(entry.rebuildCount)")
                        .font(.caption.monospacedDigit())
                        .frame(width: 24, alignment: .trailing)
                    Text(entry.percentLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
                .padding(.vertical, 5)
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
        }
    }
}

#Preview {
    RuleGuardDemoView()
}
#endif
