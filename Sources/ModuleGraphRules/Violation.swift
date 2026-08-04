import Foundation

public enum Severity: Int, Sendable, Comparable, Codable {
    case warning = 0
    case error = 1

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .warning: return "warning"
        case .error: return "error"
        }
    }
}

/// A single rule breach found in a graph.
public struct Violation: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        /// A module declares a layer the rule set has never heard of.
        case unknownLayer(module: ModuleID, layer: String)
        /// An import points at a module that is not in the graph.
        case unresolvedDependency(from: ModuleID, to: ModuleID)
        /// A module imports itself.
        case selfDependency(ModuleID)
        /// An import points upward in the layer stack.
        case layerInversion(from: ModuleID, to: ModuleID, fromLayer: String, toLayer: String)
        /// Two modules in the same band import each other's internals.
        case siblingImport(from: ModuleID, to: ModuleID, layer: String)
        /// An edge the rule set names and forbids outright.
        case deniedEdge(from: ModuleID, to: ModuleID, reason: String)
        /// A cycle, reported once per cycle with its full path.
        case cycle(path: [ModuleID])
        /// The same module name declared twice.
        case duplicateModule(ModuleID)
    }

    public let kind: Kind
    public let severity: Severity
    public let message: String

    public var id: String { "\(severity.label):\(message)" }

    public init(kind: Kind, severity: Severity, message: String) {
        self.kind = kind
        self.severity = severity
        self.message = message
    }

    /// Short label used by the demo UI and by CI output grouping.
    public var ruleName: String {
        switch kind {
        case .unknownLayer: return "unknown-layer"
        case .unresolvedDependency: return "unresolved-dependency"
        case .selfDependency: return "self-dependency"
        case .layerInversion: return "layer-inversion"
        case .siblingImport: return "sibling-import"
        case .deniedEdge: return "denied-edge"
        case .cycle: return "dependency-cycle"
        case .duplicateModule: return "duplicate-module"
        }
    }
}

extension Array where Element == Violation {
    public var errorCount: Int { lazy.filter { $0.severity == .error }.count }
    public var warningCount: Int { lazy.filter { $0.severity == .warning }.count }
    /// What a CI step would exit with.
    public var failsBuild: Bool { errorCount > 0 }
}
