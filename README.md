# Node Remote

A native macOS menu bar remote for LG webOS and Samsung Tizen TVs, made by **Node**.

Node Remote puts your TV a click away: navigate with the keyboard, open apps, adjust the volume, run scenes, set a sleep timer, and switch between the TVs in your home. Everything runs on your local network, with no accounts and no cloud.

Node Remote is an independent project. It is not affiliated with or endorsed by LG or Samsung.

## Features

- **Remote control:** directional pad, OK, back, home, menu, channels, and playback keys.
- **Mac keyboard as a remote:** arrows navigate, ↩ is OK, ⌫ goes back, space plays or pauses, + and − change the volume, M mutes, H goes home. Press **⌃⌥T** anywhere to open or close the panel.
- **Several TVs:** every TV you connect is saved. Switch between them from the TV name at the top of the panel. Each TV keeps its own pairing.
- **Apps:** open apps, mark favorites, and see which app is on screen.
- **Volume:** a live volume level and mute state on both brands.
- **Sleep timer:** turn the TV off in 15 minutes to 2 hours, with a countdown in the panel and in the menu bar.
- **Scenes:** one click to open an app, set the volume, start the timer, turn the TV off, or (on LG) change the picture mode. A scene made on one TV also runs on the other brand.
- **Routines:** schedule any scene by time and weekday ("weekdays at 7:00, YouTube at volume 15", "every day at 23:30, turn off"). If a routine turns things on, the app wakes the TV over the network first.
- **Calls lower the TV:** when any app starts using the Mac's microphone (Meet, Zoom, FaceTime), the TV pauses, lowers its volume, or mutes, and goes back to normal when the call ends. The app reads the "microphone in use" flag only; it never records anything.
- **Send to TV:** drop a photo, video, song, or YouTube link anywhere on the panel, paste a link, or send the text you copied on the Mac to the TV's search field.
- **Screen time:** local history of the apps and inputs the TV reports while your Mac is awake and connected.

## Supported TVs

> **Compatibility:** the app has been tested on an **LG 50UN7310PSC**. Other models and webOS versions are not verified. If you try another TV, say so in your issue or pull request, including the model number and the exact webOS version.

| Model | webOS version | Status |
| --- | --- | --- |
| LG 50UN7310PSC | 5.0 | Works: discovery, pairing, remote control |

| Model | Tizen | Status |
| --- | --- | --- |
| Samsung UN43T5300AGXZD (2020) | Tizen, firmware T-KTS2UABC | Works: discovery, pairing, keys, apps, volume, text input |

Samsung TVs from 2016 onward expose the local remote API this app uses. Older Samsung models (2015 and earlier) use different protocols and are not supported.

What each brand supports:

| Feature | LG webOS | Samsung Tizen |
| --- | --- | --- |
| Keys, apps, text input, power off | Yes | Yes |
| Volume level and mute state | Yes | Yes (through the TV's UPnP renderer) |
| App on screen | Yes | Yes, for apps in the bundled catalog |
| List of installed apps | Yes | Apps from the bundled catalog that the TV confirms |
| Input list and switching | Yes | Opens the TV's own Source menu |
| Pointer and touchpad | Yes | No |
| Picture settings and picture mode | Depends on TV permissions | No |
| Media casting (DLNA) | Yes | Yes |
| Open a YouTube link at the video | Yes | Opens the YouTube app only |

## Quick start with Claude

If you use Claude Code, clone this repository and tell Claude:

> Let's use this project. Set it up for my TV.

The `CLAUDE.md` file in the root tells Claude how to build the app, find your TV's address, check compatibility, and pair. Claude will ask you for anything it cannot find, such as the TV's IP address.

## Requirements

- A Mac running macOS 14 or later.
- Xcode Command Line Tools with Swift 5.9 or later. Install them with `xcode-select --install`.
- An LG webOS TV or a Samsung Tizen TV (2016 or later), on the same Wi-Fi or Ethernet network as your Mac.

## Build and run

```sh
bash scripts/build.sh
open "dist/Node Remote.app"
```

The script builds in a temporary directory, removes debug symbols, and creates a locally signed app bundle. It does not connect to a TV. Locally built apps are not notarized, so macOS may ask you to confirm the first time you open it.

To install it in your Applications folder, so it opens from Finder, Launchpad, and Spotlight like any other app:

```sh
bash scripts/install.sh
```

The app lives in the menu bar. Opening it from the Applications folder while it is running shows its panel.

## Find your TV

- **Model:** the model number is on the TV's info screen and on the label on the back of the TV.
- **IP address:** the app can find LG and Samsung TVs on your network, or you can enter the TV's IPv4 address manually (it looks like `192.0.2.42`). Your router's list of connected devices also shows it. A fixed address from the router keeps it from changing.
- **MAC address (optional):** only needed to turn the TV on from the Mac. For Samsung TVs found on the network, the app fills it in.

The app needs an IPv4 address. Hostnames and IPv6 addresses are not supported yet.

## Connect your TV

1. Turn on the TV and make sure your Mac is on the same network.
2. Open the app from the menu bar, then open Settings.
3. Choose **Find TVs on your network**, or pick the brand and enter the TV's IP address.
4. Optionally enter a display name and the MAC address.
5. Choose **Save and connect**. Approve the certificate prompt on your Mac, then accept the request on the TV.

If macOS asks for Local Network access, allow it. Discovery may not work on guest networks or networks with device isolation. In that case, enter the IP address manually.

- **LG:** pairing uses an encrypted WebSocket on port 3001. The TV shows a request from "LG Remote App", the name in LG's signed registration manifest.
- **Samsung:** pairing uses an encrypted WebSocket on port 8002. The TV asks you to allow "Node Remote" and returns a token. If the prompt never appears, check **Settings → General → External Device Manager → Device Connection Manager** on the TV.

The TV certificate fingerprint and the pairing key or token are stored in your Mac's Keychain, separately for each TV address. The app refuses a TV whose certificate has changed. To pair again after you have confirmed the TV is the same device, use **Forget pairing** in Settings.

The project ships with no TV address, device name, model, MAC address, or pairing key.

## Compatibility and limits

- **Screen time:** collected locally while the app is running, connected, and the Mac is awake. It cannot retrieve the TV's historical usage.
- **Home status:** the TV may report the underlying app while its Home overlay is visible. Home presses from this app are tracked locally. Home presses from a physical remote may not be detectable.
- **HDMI devices:** switching to a PlayStation or Chromecast switches the TV's input. It does not turn your Mac into a game controller.
- **Picture settings:** reading and changing values depends on TV permissions. Some TVs allow reading but reject changes. A scene step the TV refuses is skipped and reported.
- **Sleep timer:** there is no "end of episode" option, because neither brand reports playback progress over the local network. On Samsung, the power key toggles, so the timer first checks that the TV is still on.
- **YouTube links on Samsung:** tested on a 2020 Tizen TV, the TV refuses DIAL launches and ignores deep-link data on the local network, so a link opens the YouTube app but not the video. LG TVs open the video itself.
- **Routines:** they run while the Mac is awake and the app is open. A routine that turns the TV off never wakes it.
- **Samsung apps:** the TV does not list its installed apps, so the app checks the IDs in `samsung-apps.json` and shows the ones the TV confirms. Apps outside that catalog do not appear yet.
- **Media casting:** playback depends on the TV's supported codecs and DLNA service. Only the selected file is served, through a temporary URL reachable from the TV and this Mac only. H.264 MP4, MP3, and JPEG are the safest choices.
- **AirPlay:** the app shows guidance for macOS Screen Mirroring. It does not start mirroring itself, and it does not capture the TV screen on the Mac.
- **Logs:** activity logs describe this app's connections and commands. Internal TV system logs and Developer Mode access are not included.
- **Wake:** requires the TV's MAC address and network wake enabled in the TV's settings ("Wi-Fi wake" on LG, "Power on with mobile" on Samsung).

## Privacy and local storage

The app has no analytics, accounts, or cloud services. TV control stays on your local network. Icons are bundled with the app.

Preferences, saved TVs, scenes, and favorites are stored in macOS preferences. Usage and activity history are stored under `~/Library/Application Support/br.local.NodeRemote/`. Pairing credentials and certificate pins are stored in Keychain, separately for each TV address. None of these runtime files are part of this repository.

## Offline checks

These run without a TV and without access to your saved pairing:

```sh
bash scripts/build.sh
"dist/Node Remote.app/Contents/MacOS/NodeRemote" --self-check
python3 scripts/privacy-check.py
```

`--self-check` runs isolated tests for preferences, saved TVs, scenes, the sleep timer, keyboard shortcuts, certificates, the LG pointer channel, Home, usage, resources, the Samsung protocol messages, UPnP volume, and loopback media. `privacy-check.py` scans the files that would be published for local paths, device addresses, and saved pairing keys. It is a review aid, not a guarantee for every new file.

## Diagnostics

Diagnostics need an explicit TV address and do not switch inputs or launch apps. Reports contain local device information, so keep them private.

```sh
mkdir -p .local
"dist/Node Remote.app/Contents/MacOS/NodeRemote" \
  --diagnose --host "YOUR_TV_IP" --brand samsung --report .local/diagnostics.json
```

Use `--brand lg` (the default) or `--brand samsung`. For a TV that does not have a stored certificate pin yet, add `--trust-new-tv` to enable the trust prompt. Run `--help` for all options.

## Design

The interface follows Node's visual identity: deep blue `#002C44`, cyan `#04CBC9`, and cold white `#EFFFFF`, with the circuit-style support graphics. The tokens live in `Sources/NodeRemote/NodeTheme.swift`.

- `--render-preview DIR` draws every panel with demo data into PNG files, without contacting a TV or reading your preferences. Use it to review design changes.
- `swift scripts/make-icon.swift` regenerates the app icon in `Resources/AppIcon.icns`.

## Contributing

Bug reports and pull requests are welcome. The interface is in Brazilian Portuguese; code, documentation, and issues are in English.

When you report a problem, include:

- macOS version
- TV brand, model, and exact webOS or Tizen version
- Steps to reproduce
- A redacted error message

Keep IP addresses, MAC addresses, serial numbers, pairing keys, and diagnostic reports out of public issues and pull requests.

## License

MIT. See [LICENSE](LICENSE), which also lists third-party material and brand assets.
