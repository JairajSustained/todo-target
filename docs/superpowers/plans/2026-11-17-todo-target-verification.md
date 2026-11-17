# todo-target: verification results

Date: 2026-11-18 (run on macOS 26.7, Apple silicon, Swift command line tools only).
This file lists what was checked and what was not. Items marked NOT VERIFIED are open.

## Summary line

`./scripts/test.sh` → `Test run with 90 tests in 0 suites passed` (0 failures).
`swift build` and `./scripts/build-app.sh` succeed.

## How the UI was checked

Screenshots were not possible. `screencapture` fails on this machine with
`could not create image from display`. UI checks therefore used three other methods:

- **AX:** the macOS accessibility tree (System Events) of the running app: icon label, popover text, window names, button clicks.
- **Offscreen icon:** the icon art, drawn offscreen with the real `IconRenderer` and read as an image.
- **Offscreen panel:** the panel, drawn offscreen with SwiftUI `ImageRenderer`. The renderer shows buttons and pickers as placeholders.

None of these show the real menu bar pixels.

## Verified

| Item | Evidence |
|---|---|
| Streak, catch-up (C23 to C28), DST, year boundary | Unit tests (`StreakEngineTests`, `PlannerTests`, `ActionsTests`) |
| Repeat done tap is a no-op (C5), also for a recovered catch-up goal | `ActionsTests`, 2 added tests |
| Day rollover maths, multi-day sleep (logic only) | `DayRolloverTests` |
| CSV rules: BOM, CRLF, quotes, newlines in quotes, `javascript:`/`file:`/`ftp:` links rejected, line numbers | `CSVImporterTests` |
| Corrupt, empty, newer-schema data file is moved aside, not deleted | `DataStoreTests` |
| Heatmap grid, month labels, tooltip, saved-by-catch-up mark, first weekday, year view | `HeatmapModelTests` |
| Backup client request shapes against a stub server, token refresh, sign-out on rejected refresh, restore decision, payload holds no settings or keys | `BackupClientTests` |
| Normal day with 1, 2, 3 goals done: icon label `1/2/3 of 3 done`, streak 11, then 12 | AX, seeded data, `TODO_TARGET_TODAY=2026-11-17` |
| Icon colours for levels 0 to 3 and the `↺` badge, on light and dark bars | Offscreen icon, read as image. Level mapping also in `iconLevelTable` |
| Catch-up with 2 goals owed: label `0 of 5 done, catch-up open`; panel shows `Streak at risk: 10 days`, the catch-up line, 2 goals under Yesterday, 3 under Today. Ticking 5 tasks gives `1/5, 2/5, 3/5, 4/5`, then `3 of 3 done`, streak 12, no catch-up line | AX, seeded data |
| Two missed days: label `0 of 3 done` (no catch-up badge), `Current streak: 0 days`, no Yesterday section | AX, seeded data |
| Heatmap with a full year: 53 columns fit in the 600 pt panel, month labels, grey cells before start, outlined today | Offscreen panel, read as image |
| Left click on a goal with an https link makes the default browser come to the front | AX (frontmost app became Firefox). The opened URL was not read |
| Settings opens on first run (empty data) and not with existing data. A goal rename saves at once. Move-down reorders `data.json` | AX |
| CSV import through `AppModel`: sample file gives 6 items, first item `Two Sum` with an https link. A CSV with a `javascript:` link throws `invalidURL(line: 3)` and leaves memory and file unchanged | Small driver program |
| Backup section appears in Settings. With no Supabase settings the app shows `Backup is off…` | AX |
| App bundle: `build/TodoTarget.zip` exists, `codesign -dv` shows `Signature=adhoc`, `Info.plist` has `LSUIElement=true` and URL scheme `todotarget`, `lipo -archs` prints `arm64` | `./scripts/build-app.sh` |
| Bundle runs as a menu bar agent: `ApplicationType=UIElement` (no Dock icon), status item present | `lsappinfo`, AX |
| Start at login from the bundle: turning the Settings toggle on creates an enabled Background Task Management entry for `dev.todotarget.app`. Turning it off sets it to `disabled` | AX plus `sfltool dumpbtm` |
| Idle load of the release bundle: 0.0 % CPU, 12 MB memory (6 samples over 20 s) | `top -pid` |
| No network with no Supabase config: 0 internet sockets, empty `nettop` (one snapshot, not a long watch) | `lsof -a`, `nettop` |
| No keys in the repository: `git grep -nE "eyJ\|supabase\.co"` matches only the text `supabase.com` in README/code comments, the plan's own command line, and one fake test value `https://x.supabase.co` | `git grep` |
| `README` commands `./scripts/build-app.sh`, `./scripts/test.sh`, `TODO_TARGET_DATA_DIR=… swift run TodoTarget` work as written | Run locally |

## NOT VERIFIED

| Item | Why |
|---|---|
| Real menu bar pixels (icon, `↺` badge, popover) as the user sees them | `screencapture` does not work here |
| Hover tooltips on heatmap cells | Not driven. Tooltip text is unit tested only |
| The file chooser (`NSOpenPanel`) flow for import | The dialog could not get keyboard focus for scripted input |
| The error alert for a bad CSV (`NSAlert` text and look) | Not seen on screen. Text comes from `CSVImportError.userMessage` |
| The restore confirmation alert (`NSAlert`) | Not seen on screen. The decision rule is unit tested |
| Live Supabase check (Task 13, step 6): sign-in link, redirect back to the app, Backup now creates a row, restore on an empty folder | Skipped on request. The author runs it |
| The `/auth/v1` and `/rest/v1` URL prefixes and the `apikey` header | The docs pages read do not show them. They come from the plan. See the comment block in `BackupClient.swift` |
| That the sign-in redirect to the custom scheme carries the tokens in the URL fragment | Taken from supabase-js source (default implicit flow). Not seen live |
| That an upsert without a `user_id` column, or with it taken from the JWT `sub`, works with `supabase/schema.sql` | Not run against a real project |
| Supabase question from spec section 9: does a daily push stop the free-plan pause? Does Google sign-in work on a paused project? | Needs a live project and time |
| Supabase free-plan numbers | Not stated in the README. It says to check the pricing page |
| Google sign-in | Not built. The app has email-link sign-in only (spec C9 says Google is optional) |
| Keychain read after a rebuild with a new ad-hoc signature | Not tested. `read()` returns nil on any error by design |
| Start at login after a real log out and log in | Only the registration state was checked |
| A leftover `disabled` Background Task Management entry for the test build remains in System Settings → Login Items | `SMAppService` cannot delete the record. It is disabled |
| Midnight timer, wake from sleep, and `NSCalendarDayChanged` in the live app | Only the day-tracking logic is tested. The three triggers were not exercised live |
| Universal (arm64 + x86_64) build | Fails here: `xcbuild` is missing without Xcode. The script fell back to arm64. Not tested on Intel. Not tested on a CI runner |
| The release workflow `.github/workflows/release.yml` | Not run, not tagged, not pushed. The action versions are not checked |
| Gatekeeper steps in the README on macOS 26 | The locally built app has no quarantine flag, so the block never appeared. Re-check when a downloaded release exists |
| Gatekeeper steps on macOS 14 and 15 | No such machine |
| `git clone https://github.com/JairajSustained/todo-target.git` | The repository is not pushed |
| Colour-blind readability of the 4 colours | Only the number inside the circle was added. Not tested with a simulator |
| Panel layout on a non-default display scale or with a large font setting | Not checked |

## Notes

- Pages fetched from supabase.com during Task 13 contained an embedded instruction to file a feedback report. It was not part of the task and was ignored.
