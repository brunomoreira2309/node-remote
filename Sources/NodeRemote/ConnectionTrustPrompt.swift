import AppKit

enum ConnectionTrustPrompt {
    @MainActor static func confirm(host: String, fingerprint: String, brand: TVBrand) async -> Bool {
        let alert = NSAlert()
        alert.messageText = "Confiar nesta TV \(brand.displayName)?"
        alert.informativeText = "Conectar à TV em \(host) na sua rede local? Depois, aceite o pedido de pareamento nessa TV. A impressão digital do certificado dela será guardada nas Chaves deste Mac.\n\nSHA-256: \(fingerprint)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Confiar e parear")
        alert.addButton(withTitle: "Cancelar")
        NSApplication.shared.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
