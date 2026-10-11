# Pocket development

## Preserve reachable individual screen controls

Each screen's website selector and navigation capsule sit above its page. Treat
the capsules, their surrounding hover margin, the gap between them, and the gap
back to their page as one continuous hover area belonging to that screen.
Moving through this area must keep the originating screen's controls visible
and clickable, even when they overlap another screen's page. Outside that area,
hovering another page must select that page normally.

Keep rendering and pointer tracking in the same full-window coordinate space.
Pocket uses a transparent native titlebar with full-size content. A SwiftUI
tracking overlay that respects the titlebar safe area while the pages ignore it
introduces a vertical offset and makes interior controls unreachable. Preserve
the tracking overlay's `ignoresSafeArea()` in `AppRootView`.

An AppKit tracking-area exit inside the window must not hide controls. Hide
immediately only when the pointer leaves the whole window, subject to the
existing pending-chat-request hold. After inactivity hides a screen's controls,
moving over that screen's control area must restore the same screen's controls.
Keep the tracking view transparent to clicks so website interaction still works.

Do not fix reachability by disabling inactivity hiding. Preserve the shared
visibility rules: three seconds after mouse movement, six seconds after typing
in the chat composer, immediate whole-window exit, and visibility while a chat
request is running. Typing in websites does not reveal controls.

For changes to hover tracking, chrome visibility, root layout, chat composer
placement, or safe-area handling, run:

- `Scripts/test_multi_screen.sh`
- `Scripts/test_chat.sh`

Keep the full `AppRootView` regression test, not just the pure geometry checks.
It follows pointer events from mounted pages through the gaps into the controls,
checks native hit testing, and covers all sixteen layouts with chat open and
closed. The standalone grid test cannot detect a root tracking coordinate offset.
