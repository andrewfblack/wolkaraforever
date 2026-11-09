import Foundation

// A compile-only extension fixture. No app launches it and it deliberately
// rejects all requests until the host-side pairing and readiness gates exist.
@objc(TKJITFixtureHelper)
final class TKJITFixtureHelper: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let response = NSExtensionItem()
        response.userInfo = ["status": "not configured"]
        context.completeRequest(returningItems: [response])
    }
}
