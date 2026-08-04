import SwiftUI
import ModuleGraphRules

/// Entry point for the ModuleGraphRules demo. The whole UI lives in the
/// library's `RuleGuardDemoView` so the app target stays a thin shell — the
/// same shape you want in a real modular app, where the app target owns
/// lifecycle and nothing else.
@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            RuleGuardDemoView()
        }
    }
}
