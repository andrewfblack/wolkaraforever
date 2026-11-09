// Isolated compile-time probe for the helper's StikJIT API. Nothing in the
// installed app calls this yet; no pairing file is copied or device contacted.
import Foundation
import StikJIT

@available(iOS 17.4, *)
enum TKJITPreparationProbe {
    static func prepare(pairingFile: URL, helperLibrary: URL) -> StikJIT.JITReadiness {
        guard pairingFile.isFileURL, helperLibrary.isFileURL else {
            return .preparationFailed(reason: "The helper needs local pairing and cache files.")
        }
        do {
            try FileManager.default.createDirectory(at: helperLibrary, withIntermediateDirectories: true)
        } catch {
            return .preparationFailed(reason: "The helper could not create its private DDI cache.")
        }
        return StikJIT.prepareDevice(
            pairingFile: pairingFile,
            paths: DDIPaths.default(in: helperLibrary)
        )
    }
}
