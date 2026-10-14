import Foundation

enum AppInfo {
    /// The one place the product name lives; the Samsung pairing prompt shows it too.
    static let name = "Node Remote"
}

enum AppResources {
    static let bundle: Bundle = {
        // Packaged apps use Contents/Resources; SwiftPM runs use its module bundle.
        if let resources = Bundle.main.resourceURL,
           let packaged = Bundle(url: resources.appendingPathComponent("NodeRemote_NodeRemote.bundle")) {
            return packaged
        }
        return Bundle.module
    }()
}
