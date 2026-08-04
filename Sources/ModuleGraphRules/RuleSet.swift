import Foundation

/// An explicitly forbidden edge, with the reason a reviewer will read in CI.
public struct DeniedEdge: Hashable, Sendable, Codable {
    public let from: ModuleID
    public let to: ModuleID
    public let reason: String

    public init(from: ModuleID, to: ModuleID, reason: String) {
        self.from = from
        self.to = to
        self.reason = reason
    }
}

/// The dependency policy a team agrees to and CI enforces.
///
/// This is the artefact Swift Package Manager has nowhere to put. `Package.swift`
/// expresses *what a target depends on*. It has no vocabulary for *what a target
/// is forbidden from depending on* — and that second half is the one that decays
/// once more than a handful of people are opening pull requests.
public struct RuleSet: Sendable {
    /// Bands of the architecture, lowest rank first.
    public let layers: [Layer]
    /// Named forbidden edges that survive the generic band rules.
    public let deniedEdges: [DeniedEdge]

    private let byName: [String: Layer]

    public init(layers: [Layer], deniedEdges: [DeniedEdge] = []) {
        self.layers = layers.sorted { $0.rank < $1.rank }
        self.deniedEdges = deniedEdges

        var byName: [String: Layer] = [:]
        for layer in layers where byName[layer.name] == nil {
            byName[layer.name] = layer
        }
        self.byName = byName
    }

    public func layer(named name: String) -> Layer? { byName[name] }

    public func rank(ofLayer name: String) -> Int? { byName[name]?.rank }

    public func deniedEdge(from: ModuleID, to: ModuleID) -> DeniedEdge? {
        deniedEdges.first { $0.from == from && $0.to == to }
    }

    /// The five-band policy the bundled sample graph is measured against.
    ///
    /// Domain modules may compose with each other; feature modules may not,
    /// because a feature importing another feature is how a codebase quietly
    /// turns back into one module wearing sixteen hats.
    public static let standard = RuleSet(
        layers: [
            Layer(name: "Foundation", rank: 0, allowsSiblingImports: true),
            Layer(name: "Platform", rank: 1, allowsSiblingImports: true),
            Layer(name: "Domain", rank: 2, allowsSiblingImports: true),
            Layer(name: "Feature", rank: 3, allowsSiblingImports: false),
            Layer(name: "App", rank: 4, allowsSiblingImports: false)
        ],
        deniedEdges: [
            DeniedEdge(
                from: "PaymentsFeature",
                to: "AnalyticsCore",
                reason: "Payments may not emit analytics directly — route through PaymentsDomain."
            )
        ]
    )
}
