# Verification and portable backups

Run `./scripts/test.sh` from the source folder. It builds with the installed Apple command-line tools and runs `IdeaDock --self-test`. Tests use randomly named temporary **on-disk** SwiftData libraries, delete them afterward, and never initialize the normal user library, clipboard watcher, global shortcut, or application windows. A successful run prints each `PASS` group and exits with status 0; a failure prints `FAIL` and exits with status 1.

The tests cover:

- All eight edge/corner placements, inclusive proximity thresholds, overshoot, negative display coordinates, handle travel, invalid geometry, small displays, clamped restoration, directional translation, and serialized edge identities. These are pure geometry checks and do not move the desktop's windows.
- Capture history and time filters at midnight, inclusive/exclusive calendar boundaries, 23/25-hour daylight-saving days, ranges crossing those transitions, future timestamps, stable chronological ordering despite pins, identical-date UUID ties, day-section order matching keyboard navigation, and original capture timestamps surviving edits and disk reopen.
- Text capture and editing; pin, favorite, archive, delete, detected/manual tags, type filters, scoped and combined search.
- Category creation, order, deletion with migration to Inbox, and protection of Inbox.
- Store close/reopen with persisted idea/attachment/category UUIDs, content, metadata, dates, and order.
- Validated owned image copying, image symlink resolution, corrupt image rejection, and external file references without copying or deleting originals.
- Native asynchronous NSItemProvider text, URL, file, and image drops; representation priority, duplicate file references, capture/reopen, and dropped draft cleanup. Completion pumps the main run loop with a four-second timeout.
- Clipboard reading through a private uniquely named pasteboard: text, URL, image plus separate caption, and file references, plus cleanup on a failed multi-item capture. The general clipboard is never read or changed.
- JSON export/import with image bytes; Markdown export with an index, individual notes, and included images.
- Idempotent JSON reimport, retained local edits, and mapping the imported Inbox to the destination Inbox.
- Rejection of unsupported versions, duplicate IDs, unsafe image filenames, corrupt/oversized image data, and dangling category references before mutation.
- Transaction rollback when a destination attachment filename is occupied, including removal of an image copied earlier in the failed import, retention of the occupied original, preservation of an unrelated pending local edit, and verification after reopening the database.

Build the launchable application with `./scripts/build.sh`. The default result is the sibling `IdeaDock.app`; an optional first argument sets the destination app path. Compiler caches and build products are written to the workspace's `work/IdeaDock-build` directory. The bundle is signed locally with an ad hoc signature and checked with `codesign --verify --deep --strict`. No external dependencies are downloaded.

## Verification evidence

During development on this Mac, the debug suite and the optimized arm64 release bundle completed the data/service checks. The 1.2 release suite includes edge-docking geometry and calendar history/time filters, and prints eleven `PASS` lines including the final summary. The release checks include actual disk reopen, runtime change tracking, portable image/metadata roundtrip, rejection of a valid GIF with too many frames, rollback with an unrelated pending edit, native asynchronous providers, and a private named pasteboard. The created `.app` passed strict deep signature verification and its Info.plist passed validation.

Native interaction checks exercised text/tag capture, content editing, pinning, search, image plus text, URL and code capture, the command palette and arrow navigation, referenced-file capture, floating an individual note, and light/dark appearance. Carbon registration and delivery of a native event to the in-process event handler were also checked. App-directed automation sends keys to the selected app; it does not prove operating-system recognition of a physical global shortcut from another app. A physical shortcut check remains manual. Launch-at-login and transitions between Spaces were not physically tested. WidgetKit remains deferred.

The final rebuilt bundle should receive the same isolated release self-test after any later source changes. User-library data and the general clipboard are excluded from these tests.

## JSON format and merge behavior

Backups use `format: "IdeaDock"`, `version: 1`, and millisecond timestamps with fractional precision. They preserve ideas, categories, ordering, dates, flags, tags, inferred type/source link metadata, and attachment metadata. Owned image bytes are embedded as base64. Other files and folders retain the original absolute path and bookmark without embedding the original contents.

Import adds records by UUID and skips ideas already present. It never overwrites a local idea or category. Inbox maps to the existing local Inbox; other category UUIDs are preserved, so two independently created categories with the same name can remain separate. File references may need to be attached again when restoring on a different Mac or after moving an original file. Markdown is a readable export; restore libraries with JSON.

Import limits are 400 MB for a JSON file, 100,000 ideas, 10,000 categories, 50 MB per encoded image, and 250 MB total image payload after base64 decoding. An image may have up to 10,000 frames with no more than 40 million frame pixels in total and 16,000 pixels per dimension. Owned image filenames must use a recognized image extension and a single UUID filename matching the attachment ID. All records are validated before database/file mutation; failed imports roll back newly inserted objects and newly copied images.

## Native interaction checks

The self-test exercises storage and service behavior. The following checks require launching the native application:

1. Open `IdeaDock.app`; capture a short note with a hashtag, reopen the app, and confirm persistence.
2. Invoke the capture shortcut while a different app is active; submit with Command-Return and confirm focus returns to the previous app.
3. Paste or drop text, a link, an image, and a regular file into capture; verify image previews and external reference opening.
4. Edit a note, change category/tags, pin/favorite/archive it, then use scoped/type/search filters to locate it.
5. Change capture preferences; confirm the clipboard is read only during an explicit paste/capture action, shortcut conflicts show an actionable message, and launch-at-login reflects macOS registration state.
6. Export JSON and Markdown from settings; check the readable Markdown folder and import JSON into a separate library or use the isolated test mode for restore verification.
7. Drag full desktop capture, mini capture, and an individual note near each edge/corner. Confirm the preview follows the candidate, release tucks the note away, and Escape suppresses docking until release. Click and drag each handle back out; verify contents, resize, pin/opacity, and reopening after restart. Repeat between physical displays and Spaces, and with Reduce Motion enabled.
8. Save a capture without choosing metadata. Verify its time and position in All Notes/Today, open it through the Last saved receipt and Command-K search, combine date/type/text filters, and find it after changing category. Open and close an unchanged note and confirm its change timestamp remains stable; edit and immediately switch notes to check autosave.

## Delivery verification — 3 October 2026

The release executable was built with Swift 6.4 and the installed macOS 27 SDK, bundled as `IdeaDock.app`, and passed local ad hoc signature verification. The optimized executable passed every self-test group above. No app-source compiler warnings remain; the command-line toolchain emits two harmless linker search-path warnings for directories absent from its installation.

The native app was launched against an isolated on-disk library and inspected through macOS accessibility and actual screenshots. Verified interactions include:

- Immediate capture input focus, Return saving/dismissal, text and hashtag capture, URL recognition, and code formatting.
- Attaching a local image with a caption and an external text file using the real native file picker; image preview and file name/type/size display.
- Editing and explicit saving, pinning, instant tagged/type search, clicking draggable idea rows, Up/Down navigation, Enter opening the editor, and Escape returning to browsing.
- Command palette filtering and keyboard execution; opening Pinned and Search through its commands.
- Category management and creation, with the test category surviving a restart.
- Mini capture restored after restarting, expansion back to the full desktop surface, and opening the library from that surface.
- Creating and closing an independent floating note.
- Switching between light and dark appearance without replacing the active library/editor.
- Repeated application quit/relaunch with captured text, code, links, images, and referenced files still present.

Global Carbon registration and its application event handler were tested separately: registration succeeds, a native hotkey event reaches the correct callback once, and unregistering removes it. The release Settings UI also confirms both default shortcuts register without a conflict. The automation keyboard path targets a selected app and did not exercise macOS's physical global-hotkey dispatch; pressing Option-Space on a physical keyboard from another application remains a manual check. Launch-at-login registration/relogin and switching between actual Spaces also remain manual checks. Those settings were implemented, but login was left disabled during verification.

Image clipboard capture and file drag/drop were exercised using a private named native pasteboard and asynchronous native `NSItemProvider` fixtures, rather than changing the user's general clipboard or synthesizing a Finder drag. A passing service test is distinguished from an observed physical interaction.

Optional WidgetKit is deferred. This delivery includes the main app, desktop capture surface, and independent floating notes; it has no widget extension or cloud synchronization.

## Edge docking update — IdeaDock 1.1

The optimized 1.1 bundle passed all ten self-test output lines, strict deep signature verification, and Info.plist validation. Pure geometry checks cover every edge/corner, multiple display-coordinate layouts, threshold/overshoot behavior, handle fractions, safe restoration, and animation directions.

Native accessibility and screenshot checks verified a saved note tucked at Top and Bottom Left, side and top handle rendering, click restoration with the saved body intact, dragging a Right handle out into the desktop, and the saved corner handle surviving quit/relaunch. They also verified capture's grip context menu, Bottom docking in mini mode, the bottom handle surviving restart, restoration to the mini surface, and expansion back to full capture. A valid native frame slightly below the configured minimum exposed a restoration defect; the final build normalizes that frame rather than discarding its docked identity. The library correctly disables Dock Current Note while a library window is current.

Full capture's draft remained intact after click restoration during the same session. The isolated UI mode intentionally does not persist unsaved draft text across quit; normal mode continues to persist text drafts. Saved ideas remain in the isolated on-disk library across restarts.

App-local automation did not reliably move an original window through AppKit's WindowServer-backed `performDrag(with:)`; those header-drag attempts did not prove a physical system drag. Preview-following during a physical header drag, Escape during that gesture, physical multi-display and Spaces transitions, and Reduce Motion still require the manual check above. Native handle drag-out, menu docking, restoration, and stored docking identity were exercised separately. The normal user library and general clipboard were not used for the feature tests.

## Quick history update — IdeaDock 1.2

The packaged optimized 1.2 executable passed all eleven self-test output lines, including the final summary. The complete output is saved in [Self-test-results.txt](Self-test-results.txt). Native interaction checks used a copied, isolated fixture library under `/private/tmp` to avoid test-folder macOS privacy (TCC) checks. The normal user library was untouched.

Native accessibility and screenshot checks verified:

- All Notes and Today show captures chronologically with their timestamps. The editor distinguishes Captured from Last changed; opening and leaving an unchanged editor keeps its change time stable.
- Typed search finds notes across categories, keeps keyboard focus in the search field, and shows the correct hint for the available result. The optional native Categories section expands and collapses, and the Bug category remains browsable.
- The Last saved receipt opens its capture and clears a previously selected time filter. Command-K shows the three recent notes, supports note search, and opens the chosen result with Return.
- Editing and immediately switching notes, quitting, and reopening preserved the body `Pick this up later, without folders.`. Its original capture time stayed `12:39:56`, while Last changed showed `12:44:52` after the edit.

The 1.1 manual limitations above remain: physical global shortcuts, header drag/preview/Escape, physical multi-display and Spaces transitions, Reduce Motion, and launch-at-login/relogin were not established by these app-directed checks. WidgetKit remains deferred.
