import XCTest
@testable import ModuleGraphRules

final class ModuleGraphRulesTests: XCTestCase {

    // MARK: - Rule detection

    func testLayerInversionIsAnError() {
        let graph = ModuleGraph(modules: [
            Module(id: "NetworkingCore", layer: "Foundation", dependencies: ["SessionDomain"]),
            Module(id: "SessionDomain", layer: "Domain")
        ])
        let violations = GraphValidator.validate(graph, against: .standard)

        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(violations.first?.ruleName, "layer-inversion")
        XCTAssertEqual(violations.first?.severity, .error)
        XCTAssertTrue(violations.failsBuild)
    }

    func testDownwardAndSiblingImportsAreCleanWhereTheBandAllowsThem() {
        let graph = ModuleGraph(modules: [
            Module(id: "SessionDomain", layer: "Domain", dependencies: ["AccountDomain", "NetworkingCore"]),
            Module(id: "AccountDomain", layer: "Domain", dependencies: ["NetworkingCore"]),
            Module(id: "NetworkingCore", layer: "Foundation")
        ])
        XCTAssertTrue(GraphValidator.validate(graph, against: .standard).isEmpty)
    }

    func testSiblingImportIsFlaggedInBandsThatForbidIt() {
        let graph = ModuleGraph(modules: [
            Module(id: "CheckoutFeature", layer: "Feature", dependencies: ["CatalogFeature"]),
            Module(id: "CatalogFeature", layer: "Feature")
        ])
        let violations = GraphValidator.validate(graph, against: .standard)

        XCTAssertEqual(violations.map(\.ruleName), ["sibling-import"])
        XCTAssertEqual(violations.first?.severity, .warning)
        XCTAssertFalse(violations.failsBuild, "A sideways feature import warns; it does not stop the build.")
    }

    func testDeniedEdgeBeatsAnOtherwiseLegalDownwardImport() {
        // PaymentsFeature → AnalyticsCore points *down* the stack and would pass
        // the generic band rules. The named deny is what catches it.
        let graph = ModuleGraph(modules: [
            Module(id: "PaymentsFeature", layer: "Feature", dependencies: ["AnalyticsCore"]),
            Module(id: "AnalyticsCore", layer: "Foundation")
        ])
        let violations = GraphValidator.validate(graph, against: .standard)

        XCTAssertEqual(violations.map(\.ruleName), ["denied-edge"])
        XCTAssertTrue(violations[0].message.contains("route through PaymentsDomain"))
    }

    func testUnresolvedAndSelfDependencies() {
        let graph = ModuleGraph(modules: [
            Module(id: "A", layer: "Domain", dependencies: ["A", "GhostModule"])
        ])
        let names = Set(GraphValidator.validate(graph, against: .standard).map(\.ruleName))
        XCTAssertEqual(names, ["self-dependency", "unresolved-dependency"])
    }

    func testUnknownLayerWarnsWithoutSuppressingOtherRules() {
        let graph = ModuleGraph(modules: [
            Module(id: "Mystery", layer: "Experimental", dependencies: ["Ghost"])
        ])
        let names = GraphValidator.validate(graph, against: .standard).map(\.ruleName)
        XCTAssertEqual(names.sorted(), ["unknown-layer", "unresolved-dependency"])
    }

    func testDuplicateModuleNamesAreReportedNotSilentlyDropped() {
        let graph = ModuleGraph(modules: [
            Module(id: "Dup", layer: "Domain"),
            Module(id: "Dup", layer: "Feature", dependencies: ["Ghost"])
        ])
        XCTAssertEqual(graph.moduleCount, 1)
        XCTAssertEqual(graph.duplicateIDs, ["Dup"])
        XCTAssertEqual(GraphValidator.validate(graph, against: .standard).map(\.ruleName), ["duplicate-module"])
    }

    // MARK: - Cycles

    func testTwoNodeCycleIsReportedOnceNotTwice() {
        let graph = ModuleGraph(modules: [
            Module(id: "A", layer: "Domain", dependencies: ["B"]),
            Module(id: "B", layer: "Domain", dependencies: ["A"])
        ])
        let cycles = GraphValidator.validate(graph, against: .standard).filter { $0.ruleName == "dependency-cycle" }
        XCTAssertEqual(cycles.count, 1)
        XCTAssertEqual(cycles[0].message, "Dependency cycle: A → B → A")
    }

    func testThreeNodeCycleIsReportedOnceInCanonicalOrder() {
        let graph = ModuleGraph(modules: [
            Module(id: "C", layer: "Domain", dependencies: ["A"]),
            Module(id: "A", layer: "Domain", dependencies: ["B"]),
            Module(id: "B", layer: "Domain", dependencies: ["C"])
        ])
        let cycles = GraphValidator.validate(graph, against: .standard).filter { $0.ruleName == "dependency-cycle" }
        XCTAssertEqual(cycles.count, 1)
        XCTAssertEqual(cycles[0].message, "Dependency cycle: A → B → C → A")
    }

    func testAcyclicDiamondIsNotACycle() {
        let graph = ModuleGraph(modules: [
            Module(id: "Top", layer: "Feature", dependencies: ["Left", "Right"]),
            Module(id: "Left", layer: "Domain", dependencies: ["Base"]),
            Module(id: "Right", layer: "Domain", dependencies: ["Base"]),
            Module(id: "Base", layer: "Foundation")
        ])
        XCTAssertTrue(GraphValidator.validate(graph, against: .standard).isEmpty)
    }

    func testCanonicalSignatureIsRotationInvariant() {
        XCTAssertEqual(
            GraphValidator.canonicalSignature(["B", "C", "A"]),
            GraphValidator.canonicalSignature(["A", "B", "C"])
        )
        XCTAssertEqual(GraphValidator.canonicalSignature([]), "")
    }

    // MARK: - Blast radius

    func testBlastRadiusCountsTransitiveDependentsIncludingItself() {
        let graph = ModuleGraph(modules: [
            Module(id: "Base", layer: "Foundation"),
            Module(id: "Mid", layer: "Domain", dependencies: ["Base"]),
            Module(id: "Leaf", layer: "Feature", dependencies: ["Mid"]),
            Module(id: "Detached", layer: "Feature")
        ])
        let radius = BlastRadius(graph: graph)

        XCTAssertEqual(radius.rebuildSet(after: "Base"), ["Base", "Mid", "Leaf"])
        XCTAssertEqual(radius.entry(for: "Base")?.rebuildCount, 3)
        XCTAssertEqual(radius.entry(for: "Base")?.percentLabel, "75%")
        XCTAssertEqual(radius.entry(for: "Leaf")?.rebuildCount, 1)
        XCTAssertEqual(radius.worst?.module, "Base")
    }

    func testBlastRadiusTerminatesOnACyclicGraph() {
        let graph = ModuleGraph(modules: [
            Module(id: "A", layer: "Domain", dependencies: ["B"]),
            Module(id: "B", layer: "Domain", dependencies: ["A"])
        ])
        XCTAssertEqual(BlastRadius(graph: graph).rebuildSet(after: "A"), ["A", "B"])
    }

    func testUnknownModuleHasNoBlastRadius() {
        let radius = BlastRadius(graph: SampleGraphs.asShipped)
        XCTAssertTrue(radius.rebuildSet(after: "NotAModule").isEmpty)
        XCTAssertNil(radius.entry(for: "NotAModule"))
    }

    func testEmptyGraphIsClean() {
        let graph = ModuleGraph(modules: [])
        XCTAssertTrue(GraphValidator.validate(graph, against: .standard).isEmpty)
        XCTAssertEqual(BlastRadius(graph: graph).meanShare, 0)
        XCTAssertNil(BlastRadius(graph: graph).worst)
    }

    // MARK: - The bundled sample

    func testSampleGraphShape() {
        XCTAssertEqual(SampleGraphs.asShipped.moduleCount, 16)
        XCTAssertEqual(SampleGraphs.remediated.moduleCount, 16)
        XCTAssertEqual(SampleGraphs.asShipped.edgeCount, 39)
        XCTAssertEqual(SampleGraphs.remediated.edgeCount, 36)
    }

    func testAsShippedFailsWithTheFourEdgesWeExpect() {
        let audit = GraphAudit.asShipped
        XCTAssertTrue(audit.failsBuild)

        let byRule = Dictionary(grouping: audit.violations, by: \.ruleName).mapValues(\.count)
        XCTAssertEqual(byRule["layer-inversion"], 1)
        XCTAssertEqual(byRule["denied-edge"], 1)
        XCTAssertEqual(byRule["sibling-import"], 1)
        XCTAssertEqual(byRule["dependency-cycle"], 2)
        XCTAssertEqual(audit.errorCount, 4)
        XCTAssertEqual(audit.warningCount, 1)
    }

    /// The detector reports one cycle per back edge, not every simple cycle.
    /// What it must never do is let a cyclic graph come back clean. For the
    /// bundled sample, every module that sits in a cycle is named in one.
    func testEveryCyclicModuleInTheSampleAppearsInSomeReportedCycle() {
        let reported = GraphAudit.asShipped.violations.reduce(into: Set<ModuleID>()) { set, violation in
            if case .cycle(let path) = violation.kind { set.formUnion(path) }
        }
        XCTAssertEqual(reported, ["AccountDomain", "NetworkingCore", "SessionDomain"])
    }

    func testRemediatedGraphIsClean() {
        let audit = GraphAudit.remediated
        XCTAssertTrue(audit.violations.isEmpty, "Unexpected: \(audit.violations.map(\.message))")
        XCTAssertFalse(audit.failsBuild)
    }

    func testReroutingFourEdgesShrinksTheBlastRadius() {
        let before = GraphAudit.asShipped.blastRadius
        let after = GraphAudit.remediated.blastRadius

        XCTAssertEqual(before.entry(for: "SessionDomain")?.rebuildCount, 12)
        XCTAssertEqual(after.entry(for: "SessionDomain")?.rebuildCount, 6)
        XCTAssertLessThan(after.meanShare, before.meanShare)
    }

    func testEveryViolationRendersAHumanReadableMessage() {
        for violation in GraphAudit.asShipped.violations {
            XCTAssertFalse(violation.message.isEmpty)
            XCTAssertFalse(violation.ruleName.isEmpty)
        }
    }
}
