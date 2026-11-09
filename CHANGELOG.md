# Changelog

All notable changes to Shuck are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Shuck uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Each release's notes on GitHub are its section below
(D-95).

## [Unreleased]

### Added

- Developer Junk now lists Xcode's DerivedData, one row for each project. Projects that Xcode has not built for 30 days
  or whose project is no longer on your Mac start selected, and nothing can be selected while Xcode is running. You can
  look and choose, but nothing is deleted from this page yet.

### Changed

- Move to Trash skips a file that another file replaced since the scan, such as an installer you downloaded again, and
  says so: "another file took its place since the scan".

### Fixed

- Move to Trash's review, Quick Look and Show in Finder now follow the folder order shown in grouped results.
- The time since a scan on the File Cleanup page now updates while the page stays open.
- Excluded folders no longer appear in personal-file results when another cleanup tool manages them.
- Restoring several versions of the same file together now asks whether to keep both or skip the extra versions.
- History shows an error when its data folder cannot be examined, instead of saying there is no history yet.

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
