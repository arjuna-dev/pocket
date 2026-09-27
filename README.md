# Pocket

Pocket is a native macOS web app simulator shell. Its default Device mode is a compact, borderless utility window that shows only the simulated device and its contents.

## Build

```sh
./Scripts/build_app.sh
open Pocket.app
```

The app targets macOS 14 or later and starts with web entry points for WhatsApp, Telegram, YouTube, X, and Spotify. In Workspace mode, use the Manage Websites button to add custom http or https sites, choose an SF Symbol icon, edit entries, or disable them from Pocket's app switchers. Each service gets its own persistent `WKWebsiteDataStore`, so logins and cookies do not leak between services.

Hover over the compact window to reveal app switching, back and forward navigation, reload, orientation, Always on Top, and close controls. Device mode shows the mock phone, Screen mode removes the mock phone while keeping a compact window, and Workspace mode opens the full sidebar and toolbar layout for edge cases.

Device and Screen windows can be resized from their edges while preserving the selected orientation, and Pocket remembers the last size for each compact mode. Screen mode keeps a fixed web viewport and scales it to fit the available window, so shrinking the window does not introduce horizontal overflow. Compact modes reserve a transparent control bay below the viewing area, so revealing the lower hover controls never resizes or covers the content. The controls scale down to stay inside narrow compact windows, and a thin drag strip appears on hover above the web content. Always on Top remains available from the Pocket menu.

Keyboard shortcuts are `Command-1`, `Command-2`, and `Command-3` for Device, Screen, and Workspace, plus `Command-Shift-P` and `Command-Shift-L` for portrait and landscape. `Command-[` and `Command-]` navigate back and forward. `Control-Option-Command-T` toggles Always on Top.

WhatsApp uses a service-specific Chrome-compatible user agent because its web client otherwise rejects an embedded WebKit browser. Device mode applies a small compatibility zoom for that wide desktop layout, while Screen mode restores normal scale.
