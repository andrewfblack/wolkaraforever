# External game storage: implementation plan

Status: folder probe and opt-in disposable-file test implemented; USB-C game storage is **not implemented**. Do not move an
existing installation or replace its `Data` directory with a symlink.

## Goal and initial scope

Allow a user to choose a writable folder on a directly attached USB-C drive
before installing Forever, and keep the game installation there while keeping
the launcher, credentials, pairing state, and app preferences in the app
container. Do not automatically migrate or remove existing installations.
Never start an update or a guest when the chosen drive is unavailable.

Start with an **entire game root on one volume**, not a split `Data/` folder:
the current updater clones the root into a sibling staging directory and
activates it with one filesystem rename/swap. A split installation would
require a new transaction model and guest-path mapping. This first approach
still needs a real-device proof before any installation is directed at a drive.

## Existing code paths to change

- `wolkaraforever/WoW/WoWViewController.m`: on a new install the root defaults
  to `Documents/World of Warcraft`; existing installs use the library's
  working directory. Folder selection and persistent location configuration
  belong in the launcher, but must not take place during an update or session.
- `platform/launcher/App/AppLibrary.m`: profiles and stored records use paths
  relative to `Documents`; discovery, `workingDirectoryForApp:` and
  `executablePathForApp:` enforce that boundary. External app records need an
  explicit, separately validated storage source; changing this upstream
  component requires a narrow layer patch and maintainer review.
- `wolkaraforever/WoW/Installation.m`: inspection accepts only
  `TKAppSourceDocuments`; it must refuse to consider an unavailable external
  install ready, rather than treating it as missing and offering a fresh one.
- `wolkaraforever/WoW/Updater.m`: `cloneRoot:into:` requires `clonefile` and
  explicitly fails when private APFS clones are unavailable; activation uses
  `renamex_np(..., RENAME_SWAP)`. Its staging directory and capacity check
  must be on the **same selected volume** as the game. Prove both operations
  on the actual external filesystem before enabling writes. Do not silently
  fall back to full copies or cross-volume renames: those change update safety
  and free-space requirements.
- Guest startup and filesystem translation: resolve the chosen root while
  permission is active and keep access open for the entire game session.
  Audit all guest file opens, not just the launcher and metadata check; the
  original executable remains verified data and is not rewritten or signed.
- UI recovery, add-ons, diagnostics, `push_game.sh`, `remove_game.sh` and
  `preflight.sh`: each currently assumes game files live in the app's
  Documents folder. Keep device tools from deleting or overwriting a drive
  without an explicit, verified external-storage mode.

## Incremental milestones

1. **Read-only device probe (source implemented, device untested).** The
   Settings picker selects a folder, checks scoped access, filesystem and
   capacity, and stores an app-local bookmark rather than an absolute path.
   The Check action resolves the bookmark again, failing closed when it is
   stale or unavailable. Still test selecting a folder, unplugging/replugging,
   app restart, and revoked permission on a real device. The probe writes no
   WoW files; it does not test filesystem write capability or update safety.
2. **Transactional filesystem fixture (small-file probe implemented, device
   untested).** The opt-in Settings test uses a newly created disposable
   folder, verifies cloning does not mutate the source, checks atomic swap,
   and reports cleanup failure. Remaining: test interruption/recovery,
   filesystem identity and available capacity before and after the operation,
   and actual directory activation on the user's drive. A small-file pass is
   not sufficient to allow a real installation. Never target user game data.
3. **External installation records.** Add an explicit source type, validated
   relative paths, and app-local location reference. Preserve the existing
   Documents behavior for existing records. Prove that unavailable drives
   cannot be mistaken for a missing or ready install and that no path can
   escape the selected root. Cover discovery, import, and executable checks.
   Internal groundwork: `ExternalGameRecord` now validates an app-private
   bookmark and relative executable path, refuses missing media and symlink
   escapes, and retains the record when validation fails. The library source
   type, discovery, and launch integration are not yet connected, so this
   record alone never marks an installation ready or exposes Play.
4. **Installer and launch.** Route the complete Forever root, staging and
   capacity checks to the selected volume; hold scoped access for update,
   inspection and guest lifetime. Disable Play and updates when detached;
   cancel cleanly if detached mid-operation. Verify no action deletes the
   internal installation or the user's external files on failure.
5. **Device validation and UX.** Add explicit opt-in storage selection,
   disconnect/reconnect and recovery messaging, and update the install guide.
   Test fresh install, interrupted download, update, verification, launch,
   disconnect, and reinstall on a real iPad. Record the iPadOS version, drive
   filesystem, hardware, build revision and execution mode; do not claim game
   compatibility solely from fixture or simulator passes.

## Boundaries

- Files' ability to show a USB drive does not grant the game permanent access
  to arbitrary paths. The app must obtain user-selected folder access and
  verify it remains available at every operation boundary.
- External storage is removable and may be slower than internal flash. A
  successful download does not establish acceptable game I/O performance.
- No automatic migration, symlink workaround, binary patch, signing change,
  or game-memory instrumentation is part of this work.
