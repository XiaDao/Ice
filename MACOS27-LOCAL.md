# Local macOS 27 compatibility build

This experimental branch starts at Ice `0.11.13-dev.2` (`da2dd23`). It incorporates
the macOS 27 implementation from [upstream PR #995](https://github.com/jordanbaird/Ice/pull/995),
pinned at `ba7cb69630600f61578ee5bebe3209189d0b0b29`, including its preceding
`macos-26` fixes. Credit for that implementation and its core tests belongs to
the upstream contributors. Existing GPL notices are retained.

The local changes additionally fix recording-permission detection: on macOS 26+
window titles are no longer a valid permission test. The approach is informed by
[PR #984](https://github.com/jordanbaird/Ice/pull/984), with a coalesced callback,
monotonic refresh times, a 30-second refresh after success, and regression tests.
The first asynchronous result is never permanently cached as a denial, and an
optional permission granted after startup remains observable.

The second local iteration (`0.11.13-dev.2-macos27.2`, build 1123) also:

- Keeps the saved visibility policy while the layout editor is open. It no
  longer reveals every application merely to display the editor.
- Removes both obsolete section dividers after migration, including under the
  assessment backend, so an invisible but clickable spacer cannot remain.
- Discovers item identities before concealment and accepts identities without
  geometry. Later iterations retain the saved hidden membership across temporary
  reveals and incomplete AX scans, dropping terminated processes.
- Uses a translucent visual-effect background tinted from a small screenshot
  strip on the appropriate display, replacing the imported branch's solid white
  background. Ice Bar glyphs render as templates against that background.
- Keeps a named monochrome placeholder accessible until a real glyph can be
  captured; an uncaptured icon is no longer silently omitted.

Iterations through `0.11.13-dev.2-macos27.5`, build 1126, additionally:

- Persists identity metadata separately from glyph images, without persisting
  process IDs or screen coordinates, to restore running hidden applications.
- Keeps a temporary reveal alive while its menu is open, then starts the
  configured reveal interval after the menu closes.
- Observes temporary-menu dismissal separately from a potentially blocking AX
  press. Mouse and keyboard input are passed through while the session is active.
- Restricts the assessment click bridge to identified Apple status items in
  the clicked display's menu bar. Application popover input does not qualify.
- Resolves drawn app geometry from MenuBarAgent's native status containers;
  unverified geometry falls back to Accessibility activation. This approach is
  informed by [upstream PR #997](https://github.com/jordanbaird/Ice/pull/997).

Iteration `0.11.13-dev.2-macos27.6` (build 1127) fixes two further
gaps in the imported implementation:

- Layout drops previously saved only the application-level section. A separate
  per-item order now preserves hidden-section order across incomplete AX scans
  and restarts; the Ice Bar uses the same cache as Layout.
- A Visible drop performs a native Command-drag and checks settled physical
  adjacency twice before saving the result. Transactions are serialized and
  visibility changes paused during each gesture. Invalid or cross-display
  geometry is rejected; failure is reported instead of silently accepting an
  editor-only rearrangement. There is no continuous background reorder loop.
  The native gesture sequence is adapted from GPL upstream PR #997, pinned at
  `c3df598f36100b0500fd159a1cfd9ac5d2dc2525`.
- Layout icons and drag previews use the cached alpha mask with the current
  label colour. Changing appearance redraws them without needing to recapture
  every hidden application.

Build 1127 compiled and passed 189 core tests in 38 suites. The user confirmed
native ordering is fixed. Dark-mode glyph colour improved, but dim disconnected
details (a lock's surrounding ring and five of a launcher's nine dots) were
missing from the cached alpha, which tinting alone cannot repair.

Iteration `0.11.13-dev.2-macos27.7` (build 1128) addresses that
extraction bug. On a smoothly shaded background it estimates template alpha
against the local background instead of subtracting a fixed 25% colour prior.
Two-dimensional dim components are retained rather than requiring every separate
mark to contain an opaque pixel. Textured backgrounds retain the conservative
path; isolated specks and thin detached streaks are still removed. Image-cache
version 10 automatically recaptures version 9's incomplete glyphs. Section/order
preferences and persistent item identities are separate from that cache.

All 192 core tests in 39 suites pass. An additional local check processed the
user-supplied native-menu screenshot through the new extraction and component
filter: the ring and all nine dots remained, and neither tile was rejected by
the fade or retained-background checks. The user confirmed the ring and all nine
dots returned. Subsequent testing exposed theme-transition and filled-glyph cases
addressed below.

The ninth build is `0.11.13-dev.2-macos27.9` (1130), with 194 tests in 40 suites
passing. Iterations 8–9 additionally:

- Keep glyph alpha caches across appearance changes and resolve Layout's
  background from a dynamic system colour, instead of a periodically sampled
  CGColor. Search also renders glyphs as templates.
- Wait for the queued concealment backend operation before photographing a
  temporarily revealed item, and try one additional capture if it is missing.
- Accept a confined, translucent filled glyph with clear vertical margins.
  The previous retained-background heuristic rejected Dropover's correctly
  extracted rounded-square icon because its legitimate fill exceeded 15% of the
  tile. Locally captured raw/alpha crops confirmed that exact failure.
- Update Layout's instructions now that native reordering is supported.

An optional `ICE_GLYPH_DIAGNOSTICS_DIR` process environment variable records only
the status-item crops and extracted glyphs for local debugging. It was enabled
for iteration 8 and is disabled in the normal iteration 9 launch. Raw diagnostic
images are not included in the source patch. The user confirmed that light-mode
nine-dot detail, the real Dropover glyph, and theme transitions all work in
iteration 9. The native ordering fix was confirmed in iteration 6.

## Application menus mistaken for empty space (2026-10-29)

Build `0.11.13-dev.2-macos27.10` (1131) protects the application-menu area when
Accessibility cannot provide a complete measurement. Previously, a failed read
returned `false` from `isMouseInsideApplicationMenu`, which let the click and
hover handlers classify a visible application menu as empty bar and open Ice.
The measurement also discarded titles whose AXEnabled value was false or
unavailable, even though those titles still occupied space.

The macOS 27 measurement now includes every title, rejects missing or malformed
frames and menu-owner changes during the read, and suppresses empty-space
shortcuts while geometry is unknown. The Ice button remains available. A queued
hover reveal also rechecks its permission and menu owner before opening.

All 201 core tests in 41 suites pass, including incomplete reads, missing trailing
titles, malformed geometry, recovery, and the fallback's display boundaries.
These are confirmed failure paths in the code, not a reproduction proving which
one caused the user's intermittent OrbStack incident.

The Release build and strict signature verification passed with a fresh derived
data directory after the moved old module cache crashed the Swift compiler.
Build 1131 was installed over `/Applications/Ice.app` with the same designated
requirement. UI inspection confirmed its version and that OrbStack's File, Edit,
and Help menus could open and be cancelled. No erroneous Ice Bar was observed
during those checks, but the original intermittent state was not reproduced.
Launch Services and Spotlight each report only `/Applications/Ice.app`; the old
installed build is retained as a verified ZIP, and loose build products were
removed after installation.

## Menu interaction investigation (2026-10-27)

During testing on macOS 27.2 (26B123) with an external display, the user reported
menus that ignored same-display clicks but dismissed when the other display was
clicked. Pulse's custom-view NSMenu was affected more severely than other menus.
The problem also reproduced in Shottr with both Ice and Thaw fully stopped.
Process inspection confirmed neither manager was running, and MenuBarAgent logs
recorded the last visibility restriction being invalidated. This does not prove
which action originally triggered the bad state.

Restarting only MenuBarAgent restored native Shottr and Pulse interactions, as
confirmed by the user. With the same installed Ice build then started alone,
the user again confirmed both menus operated and dismissed normally. No further
click patch was installed between those two successful checks. This distinguishes
the observed runtime recovery from a claim that all menu failures are fixed or
that the failure is an unavoidable macOS-wide bug.

Build 1126 passed 182 core tests in 37 suites. Those tests do not reproduce
WindowServer/MenuBarAgent focus or native menu tracking across displays. The
temporary test hotkey was removed and Automatically Rehide restored to its
original enabled state. Thaw remains stopped during Ice testing.

## Build and test

Requires full Xcode; builds have been checked with Xcode 26.4 on Apple Silicon.
The helper selects `/Applications/Xcode.app` for its process when Command Line
Tools is the active global developer directory. It does not change that global
selection or install anything automatically.

```sh
bash Scripts/build-local.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test
```

The default product is `build/local/Build/Products/Release/Ice.app`; set
`ICE_DERIVED_DATA` to select another build directory. The helper prefers an
existing Apple Development identity and falls back to ad-hoc signing when none
is available. `ICE_CODE_SIGN_IDENTITY=-` explicitly selects ad-hoc signing.
Hardened runtime is disabled for these local builds, which are not notarized
releases. Replacing an official or differently signed Ice can require renewing
its Accessibility and Screen Recording grants. Iterations 3–5 use the same local
development identity; their designated requirements match, and authorization
has remained valid across these updates. Builds 1127–1131 retain that requirement.

## Behavior and limits

- On macOS 27, enumeration uses Accessibility because menu bar items no longer
  have individual WindowServer windows. Earlier macOS versions retain their
  existing enumeration and hiding paths.
- The native “Allow in the Menu Bar” backend is preferred when its preferences
  are accessible. Otherwise PR #995 falls back to assessment assertions. Do not
  grant Full Disk Access just to make the preferred backend available.
- Assessment mode requires a temporary reveal for some system-item clicks and
  uses Ice's capture indicator. This remains an experimental compatibility path.
- macOS 27 sections are persisted per application. Multiple status items from
  one application share a section. Visible order changes use explicit verified
  native drags; pinned system items can still reject movement.
- Item images are saved locally and refreshed when possible. This is not a
  guarantee of live previews for every hidden or native-overflow item.
- Thaw must be quit during testing to avoid competing menu bar assertions.

The original installed application and both apps' preferences were backed up
before the local test. See the accompanying verification report for the actual
UI checks completed on macOS 27.2; unit-test success alone is not a compatibility
claim for every display, application, or future macOS release.
