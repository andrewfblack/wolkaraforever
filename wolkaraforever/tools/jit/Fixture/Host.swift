import UIKit
import UniformTypeIdentifiers
import Darwin

// Isolated synthetic StikJIT gate; no game executable is loaded or executed.
// no pairing file, no guest executable and no JIT activation path.
@main
final class TKJITFixtureHost: UIResponder, UIApplicationDelegate, UIDocumentPickerDelegate {
    var window: UIWindow?
    private let status = UILabel()

    private var pairingFile: URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return documents.appendingPathComponent("StikJIT", isDirectory: true).appendingPathComponent("pairingFile.plist")
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let controller = UIViewController()
        let label = UILabel(frame: controller.view.bounds)
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = "StikJIT test host. No game code is committed to or executed by this app."
        controller.view.backgroundColor = .systemBackground
        controller.view.addSubview(label)
        let importButton = UIButton(type: .system)
        importButton.setTitle("Import this device's pairing file", for: .normal)
        importButton.addTarget(self, action: #selector(importPairingFile), for: .touchUpInside)
        importButton.frame = CGRect(x: 20, y: 120, width: controller.view.bounds.width - 40, height: 52)
        importButton.autoresizingMask = [.flexibleWidth]
        controller.view.addSubview(importButton)
        status.frame = CGRect(x: 20, y: 180, width: controller.view.bounds.width - 40, height: 80)
        status.autoresizingMask = [.flexibleWidth]
        status.textAlignment = .center
        status.numberOfLines = 0
        status.text = pairingFile.map { FileManager.default.fileExists(atPath: $0.path) } == true ?
            "A pairing file is stored. JIT is still disabled." : "No pairing file imported."
        controller.view.addSubview(status)
        let prepareButton = UIButton(type: .system)
        prepareButton.setTitle("Check DDI setup (no JIT)", for: .normal)
        prepareButton.addTarget(self, action: #selector(prepareDevice), for: .touchUpInside)
        prepareButton.frame = CGRect(x: 20, y: 280, width: controller.view.bounds.width - 40, height: 52)
        prepareButton.autoresizingMask = [.flexibleWidth]
        controller.view.addSubview(prepareButton)
        let enableButton = UIButton(type: .system)
        enableButton.setTitle("Enable JIT and run arena self-test", for: .normal)
        enableButton.addTarget(self, action: #selector(enableJIT), for: .touchUpInside)
        enableButton.frame = CGRect(x: 20, y: 336, width: controller.view.bounds.width - 40, height: 52)
        enableButton.autoresizingMask = [.flexibleWidth]
        controller.view.addSubview(enableButton)
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = controller
        window?.makeKeyAndVisible()
        return true
    }

    @objc private func importPairingFile() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.propertyList], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        window?.rootViewController?.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let source = urls.first, source.isFileURL, let destination = pairingFile,
              source.startAccessingSecurityScopedResource() else {
            status.text = "Pairing import refused: no scoped file access."
            return
        }
        defer { source.stopAccessingSecurityScopedResource() }
        do {
            let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true,
                  let size = values.fileSize, size > 0, size <= 65536 else {
                status.text = "Pairing import refused: expected a small, regular file."
                return
            }
            let bytes = try Data(contentsOf: source)
            guard bytes.count == size else {
                status.text = "Pairing import refused: the file changed while reading it."
                return
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
            try bytes.write(to: destination, options: [.atomic, .completeFileProtection])
            status.text = "Pairing file imported locally. JIT is still disabled."
        } catch {
            // Never display an NSError description: a file provider may put
            // private paths or pairing material in it.
            status.text = "Pairing import failed; no JIT request was sent."
        }
    }

    @objc private func enableJIT() {
        guard let pairing = readPairing() else {
            status.text = "Import a valid pairing file for this device first."
            return
        }
        status.text = "Requesting JIT preparation for this process…"
        TKJITStartOperation("enable", pairing, getpid()) { [weak self] result in
            guard let self else { return }
            status.text = result + "\nWaiting for the helper to release the debugger…"
            // The helper attaches for enable; the self test drives the brk protocol and
            // then asks the helper to detach. All local to this process; no game code.
            var report = [CChar](repeating: 0, count: 1024)
            let length = report.withUnsafeMutableBufferPointer { buffer in
                TKJITSelfTest(buffer.baseAddress, buffer.count)
            }
            let text = String(decoding: report.prefix(length == 0 ? 0 : Int(length)), as: UTF8.self)
            status.text = text
        }
    }

    private func readPairing() -> NSData? {
        guard let source = pairingFile,
              let attributes = try? FileManager.default.attributesOfItem(atPath: source.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? Int, size > 0, size <= 65536,
              let bytes = try? Data(contentsOf: source), bytes.count == size else { return nil }
        return bytes as NSData
    }

    @objc private func prepareDevice() {
        guard let pairing = readPairing() else {
            status.text = "Import a valid pairing file for this device first."
            return
        }
        status.text = "Checking the device; JIT and game launch remain disabled."
        TKJITStartOperation("prepare", pairing, 0) { [weak self] result in
            self?.status.text = result
        }
    }
}
