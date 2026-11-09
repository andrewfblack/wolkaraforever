import Foundation
import StikJIT

// Two operations only: "prepare" verifies DDI readiness; "enable" attaches
// StikJIT to the requesting host process (its PID is supplied) and services it
// for the synthetic JIT gate. Nothing here launches a game or a guest. Pairing
// bytes are never logged or retained.
@objc(TKJITFixtureHelper)
final class TKJITFixtureHelper: NSObject, NSExtensionRequestHandling {
    private let queue = DispatchQueue(label: "org.tolkara.jit-fixture-helper")

    private static func readPairing(_ item: NSExtensionItem?) -> (String?, Data?, Int32?) {
        guard let operation = item?.userInfo?["operation"] as? String,
              let pairing = item?.userInfo?["pairing"] as? Data,
              !pairing.isEmpty, pairing.count <= 65536 else { return (nil, nil, nil) }
        let pid = (item?.userInfo?["targetPid"] as? NSNumber)?.int32Value
        return (operation, pairing, pid)
    }

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let (operation, pairing, targetPid) = Self.readPairing(item)
        guard let pairing else {
            respond("invalid pairing handoff; nothing ran", to: context); return
        }
        let enable = operation == "enable"
        if enable, targetPid == nil || targetPid! <= 0 {
            respond("enable needs the requesting PID; nothing ran", to: context); return
        }
        if operation != "prepare" && !enable {
            respond("unknown operation; nothing ran", to: context); return
        }
        queue.async { [self] in
            let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            let directory = library.appendingPathComponent("StikJIT", isDirectory: true)
            let temporary = library.appendingPathComponent("pairing-\(UUID().uuidString).plist")
            do {
                try pairing.write(to: temporary, options: [.atomic, .completeFileProtection])
                defer { try? FileManager.default.removeItem(at: temporary) }
                let paths = DDIPaths.default(in: directory)
                if enable {
                    try StikJIT.enableJIT(targetPID: targetPid!, pairingFile: temporary,
                                          ddiPaths: paths, script: .universal)
                    respond("enabled: JIT preparation detached or pending; run the self test", to: context)
                } else {
                    let result = StikJIT.prepareDevice(pairingFile: temporary, paths: paths)
                    switch result {
                    case .ready: respond("device prepared; JIT not enabled", to: context)
                    case .unreachable: respond("device unreachable; JIT not enabled", to: context)
                    case .preparationFailed: respond("preparation failed; JIT not enabled", to: context)
                    default: respond("preparation returned an unknown state; JIT not enabled", to: context)
                    }
                }
            } catch {
                respond(enable ? "enable failed; JIT was not enabled" : "preparation failed; JIT was not enabled",
                        to: context)
            }
        }
    }

    private func respond(_ status: String, to context: NSExtensionContext) {
        let item = NSExtensionItem()
        item.userInfo = ["status": status]
        context.completeRequest(returningItems: [item])
    }
}
