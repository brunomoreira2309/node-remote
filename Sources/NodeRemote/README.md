# Source notes

This folder holds the Swift code for Node Remote, the menu bar app. It supports **LG webOS** and **Samsung Tizen** TVs:

- `TVController.swift` defines the operations every brand implements.
- `WebOS.swift` and `WebOSController.swift` talk to LG TVs over SSAP.
- `Samsung.swift` talks to Samsung TVs over the local remote API and UPnP.
- `NodeTheme.swift` holds the visual identity used by `RemoteView.swift`.

The tested models are listed in the repository README. Other models and firmware versions may use different permissions, endpoints, or behavior. Please say which TV brand, model, and firmware version you tested when you open a pull request that changes how the app talks to the TV.
