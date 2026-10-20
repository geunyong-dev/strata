# Strata

Strata is a native macOS storage analyzer for developer machines. It explains
where space is going without collapsing unknown files into “System Data,” and
recognizes toolchains such as Docker, Xcode, npm, Gradle, Homebrew, Android,
CocoaPods, Cypress, and Electron.

Storage analysis is read-only: it scans every top-level area
of the writable macOS data volume, reports paths blocked by privacy permissions,
then analyzes known developer storage locations and estimates reclaimable space.
Deletion runs from the pinned action bar after separate verification and explicit confirmation.

Docker and Xcode diagnostics use fixed executable paths and argument arrays—no
shell command construction. Read-only commands have a 15-second timeout so an
unresponsive daemon cannot stall the full scan indefinitely.
Each command owns a unique, owner-only temporary directory so concurrent
diagnostics cannot mix output or delete one another's files.

Project scans look in common development roots such as `~/Documents/workspace`,
`~/Developer`, and `~/Projects`. Recognized generated directories include
`node_modules`, `.next`, `.build`, `target`, `.venv`, `build`, `dist`, `Pods`,
and common project caches. Nested artifacts are counted by their first matching
parent so dependency trees are not presented twice.
Names alone do not establish that contents are generated. Nearby manifests,
lockfiles and tool markers provide supporting evidence shown in item details.
Unconfirmed or partially unreadable candidates are caution-rated and not selected
by default. Generic build/output/cache folders remain unconfirmed even when a
project manifest is present. Evidence is heuristic, not a guarantee that a folder
contains no user-authored files; previously confirmed evidence is rechecked before cleanup.

## Cleanup plans and dry runs

Scan results are converted into selectable cleanup actions. Safe actions are
selected by default; caution and dangerous actions always require explicit
selection. Before execution, previews use the following checks:

- Docker reclaimable space is refreshed with `docker system df`.
- Simulator runtime removal is verified with `simctl runtime delete --dry-run`.
- Project artifacts are remeasured and checked for changes.

Cleanup execution is gated behind a fresh dry run and a typed Korean confirmation
phrase. Project artifacts move to the macOS Trash; Docker caches/images and
Simulator runtimes use fixed argument arrays without a shell. Dangerous actions,
including Docker volume pruning, are never executed automatically. Before/after
available-space measurements and per-action results are stored locally in
`~/Library/Application Support/Strata/cleanup-history.json`.

## Run

Requirements: macOS 14 or later and a Swift 6.2 toolchain (Xcode 26 or later).

```bash
swift run Strata
```

You can also open `Package.swift` in Xcode and run the `Strata` scheme.

For a local Release app bundle, run `bash scripts/package-local.sh`. It creates
`dist/Strata.app` with an ad-hoc bundle signature and refuses to overwrite an
existing output. This is not a notarized external distribution. See
[local installation](docs/local-installation.md) and
[validation status](docs/local-validation-2026-09-28.md).

## Accuracy model

- Uses allocated bytes, not logical file size, so sparse files are not inflated.
- Does not follow symbolic links.
- Only prunes descendants of real directories; ignoring a link or excluded file
  must not suppress sibling files. Regression tests cover bundle-like link layouts.
- Counts unreadable paths once per measurement, not once per failed operation.
- Retries interrupted (`EINTR`) metadata reads and directory enumeration at most
  twice. Enumeration retries restart that root with shared file identities to
  prevent counting bytes twice; they may take additional time. Access denial is
  not retried or hidden. Raw errors and retry events remain in diagnostic logs.
- Stops at filesystem boundaries, preventing mounted simulator runtimes and
  other volumes from being counted twice.
- Deduplicates hard links by device and inode.
- Keeps the scan on the macOS data volume and skips external, network, and
  automounted filesystems.
- APFS clone sharing cannot be measured exactly with public file APIs; Strata
  marks results as estimates rather than claiming byte-perfect clone accounting.

## Privacy permissions

Each production scan writes a local JSONL diagnostic log under
`~/Library/Logs/Strata/scan-*.jsonl`. Logs include app version/path, OS version,
throttled progress, file-error paths and error codes, permission probes, measurement
summaries and completion/cancellation/failure status. No file contents are logged
or uploaded. Files are owner-only (0600); paths may contain personal names.
Schema 2 also records ordinary free capacity, important-usage capacity (null when
unavailable), the displayed capacity basis and the folder-measurement scope.
Each scan is capped at 10,000 regular events plus final summary/status, with an
omitted-event count. Logs are not automatically deleted. A missing final event
can indicate an interrupted run; it does not prove a crash. Save failures appear
in the app. When reporting issues, the assistant can inspect the latest local logs
without requiring manually copied paths. Only scans after this update are logged.

Strata probes a small set of macOS-protected folders using metadata-only reads.
When access is denied, the dashboard explains that results are incomplete and
offers a shortcut to the Full Disk Access pane in System Settings. macOS does not
provide a public API that directly reports Full Disk Access status, so the app
labels this check as an inference.

## Safety

Scanning is read-only. Suggested actions are classified as safe, caution, or
dangerous, and sensitive AI conversation/model locations are explicitly out of
scope.

## Geologic design

Storage overview and cleanup now share one screen, without 조회 / 삭제 tabs. The header and
body share the same 220-point core column and 28-point content inset.
The core panel uses rock textures, an adaptive capacity ruler and external
labels connected to proportionally sized bands. Free space is at the top;
unclassified used space is separate. When folder measurements exceed reported
used capacity, the chart explicitly switches to measured-only proportions.
Tool estimates are never added into this visualization. Up to five area bands
are shown; overflow areas remain individually accessible through a popover.
App and System folder labels refer to paths, not macOS Storage category totals.
The storage card's information button explains ordinary free versus important-usage
capacity; the primary chart continues to prefer ordinary free capacity.
Clicking a band or label shows that area's measured details above the cleanup list.
Path-backed cleanup candidates are filtered by the selected core area. Unlocated
command-based resources remain in a separate Mac-wide section. Group selection
only changes that visible group; selections in other areas remain explicitly
counted in the fixed action bar and included in the confirmation list.

During scanning, throttled file-enumeration updates (about 250 ms) populate the
core with provisional measurements, including the currently scanned area.
Pending/unclassified used space is not presented as free space. The activity
view shows the current phase/path, inspected volume item count, completed
top-level areas, elapsed time and time since the last real update. No synthetic
percentage or ETA is shown. Diagnostics and project/cache analysis continue
after volume enumeration; cleanup stays unavailable until the final snapshot.
Scanning can be cancelled: enumeration and running commands observe cancellation,
partial results are discarded, and a previous completed snapshot is restored.
A blocked OS filesystem call must return before cooperative cancellation proceeds.
Starting a new scan invalidates earlier cleanup verification.

The top status bar opens cleanup history even before scanning. The latest 50 runs
are stored newest-first with expandable per-item results. Read/write failures are
reported; corrupt history files are not silently overwritten.

Unclassified-space diagnostics use read-only diskutil property-list output for
APFS containers, sibling volumes and system/data snapshots. Confirmed observations,
unavailable data and possible causes are separated. Snapshot count is not a byte
estimate; shared blocks and exclusive reclaimable space remain unquantified.
The dashboard keeps only a short status and next step. A separate readable sheet
explains the result in plain language, with technical evidence collapsed by default.
No snapshot deletion or thinning is performed. See Apple's
[APFS snapshot guide](https://support.apple.com/guide/disk-utility/dskuf82354dc/mac)
and [APFS space-sharing explanation](https://support.apple.com/guide/mac-help/sysp560a2952/mac).

Cleanup selection uses divider-separated full-width rows with a leading check
indicator; the entire row remains a Button target. A group header selects/deselects that group;
its separate chevron only collapses/expands it. Detail and copy controls never
toggle selection. The action bar remains pinned outside the scroll view, even
with zero selection. Execution remains a separate verified confirmation flow.

First use checks protected-folder readability and offers permission setup,
rechecking, or explicit limited-mode continuation. A compact status remains
visible for the current measurement. Permission checks are probes, not proof of
access to every file. Old snapshots remain limited until a fresh scan succeeds.
The card and core share one available-capacity basis (ordinary free capacity
when present, important-usage capacity only as a labeled fallback). Permission
cannot explain every unclassified byte or guarantee its disappearance.

Dark is the initial appearance; the header menu offers light and system modes.
Colors live in `StrataTheme.swift`. Cards use 4-point corners, numbers use
tabular figures, and safe/caution badges use neutral icons and text.
Irreversible consequences use the iron-oxide signal color.

Paths and operation details expand progressively; operation text can be copied.
The first completed scan reveals the core bottom-to-top over 1.2 seconds.
Refreshed measurements update band sizes over 0.4 seconds. Reduce Motion
disables animation. The confirmation sheet does not animate its content.

Measured size, estimated reclaimable size, and observed free-space change are
different quantities. Trash moves do not immediately release disk space. Age
labels describe available usage records and never establish deletion safety.
IBM Plex and a custom ammonite icon are not bundled; native type and symbols
are used. Selection controls retain Button keyboard behavior and announce their
selection state to accessibility clients. Dark/light offscreen AppKit previews
can be generated with `STRATA_RENDER_PREVIEWS=1 swift test` in
`/private/tmp/strata-core-previews` (fixture data, no cleanup operations).
