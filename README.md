# Pocket

Pocket is a native macOS web app shell. It opens in Screen mode and landscape orientation by default, showing websites in a compact, borderless floating window.

## Build

```sh
./Scripts/build_app.sh
open Pocket.app
```

To retain Keychain approval across local rebuilds, run `./Scripts/setup_signing.sh` once. It creates a local code-signing certificate in your user Keychain, trusts it for code signing only, and allows `/usr/bin/codesign` to use its private key. Future builds automatically reuse it. After the first signed build, approve Pocket's WebCrypto key with **Always Allow**. A one-time **Allow** approval does not persist. You can use an existing signing identity instead by setting `POCKET_SIGNING_IDENTITY` when building.

The app targets macOS 14 or later and starts with web entry points for WhatsApp, Telegram, YouTube, X, and Spotify. Use the settings sliders icon in the bottom bar to add custom http or https sites, choose an SF Symbol icon, edit entries, or disable them from Pocket's app switcher. Each service gets its own persistent `WKWebsiteDataStore`, so logins and cookies do not leak between services.

Move over a screen to reveal its app switching, back and forward navigation, reload, orientation, Always on Top, and close controls. Bars appear immediately and disappear after three seconds without mouse movement. Typing, clicking, and scrolling do not reveal them or extend that deadline. Device mode shows the mock phone, while Screen mode removes the mock phone and keeps a compact window. The Pin button includes a label; website settings use a sliders icon.

Device windows keep the selected orientation when resized; Screen windows allow free edge resizing and always divide the available page area into equal cells. Pocket remembers the individual screen size for each orientation. Adding columns or rows grows the window by the current screen dimensions; removing them shrinks the window while retaining the remaining screens' size. Shared bars are counted once, and pages meet without gaps or borders.

Screen mode has a native layout menu with four equally sized square cells in each icon for one screen, two side by side, two stacked, or a four-screen grid. A shared top bar holds the three window controls, and a centered shared bottom bar holds layout, orientation, the Pin label and pin icon, and settings, in that order. The active screen's website chooser and navigation capsule sit together above its right edge, with the website chooser on the left. The margin between these controls and the page belongs to the same hover region, so moving into the controls keeps them visible. Top-row controls overlay the shared top bar; interior controls extend over a neighbor without covering their own website. Drag the shared top bar to move the window. All bars hide after three seconds of inactivity and remain available while a native menu is open.

Websites reflow as the viewport changes. Below a 480 x 300 viewport, Pocket zooms out to keep the layout usable; normal sizing returns when the window grows.

Web views fill their assigned tiles independently of website content widths. New-window links and sign-in popups open in a separate window, preserving communication with the original page. If a WebKit content process stops, Pocket attempts one reload and shows a retry message if it stops again within 30 seconds.

Each screen keeps its own selected site, web views, and navigation history. Switching from four screens to one and back retains the hidden screens' live pages, including their URLs, form state, and scroll positions. Screen selections, layout, and the last URL of each site on each screen are saved for the next launch; live document state is retained only while Pocket is running.

Run `./Scripts/test_multi_screen.sh` to check native layout resizing, equal screen dimensions with loaded content, layout geometry, independent web views, page retention, mouse-only idle controls, popup communication, crash recovery, and site disabling. Run `./Scripts/test_viewport.sh` to check the responsive viewport policy.

Keyboard shortcuts are `Command-1` for Device and `Command-2` for Screen, plus `Command-Shift-P` and `Command-Shift-L` for portrait and landscape. `Command-[` and `Command-]` navigate back and forward. `Control-Option-Command-T` toggles Always on Top.

Always on Top is enabled by default. While pinned, Pocket stays above other windows and follows you across desktops, including full-screen apps such as Arc. Turn off the pin using the button or the Pocket menu to keep Pocket on its current desktop at the normal window level.

WhatsApp uses a service-specific Chrome-compatible user agent because its web client otherwise rejects an embedded WebKit browser. Its resizing behavior is the same as every other website: responsive above the minimum viewport, with shrinking below it.
