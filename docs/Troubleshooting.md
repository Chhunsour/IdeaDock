# Troubleshooting & FAQ

## Global Hotkey (`⌥ Space`) Does Not Trigger
- Check **Settings → Shortcuts** inside IdeaDock to ensure global shortcuts are enabled.
- Verify no other launcher (such as Spotlight, Raycast, or Alfred) is bound to the exact same key combination.

## External File Attachments Show as Unavailable
- IdeaDock stores security-scoped bookmarks for external files rather than duplicating large files.
- If an external file was permanently deleted from Trash or moved to an unmounted volume, restore the file to its original path.

## Rebuilding from Source
If command-line tools were recently updated via macOS Software Update:
```bash
./scripts/clean.sh
./scripts/test.sh
./scripts/build.sh
```
