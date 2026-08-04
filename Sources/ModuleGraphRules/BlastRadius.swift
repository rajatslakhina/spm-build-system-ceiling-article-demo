import Foundation

/// Answers the only build-time question that actually predicts CI pain:
/// *if I touch this module, how much of the graph has to be rebuilt?*
///
/// Incremental compilation — the thing SwiftPM already gives you for free —
/// only helps for the modules it can skip. Blast radius is the count it cannot
/// skip, and it is a property of your dependency shape, not of your build tool.
/// A module every feature transitively imports has a blast radius of 100%, and
/// no amount of caching makes an edit to it cheap for the person who made it.
public struct BlastRadius: Sendable {

    public struct Entry: Sendable, Hashable, Identifiable {
        public let module: ModuleID
        /// Modules that must be rebuilt after this one changes, including itself.
        public let rebuildCount: Int
        /// `rebuildCount` as a fraction of the whole graph, 0...1.
        public let share: Double

        public var id: ModuleID { module }

        public var percentLabel: String {
            "\(Int((share * 100).rounded()))%"
        }
    }

    private let graph: ModuleGraph
    private let dependents: [ModuleID: [ModuleID]]

    public init(graph: ModuleGraph) {
        self.graph = graph

        var dependents: [ModuleID: [ModuleID]] = [:]
        for module in graph.modules {
            for dependency in module.dependencies where graph.contains(dependency) {
                dependents[dependency, default: []].append(module.id)
            }
        }
        self.dependents = dependents.mapValues { $0.sorted() }
    }

    /// Breadth-first walk up the reverse edges. The `seen` set is what keeps a
    /// cyclic graph from spinning forever — cycles are a rule violation, but the
    /// metric still has to return a number when one is present.
    public func rebuildSet(after change: ModuleID) -> Set<ModuleID> {
        guard graph.contains(change) else { return [] }

        var seen: Set<ModuleID> = [change]
        var queue: [ModuleID] = [change]
        var head = 0

        while head < queue.count {
            let current = queue[head]
            head += 1
            for dependent in dependents[current] ?? [] where seen.insert(dependent).inserted {
                queue.append(dependent)
            }
        }
        return seen
    }

    public func entry(for module: ModuleID) -> Entry? {
        guard graph.contains(module) else { return nil }
        let count = rebuildSet(after: module).count
        let total = max(graph.moduleCount, 1)
        return Entry(module: module, rebuildCount: count, share: Double(count) / Double(total))
    }

    /// Every module, worst blast radius first, ties broken by name.
    public func report() -> [Entry] {
        graph.sortedIDs
            .compactMap(entry(for:))
            .sorted {
                $0.rebuildCount == $1.rebuildCount
                    ? $0.module < $1.module
                    : $0.rebuildCount > $1.rebuildCount
            }
    }

    /// Mean share across the graph. This is the single number worth putting on
    /// a dashboard: it moves when the *shape* improves, not when the hardware does.
    public var meanShare: Double {
        let entries = report()
        guard !entries.isEmpty else { return 0 }
        return entries.reduce(0) { $0 + $1.share } / Double(entries.count)
    }

    public var worst: Entry? { report().first }
}
