# Pocket

Pocket is a native macOS web app shell. It opens in Screen mode and landscape orientation by default, showing websites in a compact, borderless floating window.

## Build

```sh
./Scripts/build_app.sh
open Pocket.app
```

To retain Keychain approval across local rebuilds, run `./Scripts/setup_signing.sh` once. It creates a local code-signing certificate in your user Keychain, trusts it for code signing only, and allows `/usr/bin/codesign` to use its private key. Future builds automatically reuse it. After the first signed build, approve Pocket's WebCrypto key with **Always Allow**. A one-time **Allow** approval does not persist. You can use an existing signing identity instead by setting `POCKET_SIGNING_IDENTITY` when building.

The app targets macOS 14 or later and starts with web entry points for WhatsApp, Telegram, YouTube, X, and Spotify. Use the settings sliders icon in the bottom bar to add custom http or https sites, choose an SF Symbol icon, edit entries, or disable them from Pocket's app switcher. Each service gets its own persistent `WKWebsiteDataStore`, so logins and cookies do not leak between services.

Move over a screen to reveal its app switching, back and forward navigation, reload, orientation, Always on Top, and close controls. Bars appear immediately and disappear after three seconds without mouse movement. Typing in a website, clicking, and scrolling do not reveal them or extend that deadline. Typing in Pocket's chat input keeps the controls visible for six seconds. Leaving the window hides them immediately, except while a chat request is running. Device mode shows the mock phone, while Screen mode removes the mock phone and keeps a compact window. The Pin button includes a label; website settings use a sliders icon.

Device windows keep the selected orientation when resized; Screen windows allow free edge resizing and always divide the available page area into equal cells. Pocket remembers the individual screen size for each orientation. Adding columns or rows grows the window by the current screen dimensions; removing them shrinks the window while retaining the remaining screens' size. Shared bars are counted once, and pages meet without gaps or borders.

Screen mode has a native layout menu with four equally sized square cells in each icon for one screen, two side by side, two stacked, or a four-screen grid. A shared top bar holds the three window controls, and a centered shared bottom bar holds layout, orientation, the Pin label and pin icon, and settings, in that order. The active screen's website chooser and navigation capsule sit together above its right edge, with the website chooser on the left. The margin between these controls and the page belongs to the same hover region, so moving into the controls keeps them visible. Top-row controls overlay the shared top bar; interior controls extend over a neighbor without covering their own website. Drag the shared top bar to move the window. All bars hide after three seconds of inactivity and remain available while a native menu is open.

Websites reflow as the viewport changes. Below a 480 x 300 viewport, Pocket zooms out to keep the layout usable; normal sizing returns when the window grows.

Click the four-corners icon to the right of Refresh to expand an individual screen into a floating window centered on the current monitor at 75% of its available width and height. The grid stays in place underneath. The floating view keeps that screen's website selector and navigation controls, with the same hover timeout. Click the icon again or press Escape to return the live page to its original tile. One screen can be expanded at a time; switching expanded screens restores the previous one. Expansion preserves the page's URL, navigation history, form input, and scroll position.

Web views fill their assigned tiles independently of website content widths. New-window links and sign-in popups open in a separate window, preserving communication with the original page. If a WebKit content process stops, Pocket attempts one reload and shows a retry message if it stops again within 30 seconds.

Each screen keeps its own selected site, web views, and navigation history. Switching from four screens to one and back retains the hidden screens' live pages, including their URLs, form state, and scroll positions. Screen selections, layout, and the last URL of each site on each screen are saved for the next launch; live document state is retained only while Pocket is running.

Run `./Scripts/test_multi_screen.sh` to check native layout resizing, equal screen dimensions with loaded content, layout geometry, independent web views, page retention, mouse-only idle controls, popup communication, crash recovery, and site disabling. Run `./Scripts/test_viewport.sh` to check the responsive viewport policy.

## Pocket chat

Click the chat bubble after settings in the shared bottom bar. First use explains the feature and offers **Cancel** or **Log in to ChatGPT**. Sign-in opens your browser through the [Codex app-server login flow](https://learn.chatgpt.com/docs/app-server). Pocket keeps its credentials in its own `~/Library/Application Support/Pocket/Codex` directory, separate from other Codex apps. Subsequent clicks open or close a floating input below the bottom bar. Its box has a dark fill and border; the surrounding area stays transparent. Opening it grows the window downward and keeps the screen dimensions unchanged. Shared bars, individual controls, and the input hide together after three seconds without mouse movement, or six seconds after the last chat edit. Mouse movement cannot shorten that typing deadline. Leaving the window hides the controls immediately. While a chat request is running, the controls remain visible even if the pointer leaves. Completion, failure, or cancellation releases that hold: controls hide immediately if the pointer is outside, otherwise the normal inactivity timer resumes. Hiding retains the input's draft, focus, and reserved height, so returning to the window or typing reveals the controls together without resizing the screens.

Try "Give me a 4x4 grid" or "Give me a 2x2 grid with Telegram top left and YouTube top right." Requests use your ChatGPT account's available Codex usage. The assistant receives the layout, registered site names and URLs, and each screen's selected site and current URL. Website cookies, passwords, and page contents are not included. The native helper runs separately from the UI with shell tools, browsing, and connectors disabled.

Responses use a strict JSON schema. Pocket validates the complete change before applying it and rejects replies if the view changed while the request was running. Unmentioned screens retain their existing sites and live web views; explicitly empty screens switch Off. The composer supports request cancellation. Undo is currently disabled. Request feedback and warnings appear in dismissible toasts that disappear after five seconds.

Install the official Codex CLI before building. `build_app.sh` bundles its native executable for Finder launches; `POCKET_CODEX_BINARY` can specify its path. The helper is bundled without account credentials. Run `./Scripts/test_chat.sh` to check offline login and command flows, JSON-RPC failures, workspace validation, state preservation, composer sizing, and real helper startup. End-to-end inference requires completing ChatGPT sign-in in Pocket.

Keyboard shortcuts are `Command-1` for Device and `Command-2` for Screen, plus `Command-Shift-P` and `Command-Shift-L` for portrait and landscape. `Command-[` and `Command-]` navigate back and forward. `Control-Option-Command-T` toggles Always on Top.

Always on Top is enabled by default. While pinned, Pocket stays above other windows and follows you across desktops, including full-screen apps such as Arc. Turn off the pin using the button or the Pocket menu to keep Pocket on its current desktop at the normal window level.

WhatsApp uses a service-specific Chrome-compatible user agent because its web client otherwise rejects an embedded WebKit browser. Its resizing behavior is the same as every other website: responsive above the minimum viewport, with shrinking below it.
