# Pocket

Pocket is a native macOS web app shell. It opens in Screen mode and landscape orientation by default, showing websites in a compact, borderless floating window.

## Build

```sh
./Scripts/build_app.sh
open Pocket.app
```

To retain Keychain approval across local rebuilds, run `./Scripts/setup_signing.sh` once. It creates a local code-signing certificate in your user Keychain, trusts it for code signing only, and allows `/usr/bin/codesign` to use its private key. Future builds automatically reuse it. After the first signed build, approve Pocket's WebCrypto key with **Always Allow**. A one-time **Allow** approval does not persist. You can use an existing signing identity instead by setting `POCKET_SIGNING_IDENTITY` when building.

The app targets macOS 14 or later and starts with web entry points for WhatsApp, Telegram, YouTube, X, and Spotify. Use **Manage sites** in the bottom menu to add custom http or https sites, choose an SF Symbol icon, edit entries, or disable them from Pocket's app switcher. Each service gets its own persistent `WKWebsiteDataStore`, so logins and cookies do not leak between services.

Hover over the compact window to reveal app switching, back and forward navigation, reload, orientation, Always on Top, and close controls. Device mode shows the mock phone, while Screen mode removes the mock phone and keeps a compact window. The Manage sites button appears in the bottom menu with the hover controls.

Device and Screen windows can be resized from their edges while preserving the selected orientation, and Pocket remembers the last size for each compact mode. Websites update their responsive layouts as the web viewport changes. Below a 480 × 300 viewport, Pocket zooms out to keep the layout usable rather than squeezing it further; normal sizing returns when the window grows. Compact modes reserve a transparent control bay below the viewing area, so revealing the lower hover controls never resizes or covers the content. The controls scale down to stay inside narrow compact windows, and a thin drag strip appears on hover above the web content. Always on Top remains available from the Pocket menu.

Keyboard shortcuts are `Command-1` for Device and `Command-2` for Screen, plus `Command-Shift-P` and `Command-Shift-L` for portrait and landscape. `Command-[` and `Command-]` navigate back and forward. `Control-Option-Command-T` toggles Always on Top.

Always on Top is enabled by default. While pinned, Pocket stays above other windows and follows you across desktops, including full-screen apps such as Arc. Turn off the pin using the button or the Pocket menu to keep Pocket on its current desktop at the normal window level.

WhatsApp uses a service-specific Chrome-compatible user agent because its web client otherwise rejects an embedded WebKit browser. Every other site sends a current Safari user agent, taken from the installed Safari version, so sites such as Gmail do not treat the embedded WebKit view as an outdated browser. Resizing behavior is the same for every website: responsive above the minimum viewport, with shrinking below it.
