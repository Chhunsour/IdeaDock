# IdeaDock

A native macOS 14+ workspace for quick idea capture, a quiet desktop capture bar, and a searchable local library. Built with SwiftUI, AppKit, and SwiftData. No account, external dependencies, analytics, or background clipboard monitoring.

## Open the app

Open the supplied `IdeaDock.app`. IdeaDock can stay in the menu bar after its windows close; use **IdeaDock → Quit IdeaDock** to quit. Settings control Dock/menu bar visibility, appearance, floating windows, global shortcuts, and launch at login. At least one Dock or menu bar entry remains available.

Default actions:

| Action | Shortcut |
| --- | --- |
| Quick capture from any app | Option-Space |
| Explicitly capture the current clipboard | Command-Shift-V |
| Save from capture | Command-Return |
| Dismiss quick capture | Escape |
| Open the command palette | Command-K |
| Settings | Command-comma |

Quick capture also accepts Return to save and Shift-Return for a new line. Desktop capture supports multiline drafting. Text, URLs, code, images, files, and folders can be captured or dropped; hashtags are detected when enabled. The library supports categories, tags, type filters, text search, pin/favorite/archive, and floating individual notes. Search combines ordinary words with filters such as `tag:launch`, `category:research`, and `type:code`.

The app does not contact a metadata service for captured links. Links are detected locally; opening a link or referenced file uses the chosen macOS application.

## Capture now, find it later

The library opens to **All Notes**, a capture history grouped automatically into Today, Yesterday, and dates. The newest captures stay first; older pinned notes remain available in Pinned without disrupting the history. **Today** provides a quick daily view. Time filters find captures from yesterday, the last seven days, or the last thirty days, and combine with ordinary search and automatic content-type filters.

Every note shows its local capture date and time. Hover a timestamp for the full time and time zone; the editor also exposes the last change time when relevant. Capture time means the moment the note was saved into IdeaDock, including content you pasted. It does not infer when an external item was originally copied. Opening or closing an unchanged editor preserves its timestamps.

Press **Command-K** to see your latest captures or type a few remembered words to find a saved note. Search covers titles, bodies, tags, URLs, category names, and attachment names. Return opens the selected result. Ordinary library search finds notes across categories; Archive retains a separate search scope. After saving from desktop capture, a quiet **Last saved** line shows the time and title and opens that note with one click.

Titles, content types, dates, and optional hashtags are derived automatically. Categories start collapsed in the sidebar and remain available when needed. You can keep using Inbox for every capture without organizing anything manually.

## Move and tuck away notes

Drag the desktop capture header, its mini-bar grip, or the slim grip above an individual floating note's title. Notes move freely across the desktop. Near any side, top, bottom, or corner, a translucent orange handle previews the docking position. Release to let the note slide and fade into that edge. Click the remaining handle to bring it back, or drag the handle out to place the note elsewhere. Escape during a drag cancels docking.

Right-click a drag grip for **Dock at Screen Edge**, or use **Window → Dock Current Note** for a keyboard-accessible alternative. All eight edges/corners are available. The app remembers docked notes across restart, keeps handles within the available display area, and follows macOS Reduce Motion. Docking preserves the current editor and unsaved capture draft while the app stays open.

## Storage and backups

The normal library lives in `~/Library/Application Support/IdeaDock/`. SwiftData stores the ideas and metadata in `IdeaDock.store`; owned image files live in `Attachments/`. Preferences and window state use local UserDefaults. The app has no synchronization service.

Images are validated and copied into the library. Regular files and folders keep a bookmark and fallback path, so their original contents are not duplicated. Moving or deleting an original may make its reference unavailable. Removing an idea removes its owned images and preserves referenced originals.

Settings → Data exports a portable JSON backup or a readable Markdown folder with included images. JSON imports merge UUIDs and preserve existing local edits. Inbox maps to the destination Inbox; distinct non-Inbox category UUIDs remain distinct. Exported regular file/folder references still require their originals. See [verification and format details](docs/Verification.md) for limits, restore behavior, and checks.

## Build and test

Requires macOS and Apple command-line tools with Swift 6 or later and a macOS SDK. The package targets macOS 14 and uses Swift 5 language mode. Full Xcode is not required for the supplied application target.

```sh
./scripts/test.sh
./scripts/build.sh
```

The build script creates the sibling `IdeaDock.app`, copies its resource bundles, applies a local ad hoc signature, and verifies that signature. Pass a different `.app` destination as the first argument if needed. All compiler/module/SwiftPM caches stay in `work/IdeaDock-build` inside a standalone source checkout, or in the enclosing workspace when the source is under `outputs/`; `IDEADOCK_BUILD_ROOT` overrides that build directory. Scripts pass `--disable-sandbox` to SwiftPM because the restricted development environment cannot start its manifest sandbox. There are no dependencies to download.

The supplied binary is an Apple silicon build, verified on this Mac. It is locally signed for personal use and is not notarized for public distribution. The source can be rebuilt with Apple's toolchain on a compatible Mac.

Tests use temporary **on-disk** libraries and exercise capture/edit/delete, flags/tags/search, categories, actual reopen persistence, owned images and external references, JSON/Markdown roundtrips, identity-preserving imports, malicious/corrupt backup rejection, rollback, asynchronous native drops, and a private named pasteboard. They never read or change the general clipboard. `IdeaDock --self-test` exits before any normal library or application UI initialization. Native shortcut/focus/window/login behavior requires the separate interaction checks in [Verification.md](docs/Verification.md).

For an isolated native UI library, launch the executable with `--data-dir /private/tmp/IdeaDock-UIVerification`. This switches the app to a separate library and preference suite. Use a new empty path and quit the normal instance first. A temporary path avoids macOS requesting Documents access for the test library after a local rebuild; the normal library lives in Application Support.

## Source layout

| Location | Responsibility |
| --- | --- |
| `App/Main.swift` | AppKit lifecycle, menu bar and menus, native window/panel ownership, focus, and commands |
| `App/EdgeDockController.swift`, `Services/EdgeDockGeometry.swift`, `Components/WindowDragRegion.swift` | Native dragging, edge previews, dock handles, animation, safe restoration, and remembered positions |
| `App/Preferences.swift`, `Services/HotKeyService.swift` | UserDefaults, login item state, and Carbon global shortcuts |
| `App/WorkspaceState.swift`, `Features/Library/` | Library navigation, selection, filters, search, and command palette |
| `Features/Capture/`, `Components/CaptureTextView.swift` | Capture drafts and native text/paste/drop input |
| `Features/Editor/`, `Features/FloatingNotes/`, `Features/Categories/` | Editing, individual floating notes, and organization |
| `Models/Idea.swift`, `Data/IdeaStore.swift` | SwiftData schema, persistence, explicit saves, and scoped queries |
| `Services/AttachmentService.swift`, `Services/DropReader.swift` | Image ownership, references, clipboard snapshots, and drop decoding |
| `Data/ExportService.swift`, `App/SelfTests.swift` | Versioned backups, readable exports, validated merge, and isolated verification |
| `Features/Settings/`, `Components/Design.swift` | Native settings and shared visual treatment |
| `Services/CaptureHistory.swift`, `Components/CaptureTimestamp.swift` | Calendar-based history, time ranges, exact local timestamps, and live relative labels |

### SwiftData with command-line tools

The models implement `PersistentModel` explicitly because the installed command-line toolchain does not include the SwiftData `@Model` macro plugin. Each model defines schema metadata, reflected `_$backingData` and `_$observationRegistrar` fields, and `init(backingData:)`. Constructors initialize raw backing data; runtime getters/setters call the model-level `getValue`/`setValue` helpers inside Observation access/mutation hooks. Calling raw backing-data setters for runtime edits bypasses SwiftData change tracking and loses edits after refresh, so keep that distinction when changing models. Delete code also avoids reading scalar properties from invalidated deleted models.

Optional WidgetKit is deferred in this source delivery because building and installing a widget extension requires a full Xcode application project and signing/provisioning setup.
