import Foundation

/// A module's name, used as its identity in the dependency graph.
public struct ModuleID: Hashable, Sendable, Comparable, CustomStringConvertible,
                        ExpressibleByStringLiteral, Codable {
    public let name: String

    public init(_ name: String) { self.name = name }
    public init(stringLiteral value: StringLiteralType) { self.name = value }

    public var description: String { name }

    public static func < (lhs: ModuleID, rhs: ModuleID) -> Bool { lhs.name < rhs.name }
}

/// One horizontal band of the architecture.
///
/// `rank` orders the bands: a module may depend downward onto a strictly lower
/// rank. Whether it may also depend *sideways*, onto a module in its own band,
/// is a per-band decision — most teams let domain modules compose freely and
/// ban it outright between feature modules.
public struct Layer: Hashable, Sendable, Codable {
    public let name: String
    public let rank: Int
    public let allowsSiblingImports: Bool

    public init(name: String, rank: Int, allowsSiblingImports: Bool = false) {
        self.name = name
        self.rank = rank
        self.allowsSiblingImports = allowsSiblingImports
    }
}

/// A single node in the dependency graph: a module, the band it belongs to,
/// and the modules it imports.
public struct Module: Hashable, Sendable, Identifiable, Codable {
    public let id: ModuleID
    public let layer: String
    public let dependencies: [ModuleID]

    public init(id: ModuleID, layer: String, dependencies: [ModuleID] = []) {
        self.id = id
        self.layer = layer
        self.dependencies = dependencies
    }
}

/// An immutable dependency graph with an O(1) name lookup built once at init.
///
/// Duplicate module names collapse to the first declaration; `duplicateIDs`
/// records the collisions so the validator can report them rather than silently
/// dropping a node.
public struct ModuleGraph: Sendable {
    public let modules: [Module]
    public let duplicateIDs: [ModuleID]

    private let index: [ModuleID: Module]

    public init(modules: [Module]) {
        var index: [ModuleID: Module] = [:]
        var ordered: [Module] = []
        var duplicates: [ModuleID] = []
        index.reserveCapacity(modules.count)
        ordered.reserveCapacity(modules.count)

        for module in modules {
            if index[module.id] == nil {
                index[module.id] = module
                ordered.append(module)
            } else {
                duplicates.append(module.id)
            }
        }

        self.modules = ordered
        self.index = index
        self.duplicateIDs = duplicates
    }

    public var moduleCount: Int { modules.count }

    /// Total declared import edges, including any that point at unknown modules.
    public var edgeCount: Int { modules.reduce(0) { $0 + $1.dependencies.count } }

    /// Module IDs in a stable, name-sorted order. Every traversal in this
    /// package starts here so results never depend on declaration order.
    public var sortedIDs: [ModuleID] { modules.map(\.id).sorted() }

    public func module(_ id: ModuleID) -> Module? { index[id] }

    public func contains(_ id: ModuleID) -> Bool { index[id] != nil }

    /// Every module that directly imports `id`.
    public func directDependents(of id: ModuleID) -> [ModuleID] {
        modules.filter { $0.dependencies.contains(id) }.map(\.id).sorted()
    }

    /// Returns a copy with `id`'s import list replaced. Unknown IDs are a no-op.
    public func replacingDependencies(of id: ModuleID, with dependencies: [ModuleID]) -> ModuleGraph {
        guard contains(id) else { return self }
        let rewritten = modules.map { module -> Module in
            guard module.id == id else { return module }
            return Module(id: module.id, layer: module.layer, dependencies: dependencies)
        }
        return ModuleGraph(modules: rewritten)
    }
}
