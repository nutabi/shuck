# Scan performance

A personal-files scan that is not cancelled logs one line in the `FileCleanup` category, such as `Scanned 812345 entries in 74.2 seconds` (NFR-PERF-002, D-78). An entry is a file or folder the scan looked at. A package or a device backup counts as one entry, although measuring its size reads everything inside it.

The measurements in `docs/archive/progress.md` come from the owner's own home folder. Agents never scan a real home folder (safety rule 4), so an agent gives the owner these steps instead of running them:

1. Build the release app: `SHUCK_SIGN_IDENTITY=- scripts/build-dmg.sh --skip-notarization` writes `build/release/Shuck.app`. A debug build is not optimized, so its times say little.
2. Open `build/release/Shuck.app` and click Large Files, which starts the scan. macOS asks once about each protected folder, such as Documents, and the scan waits for the answer. When the scan has finished, click Scan to run it again.
3. Read both lines with `/usr/bin/log show --last 1h --style compact --predicate 'process == "Shuck" AND subsystem == "me.nutabi.shuck" AND eventMessage BEGINSWITH "Scanned"'` and record the second. The process filter leaves out engine tests, which log the same line. In zsh, `log` is a shell builtin, so the command needs the full path.
4. While Shuck is still open, read its peak memory with `vmmap --summary $(pgrep -x Shuck) | grep 'Physical footprint'` and record the peak (NFR-PERF-003). Only 25 MB of the baseline's 17.1 GB peak was still allocated after the scan, so the current footprint says little.
