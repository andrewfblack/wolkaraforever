import Foundation
import StikJIT

// Preparation only: there is no target PID, debugger attach, executable region,
// or guest-entry path here. A separate gate must be reviewed before adding any
// of those operations. Pairing bytes are never logged or retained.
@objc(TKJITFixtureHelper)
final class TKJITFixtureHelper: NSObject, NSExtensionRequestHandling {
    private let queue = DispatchQueue(label: "org.tolkara.jit-fixture-helper")

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let operation = item?.userInfo?["operation"] as? String
        let pairing = item?.userInfo?["pairing"] as? Data
        guard operation == "prepare", let pairing, !pairing.isEmpty, pairing.count <= 65536 else {
            respond("refused: invalid preparation request", to: context)
            return
        }
        queue.async { [self] in
            let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            let directory = library.appendingPathComponent("StikJIT", isDirectory: true)
            let temporary = library.appendingPathComponent("pairing-\(UUID().uuidString).plist")
            do {
                try pairing.write(to: temporary, options: [.atomic, .completeFileProtection])
                defer { try? FileManager.default.removeItem(at: temporary) }
                let result = TKJITPreparationProbe.prepare(pairingFile: temporary, helperLibrary: directory)
                switch result {
                case .ready: respond("device prepared; JIT not enabled", to: context)
                case .unreachable: respond("device unreachable; JIT not enabled", to: context)
                case .preparationFailed: respond("preparation failed; JIT not enabled", to: context)
                }
            } catch {
                respond("temporary pairing handoff failed; JIT not enabled", to: context)
            }
        }
    }

    private func respond(_ status: String, to context: NSExtensionContext) {
        let item = NSExtensionItem()
        item.userInfo = ["status": status]
        context.completeRequest(returningItems: [item])
    }
}
