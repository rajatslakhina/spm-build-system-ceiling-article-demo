import Foundation

/// Checks a `ModuleGraph` against a `RuleSet` and reports every breach.
///
/// Results are fully deterministic: every traversal iterates name-sorted IDs,
/// so the same graph always produces the same list in the same order. That
/// matters more than it sounds — a linter whose output reorders between runs
/// produces noisy diffs and gets switched off within a month.
public enum GraphValidator {

    public static func validate(_ graph: ModuleGraph, against ruleSet: RuleSet) -> [Violation] {
        var violations: [Violation] = []

        for id in graph.duplicateIDs.sorted() {
            violations.append(
                Violation(
                    kind: .duplicateModule(id),
                    severity: .error,
                    message: "\(id) is declared more than once; later declarations were ignored."
                )
            )
        }

        for module in graph.modules.sorted(by: { $0.id < $1.id }) {
            let fromLayer = ruleSet.layer(named: module.layer)
            if fromLayer == nil {
                violations.append(
                    Violation(
                        kind: .unknownLayer(module: module.id, layer: module.layer),
                        severity: .warning,
                        message: "\(module.id) declares layer '\(module.layer)', which the rule set does not define."
                    )
                )
            }

            for dependency in module.dependencies.sorted() {
                if dependency == module.id {
                    violations.append(
                        Violation(
                            kind: .selfDependency(module.id),
                            severity: .error,
                            message: "\(module.id) imports itself."
                        )
                    )
                    continue
                }

                guard let target = graph.module(dependency) else {
                    violations.append(
                        Violation(
                            kind: .unresolvedDependency(from: module.id, to: dependency),
                            severity: .error,
                            message: "\(module.id) imports \(dependency), which is not in the graph."
                        )
                    )
                    continue
                }

                if let denied = ruleSet.deniedEdge(from: module.id, to: dependency) {
                    violations.append(
                        Violation(
                            kind: .deniedEdge(from: module.id, to: dependency, reason: denied.reason),
                            severity: .error,
                            message: "\(module.id) → \(dependency) is denied. \(denied.reason)"
                        )
                    )
                    continue
                }

                guard let fromLayer, let toRank = ruleSet.rank(ofLayer: target.layer) else { continue }

                if toRank > fromLayer.rank {
                    violations.append(
                        Violation(
                            kind: .layerInversion(
                                from: module.id, to: dependency,
                                fromLayer: module.layer, toLayer: target.layer
                            ),
                            severity: .error,
                            message: "\(module.id) (\(module.layer)) imports \(dependency) (\(target.layer)) — that points up the stack."
                        )
                    )
                } else if toRank == fromLayer.rank && !fromLayer.allowsSiblingImports {
                    violations.append(
                        Violation(
                            kind: .siblingImport(from: module.id, to: dependency, layer: module.layer),
                            severity: .warning,
                            message: "\(module.id) imports its \(module.layer) sibling \(dependency); that band forbids sideways imports."
                        )
                    )
                }
            }
        }

        violations.append(contentsOf: cycles(in: graph))

        return violations.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            if $0.ruleName != $1.ruleName { return $0.ruleName < $1.ruleName }
            return $0.message < $1.message
        }
    }

    // MARK: - Cycle detection

    /// Iterative depth-first search. Recursion is avoided on purpose: a real
    /// module graph parsed out of CI can be deeper than a comfortable stack,
    /// and a linter that crashes on the worst repository in the fleet is worse
    /// than no linter at all.
    ///
    /// The guarantee this gives you is *one reported cycle per back edge found
    /// in DFS order*, not the complete set of simple cycles — enumerating those
    /// is Johnson's algorithm and the count is exponential in the worst case.
    /// That is deliberately weaker than "every cycle in one pass", and the
    /// trade it buys is the one a build gate actually wants: at least one back
    /// edge in every strongly connected component is always reported, so a
    /// cyclic graph can never come back clean. You fix a cycle, you re-run, you
    /// get the next one. Self-imports are skipped here because
    /// `selfDependency` already covers them, and reporting `A → A` twice trains
    /// people to skim the output.
    static func cycles(in graph: ModuleGraph) -> [Violation] {
        struct Frame {
            let node: ModuleID
            let dependencies: [ModuleID]
            var next: Int
        }

        var settled: Set<ModuleID> = []
        var path: [ModuleID] = []
        var onPath: Set<ModuleID> = []
        var signatures: Set<String> = []
        var found: [[ModuleID]] = []

        func dependencies(of id: ModuleID) -> [ModuleID] {
            (graph.module(id)?.dependencies ?? []).sorted()
        }

        for root in graph.sortedIDs where !settled.contains(root) {
            var frames: [Frame] = [Frame(node: root, dependencies: dependencies(of: root), next: 0)]
            path.append(root)
            onPath.insert(root)

            while let frame = frames.last {
                guard frame.next < frame.dependencies.count else {
                    settled.insert(frame.node)
                    onPath.remove(frame.node)
                    if !path.isEmpty { path.removeLast() }
                    frames.removeLast()
                    continue
                }

                let dependency = frame.dependencies[frame.next]
                frames[frames.count - 1].next += 1

                guard graph.contains(dependency), dependency != frame.node else { continue }

                if onPath.contains(dependency) {
                    guard let start = path.firstIndex(of: dependency) else { continue }
                    let cycle = Array(path[start...])
                    let signature = canonicalSignature(cycle)
                    if signatures.insert(signature).inserted { found.append(cycle) }
                } else if !settled.contains(dependency) {
                    path.append(dependency)
                    onPath.insert(dependency)
                    frames.append(
                        Frame(node: dependency, dependencies: dependencies(of: dependency), next: 0)
                    )
                }
            }
        }

        return found
            .map { cycle in
                let rendered = (cycle + [cycle[0]]).map(\.name).joined(separator: " → ")
                return Violation(
                    kind: .cycle(path: cycle),
                    severity: .error,
                    message: "Dependency cycle: \(rendered)"
                )
            }
            .sorted { $0.message < $1.message }
    }

    /// Rotates a cycle so its alphabetically smallest member leads, so the same
    /// cycle reached from two different roots is only reported once.
    static func canonicalSignature(_ cycle: [ModuleID]) -> String {
        guard let pivot = cycle.indices.min(by: { cycle[$0] < cycle[$1] }) else { return "" }
        let rotated = Array(cycle[pivot...]) + Array(cycle[..<pivot])
        return rotated.map(\.name).joined(separator: "->")
    }
}
