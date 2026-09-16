# Changelog

## 1.1.0

Security: metadata is read out of an image, never by running it.

- Sync used to run every new AppImage with `--appimage-extract`, which is
  code execution on a file that merely landed in the folder. The squashfs
  image is now located from the ELF header and read with `unsquashfs` inside
  a `bubblewrap` sandbox (no network, no home, image read-only, time and
  memory caps). Nothing from an AppImage executes until the user launches it.
- The embedded desktop entry is accepted one field at a time: a known set of
  keys, one line each, control characters removed, lengths capped, unknown
  groups dropped. `Exec` is written by the plugin from the file path and the
  user's own `args`; the image's `Exec` flags and `[Desktop Action]` groups
  are no longer copied. An icon is kept only when it is under 4 MB and starts
  like a PNG, SVG or XPM.
- New dependency: `squashfs-tools`. Without it the plugin still syncs, with
  filename-derived names and a generic icon.


## 1.0.0

First release.

- Watches an AppImage folder with `inotifywait` and keeps
  `~/.local/share/applications` in step: entries appear when a file arrives and
  are removed when it goes.
- Builds each launcher entry from the desktop entry and icon embedded in the
  AppImage: `GenericName`, `Keywords` and their translations, `Comment`,
  `Categories`, `MimeType`, `StartupWMClass`, the flags its own `Exec` carried,
  and its `[Desktop Action]` groups. Falls back to a filename-derived name and
  a generic icon when an AppImage carries none.
- Bar widget listing every AppImage with its icon, size and filename, with a
  run and a rename button per row and in-place renaming; an empty name clears
  the override.
- Rows show the version the AppImage reports, and offer run-or-focus, rename,
  hide from the launcher, and delete-the-file behind a confirmation.
- An AppImage with a window open gets a focus button rather than a run button,
  matched on its window class, and a launch that dies within a few seconds
  reports its first error line instead of failing silently.
- Keyboard-first panel: the cursor spans the rows and both footer buttons,
  Enter runs or presses, and `r`, `h`, `Del`, `s` and `o` reach rename, hide,
  delete, sync and the folder directly.
- Overrides for name, extra `Exec` arguments, categories and visibility in
  `~/.config/omarchy/appimages.json`.
- Ids keep the case and separators of the filename, so two AppImages whose
  names differ only in those cannot collide onto one launcher entry.
- The folder watcher backs off when it cannot start or cannot stay up, rather
  than retrying a full sync every two seconds for the rest of the session.
- IPC on `appimages` (service) and `io.github.hpolthof.appimages` (widget), so
  the panel can be opened from a Hyprland keybinding.
