# Changelog

All notable changes to Shuck are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Shuck uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Each release's notes on GitHub are its section below
(D-95).

## [Unreleased]

### Added

- Shuck asks before it quits while it is moving, deleting, cleaning up or restoring items. If you choose Stop and Quit,
  it finishes the item it is working on and records it in History before it quits.
- Settings lists excluded folders. Add folders with the Add button and take them out with Remove. Shuck never lists,
  moves or deletes anything inside an excluded folder, or a folder that holds one, in any tool. Adding a folder hides
  its files from every list at once. A folder you remove is scanned again from the next scan on.
- Developer Junk also lists the node_modules folders of projects you have not changed for 30 days, one row for each
  project, in a group of their own. Shuck looks in your project folders only: Settings lists them, and starts with
  whichever of Developer, Projects, Code, src and repos exist in your home folder. A project needs a lockfile next to
  its node_modules, and Shuck lists only the top-most node_modules of a project. A project you worked on within 30 days
  starts unselected. So does one that patches packages with patch-package or depends on local folders with file:, and its
  row says why. Every row says that restoring node_modules needs npm install and an internet connection. Large Files and
  Old Files no longer list what is inside those node_modules folders.
- Before deleting or cleaning up a single item larger than a quarter of the space in use on your Mac, Shuck asks you a
  second time and names the item, since something that large is rarely just a cache.
- After deleting, cleaning up or moving items to the Trash, the summary shows how much free space your Mac actually
  gained, measured on the disk, next to Shuck's estimate, and explains why they can differ: local Time Machine
  snapshots, APFS clones, a tool's estimate, or other apps using space at the same time.
- Developer Junk now lists Xcode's DerivedData, one row for each project. Projects that Xcode has not built for 30 days
  or whose project is no longer on your Mac start selected, and nothing can be selected while Xcode is running. You can
  look and choose. Each row says that the project's Swift package checkouts go too, and that Xcode needs an internet
  connection to download them again.
- Developer Junk also lists Xcode's device support files, one row for each version of each platform. Every version
  except the newest of its platform starts selected, because Xcode copies the files again when you connect a device.
- Developer Junk also lists the iOS Simulator's caches, which start selected and are disabled while Xcode or Simulator
  is running.
- Developer Junk also lists your Xcode archives, one row for each, in a group of their own. They are your data: Apple says
  to keep the archive of every build you distribute, so none starts selected and Select All leaves them out. Choose each
  one yourself, then Move to Trash shows them in a list to review first. They go to the Trash, and History can put them
  back.
- Developer Junk has a Delete button. It shows one confirmation with the totals for each category, and a button to list
  every item, before anything is deleted. Deleted items don't go to the Trash, and History lists them as not
  restorable.
- Caches & Logs now lists the caches and logs your apps keep, in `~/Library/Caches`, `~/Library/Logs` and sandboxed
  apps' own caches, with a section for each app and its total size. A cache that nothing has changed in for 30 days, and
  a log for 7 days, starts selected. Caches that macOS itself writes are listed but never start selected, and neither
  does a cache whose app Shuck can't find on your Mac, since some apps keep more than a cache there; its row says so.
  Nothing can be selected while its app is running. Delete shows the same confirmation as Developer Junk and empties each
  folder without removing the folder. Caches that developer tools own, such as Homebrew's, stay with Developer Junk.
- Developer Junk lists the simulators that Xcode can no longer start (unavailable simulators), when your Mac has
  Xcode and simulators. Cleaning them up runs `xcrun simctl delete unavailable`, Xcode's own command; Shuck never deletes
  simulator data itself. The confirmation says "Clean up" for tool commands, and its size is shown as unknown. History
  shows the command that ran, the tool's path and what it printed. Shuck finds tools only where they are usually
  installed (`/usr/bin`, `/opt/homebrew/bin`, `/usr/local/bin`).
- Developer Junk lists npm's cache when npm is installed and has a cache in `~/.npm`. Cleaning it up runs
  `npm cache clean --force`, npm's own command, and the size shown is an upper estimate from the cache folder.
  Shuck starts `npm` offline and with its update check turned off.
- Developer Junk lists pip's cache when Homebrew's `pip` or `pip3` is installed and pip has a cache in
  `~/Library/Caches/pip`. Cleaning it up runs `pip cache purge`, pip's own command, with pip's check for a newer version turned off. Apple's
  own `pip3` is not used.
- Developer Junk lists Homebrew's cleanup when `brew` is installed and has downloads in
  `~/Library/Caches/Homebrew`. Cleaning it up runs `brew cleanup`, Homebrew's own command, which removes old
  versions of packages and old downloads and keeps the current ones. The size shown is the download cache only.
  Shuck starts `brew` with Homebrew's analytics and automatic update turned off.
- Large Files and Old Files mark files that iCloud keeps on your other devices, such as files in Desktop and Documents
  when iCloud syncs them, with "Synced". Move to Trash's review warns that moving them to the Trash also removes them
  from your other devices.

### Changed

- When you stop a developer tool, or Shuck stops one that runs too long, History now says that processes the tool
  started may still be running, since Shuck stops only the tool itself.
- Move to Trash skips a file that another file replaced since the scan, such as an installer you downloaded again, and
  says so: "another file took its place since the scan".
- Large Files and Old Files no longer list packages and folders that are only in iCloud and not downloaded to your Mac,
  as they already left out such files.
- A row that cannot be selected names the app that is running, such as "Xcode is running", instead of "App is running".
- Developer Junk shows each Xcode project's path under its name, so two projects with the same name can be told apart.
- Tool commands are shown as you would type them, such as `/opt/homebrew/bin/brew cleanup`, without quotes around every
  word.
- Large Files, Old Files, Developer Junk and Caches & Logs have Select All and Select None buttons. Select All never
  selects a row whose app is running.
- Old Files judges a file by the latest of when it was last opened, last changed and added to its folder, so a file
  that a script rewrites every day, or one you copied or downloaded recently, no longer looks old. The reason and the
  Last Opened column say which date decided: "Not opened", "Not modified" or "Added". For a package, such as a
  document bundle, a change to a file directly inside it counts as a change to the package.
- Move to Trash and Delete skip any item that changed after the scan, even when its size stayed the same, such as a
  file still being written or a cache an app has just written to, and say "modified since the scan".
- Large Files and Old Files no longer look inside a Git repository's own `.git` folder, so they never offer its packfiles,
  which the repository needs. They also leave out any disk mounted inside your home folder.

### Fixed

- If Shuck quits or crashes while it moves items to the Trash, History now finds the item that was being moved in the
  Trash and lets you restore it. Before, it showed the item as interrupted, with no way to put it back.
- Opening Shuck while it is already open brings the open window to the front instead of starting a second copy, so
  two copies can no longer clean up at the same time.
- Deleting a very deeply nested folder, such as some node_modules folders, no longer stops part-way. A Restore whose
  move fails no longer leaves empty folders behind.
- Stopping a cleanup at the moment a developer tool starts could make Shuck quit unexpectedly. It no longer does.
- Shuck no longer freezes for a moment when you click Move to Trash or Delete with thousands of items selected. The
  review opens as soon as Shuck has checked every item.
- Developer Junk and Caches & Logs say "Not accessible" when macOS keeps Shuck out of a folder they would list,
  instead of leaving it out without a word. Developer Junk's page now shows the note, as Caches & Logs' does.
- Move to Trash's review, Quick Look and Show in Finder now follow the folder order shown in grouped results.
- The time since a scan on the File Cleanup page now updates while the page stays open.
- Excluded folders no longer appear in personal-file results when another cleanup tool manages them.
- Restoring several versions of the same file together now asks whether to keep both or skip the extra versions.
- History shows an error when its data folder cannot be examined, instead of saying there is no history yet.

### Security

- Shuck now refuses to touch the simulators' devices and runtimes and Docker's disk image, which only `simctl` and
  Docker may change.
- Shuck refuses to move or delete a folder that directly holds a Photos, Music or TV library or a Time Machine backup,
  a folder it cannot read (shown as not accessible), and a disk or disk image mounted at the item itself.

## [0.1.1] - 2026-11-03

### Added

- A Stop button for scans. A stopped scan stays stopped until you click Scan.

### Changed

- Run summaries and History say why an item was skipped. An item Shuck may not read shows as "not accessible" instead
  of "missing", and a failure shows its error in words.
- Large Files remembers whether Group by Folder is on.
- Long result lists stay responsive while a scan adds rows.
- Shuck has one main window, and closing it quits Shuck. ⌘N no longer opens a second window that shared the first
  one's selection.

### Fixed

- Restore could move the wrong file. When a later run reused a trashed file's name in the Trash, restoring the earlier
  run moved the later run's file. Restore now checks that the file is the one Shuck trashed, and History shows any other
  as "Not restorable (Trash emptied)".
- Scans skipped folders they could not read without saying so, unless permission was the reason. The File Cleanup page
  now counts them: "Some folders could not be read".
- Scans now match protected names whatever their letter case, as Move to Trash does, so they no longer list items that
  Move to Trash would refuse.

### Security

- The system log no longer shows the names of files and folders that a scan could not list.
- History no longer reads its log through a symbolic link, which Shuck already refused when writing the log.

## [0.1.0] - 2026-11-02

### Added

- File Cleanup, with two sub-tools. Large Files lists files above a minimum size, grouped by top-level folder. Old Files
  lists files you haven't opened for a set period, oldest first.
- Move to Trash. You review every item before anything moves, and a summary says what happened to each one. You can
  stop a run while it moves items.
- A total on the File Cleanup page that counts each file once, even when both sub-tools list it.
- History, which lists every run with its items and their outcomes. Restore puts trashed items back, selected ones or
  all, and asks whether to keep both or skip when an item's original place is taken.
- Protected locations, such as system folders, are never touched, and every item is checked again just before it moves.

## [0.0.1] - 2026-11-02

### Added

- The app window with its sidebar, signed and notarized. No tools yet.

[Unreleased]: https://github.com/nutabi/shuck/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/nutabi/shuck/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/nutabi/shuck/compare/v0.0.1...v0.1.0
[0.0.1]: https://github.com/nutabi/shuck/releases/tag/v0.0.1
