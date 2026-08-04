import Foundation

/// Two snapshots of the same sixteen-module app: the graph as it drifted, and
/// the graph after the four edges that broke policy were rerouted.
///
/// The module names are generic on purpose. The *shape* is not — a foundation
/// module reaching up for a session token, a feature importing a sibling feature
/// to reuse one view, and analytics wired straight into the payments screen are
/// the three edges that show up in almost every codebase that grew past ten
/// modules without anything enforcing the boundaries.
public enum SampleGraphs {

    /// The graph as it exists at the point somebody finally draws it on a whiteboard.
    public static let asShipped = ModuleGraph(modules: [
        // Foundation
        Module(id: "CoreUtilities", layer: "Foundation"),
        Module(id: "AnalyticsCore", layer: "Foundation", dependencies: ["CoreUtilities"]),
        Module(id: "NetworkingCore", layer: "Foundation",
               dependencies: ["CoreUtilities", "SessionDomain"]),

        // Platform
        Module(id: "DesignSystem", layer: "Platform", dependencies: ["CoreUtilities"]),
        Module(id: "PersistenceKit", layer: "Platform", dependencies: ["CoreUtilities"]),
        Module(id: "FeatureFlags", layer: "Platform",
               dependencies: ["CoreUtilities", "NetworkingCore"]),

        // Domain
        Module(id: "SessionDomain", layer: "Domain",
               dependencies: ["NetworkingCore", "PersistenceKit", "AccountDomain"]),
        Module(id: "AccountDomain", layer: "Domain",
               dependencies: ["NetworkingCore", "PersistenceKit", "SessionDomain"]),
        Module(id: "CatalogDomain", layer: "Domain",
               dependencies: ["NetworkingCore", "PersistenceKit"]),
        Module(id: "PaymentsDomain", layer: "Domain",
               dependencies: ["NetworkingCore", "AnalyticsCore", "SessionDomain"]),

        // Feature
        Module(id: "OnboardingFeature", layer: "Feature",
               dependencies: ["DesignSystem", "AccountDomain", "FeatureFlags"]),
        Module(id: "CatalogFeature", layer: "Feature",
               dependencies: ["DesignSystem", "CatalogDomain", "FeatureFlags"]),
        Module(id: "CheckoutFeature", layer: "Feature",
               dependencies: ["DesignSystem", "PaymentsDomain", "CatalogFeature"]),
        Module(id: "PaymentsFeature", layer: "Feature",
               dependencies: ["DesignSystem", "PaymentsDomain", "AnalyticsCore"]),
        Module(id: "ProfileFeature", layer: "Feature",
               dependencies: ["DesignSystem", "AccountDomain", "SessionDomain"]),

        // App
        Module(id: "AppShell", layer: "App",
               dependencies: ["OnboardingFeature", "CatalogFeature", "CheckoutFeature",
                              "PaymentsFeature", "ProfileFeature", "FeatureFlags"])
    ])

    /// The same sixteen modules after four edges are rerouted:
    ///
    /// 1. `NetworkingCore` stops importing `SessionDomain` — the token becomes a
    ///    protocol that `NetworkingCore` owns and `SessionDomain` conforms to.
    /// 2. `AccountDomain` stops importing `SessionDomain`, breaking the cycle.
    /// 3. `CheckoutFeature` reaches for `CatalogDomain` instead of `CatalogFeature`.
    /// 4. `PaymentsFeature` emits analytics through `PaymentsDomain`.
    ///
    /// No module was added and no module was deleted. The only thing that changed
    /// is which arrows exist, which is exactly the point.
    public static let remediated = ModuleGraph(modules: [
        Module(id: "CoreUtilities", layer: "Foundation"),
        Module(id: "AnalyticsCore", layer: "Foundation", dependencies: ["CoreUtilities"]),
        Module(id: "NetworkingCore", layer: "Foundation", dependencies: ["CoreUtilities"]),

        Module(id: "DesignSystem", layer: "Platform", dependencies: ["CoreUtilities"]),
        Module(id: "PersistenceKit", layer: "Platform", dependencies: ["CoreUtilities"]),
        Module(id: "FeatureFlags", layer: "Platform",
               dependencies: ["CoreUtilities", "NetworkingCore"]),

        Module(id: "SessionDomain", layer: "Domain",
               dependencies: ["NetworkingCore", "PersistenceKit", "AccountDomain"]),
        Module(id: "AccountDomain", layer: "Domain",
               dependencies: ["NetworkingCore", "PersistenceKit"]),
        Module(id: "CatalogDomain", layer: "Domain",
               dependencies: ["NetworkingCore", "PersistenceKit"]),
        Module(id: "PaymentsDomain", layer: "Domain",
               dependencies: ["NetworkingCore", "AnalyticsCore", "SessionDomain"]),

        Module(id: "OnboardingFeature", layer: "Feature",
               dependencies: ["DesignSystem", "AccountDomain", "FeatureFlags"]),
        Module(id: "CatalogFeature", layer: "Feature",
               dependencies: ["DesignSystem", "CatalogDomain", "FeatureFlags"]),
        Module(id: "CheckoutFeature", layer: "Feature",
               dependencies: ["DesignSystem", "PaymentsDomain", "CatalogDomain"]),
        Module(id: "PaymentsFeature", layer: "Feature",
               dependencies: ["DesignSystem", "PaymentsDomain"]),
        Module(id: "ProfileFeature", layer: "Feature",
               dependencies: ["DesignSystem", "AccountDomain", "SessionDomain"]),

        Module(id: "AppShell", layer: "App",
               dependencies: ["OnboardingFeature", "CatalogFeature", "CheckoutFeature",
                              "PaymentsFeature", "ProfileFeature", "FeatureFlags"])
    ])
}

/// One graph, its violations and its blast-radius table, computed once.
public struct GraphAudit: Sendable {
    public let title: String
    public let graph: ModuleGraph
    public let violations: [Violation]
    public let blastRadius: BlastRadius

    public init(title: String, graph: ModuleGraph, ruleSet: RuleSet = .standard) {
        self.title = title
        self.graph = graph
        self.violations = GraphValidator.validate(graph, against: ruleSet)
        self.blastRadius = BlastRadius(graph: graph)
    }

    public var errorCount: Int { violations.errorCount }
    public var warningCount: Int { violations.warningCount }
    public var failsBuild: Bool { violations.failsBuild }

    public var meanShareLabel: String {
        "\(Int((blastRadius.meanShare * 100).rounded()))%"
    }

    public static var asShipped: GraphAudit {
        GraphAudit(title: "As shipped", graph: SampleGraphs.asShipped)
    }

    public static var remediated: GraphAudit {
        GraphAudit(title: "After four edges move", graph: SampleGraphs.remediated)
    }
}
