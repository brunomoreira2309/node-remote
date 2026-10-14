import AppKit
import Carbon.HIToolbox

/// Keys that drive the TV while the panel is open and no text field is being edited.
enum RemoteShortcut: Equatable {
    case key(RemoteKey), ok, playPause, volume(up: Bool), mute

    static func action(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags) -> RemoteShortcut? {
        // Leave ⌘/⌃/⌥ combinations to the system and the app's menus.
        guard modifiers.intersection([.command, .control, .option]).isEmpty else { return nil }
        switch Int(keyCode) {
        case kVK_UpArrow: return .key(.up)
        case kVK_DownArrow: return .key(.down)
        case kVK_LeftArrow: return .key(.left)
        case kVK_RightArrow: return .key(.right)
        case kVK_Return, kVK_ANSI_KeypadEnter: return .ok
        case kVK_Delete: return .key(.back)
        case kVK_Space: return .playPause
        default: break
        }
        switch characters?.lowercased() {
        case "+", "=": return .volume(up: true)
        case "-", "_": return .volume(up: false)
        case "m": return .mute
        case "h": return .key(.home)
        default: return nil
        }
    }
}

/// One system-wide hotkey (⌃⌥T) that opens or closes the panel. Carbon hotkeys need no
/// Accessibility permission and never observe other keystrokes.
final class GlobalHotKey {
    static let label = "⌃⌥T"
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    init?(action: @escaping () -> Void) {
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { hotKey.action() }
            return noErr
        }, 1, &type, context, &handler) == noErr else { return nil }
        let id = EventHotKeyID(signature: OSType(0x5456_524D), id: 1) // "TVRM"
        guard RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &reference) == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }
    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
