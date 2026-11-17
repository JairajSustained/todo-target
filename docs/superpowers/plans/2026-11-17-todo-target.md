# todo-target Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar app with 3 daily goals, a red-to-green icon, a streak with one-day catch-up, a yearly heatmap, and an optional Supabase backup.

**Architecture:** A pure-logic Swift library (`TodoTargetCore`) holds all rules and is fully unit tested. A thin AppKit/SwiftUI executable (`TodoTarget`) shows the status item, panel, and settings. The app is built with Swift Package Manager and a shell script that makes the `.app` bundle. Full Xcode is not installed.

**Tech Stack:** Swift 6.3, SwiftPM, Swift Testing (`import Testing`), AppKit `NSStatusItem` + `NSPopover`, SwiftUI, `URLSession`, Keychain, `SMAppService`. Minimum macOS 14.

**Test harness note (Task 1):** XCTest is not installed with the command line tools. Swift Testing is installed, but SwiftPM does not find it by itself. Run tests with `./scripts/test.sh` instead of plain `swift test`. The script passes the framework paths and takes the same arguments (for example `--filter ModelsTests`).

**Spec:** `docs/superpowers/specs/2026-11-17-todo-target-design.md` (decision IDs D1 to D15 and C1 to C34 are cited below).

## Global Constraints

- Exactly 3 goals. Array order is the priority order (D2, C14).
- Icon levels: 0 red, 1 orange, 2 yellow-green, 3 green (D4). The streak counts only on 3 of 3 (D5).
- The day ends at local midnight (C1). Day keys come from `Calendar`, never from 86400-second maths.
- One done mark per goal per day. A second tap does nothing (C5). Undo is allowed only on the day the mark was made (C4).
- Left click opens the first owed task (D6). Right click opens the panel (D6b). No reminders (D7).
- Local data is the main copy (D8). The repository holds no keys (D9). Backup is per-user Supabase (C19, C20).
- Minimum macOS version 14. Ad-hoc signed, not notarized (C18). License MIT (D12).
- Local data path: `~/Library/Application Support/todo-target/data.json` (C13).
- Only `http` and `https` links are ever opened.
- Never push to a remote, and never create a GitHub repository, without the author's explicit approval.
- End each commit message with: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`

## Review Focus

1. DST and time-zone days: a streak across a 23-hour day must count each calendar day once. Test in Task 3.
2. The Mac sleeps over midnight or the app starts the next day: "today" must refresh with no restart. Test in Task 9.
3. CSV with a byte order mark, CRLF, quoted commas, or a `javascript:` or `file:` link: parse it correctly or reject it. Never open a non-web link. Test in Task 6.
4. A corrupt, empty, or newer-schema data file: do not crash and do not lose the file. Test in Task 7.
5. "Restore from backup" on a Mac that has data: never replace local data without a confirmation. Test in Task 13.

---

## File Structure

```
Package.swift                          targets: TodoTargetCore, TodoTarget, TodoTargetCoreTests
LICENSE  README.md  .gitignore
.github/workflows/release.yml          tag push -> build zip -> GitHub Release
scripts/build-app.sh                   builds build/TodoTarget.app and build/TodoTarget.zip
resources/Info.plist                   LSUIElement, URL scheme, min macOS
examples/sample-list.csv   supabase/schema.sql
Sources/TodoTargetCore/
  DayKey.swift  Models.swift  StreakEngine.swift  Actions.swift  Planner.swift
  CSVImporter.swift  DataStore.swift  HeatmapModel.swift  DayRollover.swift  Clock.swift
  Backup/BackupPayload.swift  Backup/TokenStore.swift  Backup/BackupClient.swift
Sources/TodoTarget/
  main.swift  AppDelegate.swift  AppModel.swift
  StatusItemController.swift  IconRenderer.swift
  PanelView.swift  HeatmapView.swift  SettingsView.swift
  LaunchAtLogin.swift  URLSchemeHandler.swift  BackupCoordinator.swift
Tests/TodoTargetCoreTests/             one test file per core file, plus Fixtures.swift
```

---

### Task 1: Package scaffold and test harness

**Files:**
- Create: `Package.swift`, `.gitignore`, `LICENSE`, `Sources/TodoTargetCore/DayKey.swift` (empty stub), `Sources/TodoTarget/main.swift` (prints nothing, exits), `Tests/TodoTargetCoreTests/SmokeTests.swift`

**Interfaces:**
- Produces: library target `TodoTargetCore`, executable target `TodoTarget` (depends on the library), test target `TodoTargetCoreTests`. Platform `.macOS(.v14)`.

- [ ] **Step 1: Write the smoke test** in `SmokeTests.swift`: `@Test func harnessRuns() { #expect(1 + 1 == 2) }` with `import Testing` and `@testable import TodoTargetCore`.
- [ ] **Step 2: Create the package files.** `LICENSE` is MIT with `Copyright (c) 2026 todo-target contributors`. `.gitignore` lists `.build/`, `build/`, `.DS_Store`, `*.xcodeproj`. Run `git init -b main` in the project folder.
- [ ] **Step 3: Run** `swift test`. Expected: 1 test passes with only the command line tools. If Swift Testing does not run, switch the test files to XCTest, and record the change in the plan header.
- [ ] **Step 4: Run** `swift build`. Expected: builds both targets.
- [ ] **Step 5: Commit** `chore: scaffold package and test harness`. Include `docs/` in this commit.

### Task 2: DayKey, models, and test fixtures

**Files:**
- Create: `Sources/TodoTargetCore/DayKey.swift`, `Sources/TodoTargetCore/Models.swift`
- Test: `Tests/TodoTargetCoreTests/ModelsTests.swift`, `Tests/TodoTargetCoreTests/Fixtures.swift`

**Interfaces:**
- Produces (all `public`, `Sendable`):
  - `struct DayKey: Hashable, Comparable { init(date: Date, calendar: Calendar); init?(string: String); var string: String /* "yyyy-MM-dd" */; func adding(days: Int, calendar: Calendar) -> DayKey; func date(calendar: Calendar) -> Date; var year: Int; var month: Int; var day: Int }`
  - `struct ListItem: Codable, Equatable { var group: String; var title: String; var url: URL? }`
  - `struct Goal: Codable, Equatable, Identifiable { var id: UUID; var name: String; var items: [ListItem]; var position: Int }`
  - `struct Completion: Codable, Equatable { var itemIndex: Int?; var doneOn: String }` (`doneOn` is a `DayKey.string`)
  - `struct DayRecord: Codable, Equatable { var completions: [String: Completion] }` (key is `goal.id.uuidString`)
  - `struct Settings: Codable, Equatable { var launchAtLogin: Bool = true; var supabaseURL: String?; var supabaseAnonKey: String? }`
  - `struct AppData: Codable, Equatable { var schemaVersion: Int = 1; var goals: [Goal]; var days: [String: DayRecord]; var firstUseDay: String?; var settings: Settings; static func pristine() -> AppData; var isPristine: Bool }`. `pristine()` has 3 goals named "Goal 1" to "Goal 3", no days, `firstUseDay == nil`. `isPristine` is true only when `days` is empty, `firstUseDay == nil`, and every goal has its default name and an empty `items` list.
  - Test helper `Fixtures.make(own: [String: Set<Int>] = [:], recovered: [String: Set<Int>] = [:], firstUse: String, lists: [Int: [ListItem]] = [:]) -> AppData` and `Fixtures.goalIDs: [UUID]` (3 fixed UUIDs), `Fixtures.utc: Calendar` (Gregorian, UTC), `Fixtures.day(_ s: String) -> DayKey`. In `own`, slot `i` is done on that day. In `recovered`, slot `i` has `doneOn` equal to the next day.

- [ ] **Step 1: Write failing tests** in `ModelsTests.swift`:
```swift
@Test func dayKeyRoundTrip() { #expect(DayKey(string: "2026-11-17")?.string == "2026-11-17") }
@Test func dayKeyRejectsBadStrings() { #expect(DayKey(string: "2026-13-01") == nil); #expect(DayKey(string: "x") == nil) }
@Test func addingDaysCrossesMonthAndYear() {
  #expect(Fixtures.day("2025-12-31").adding(days: 1, calendar: Fixtures.utc).string == "2026-01-01")
  #expect(Fixtures.day("2026-03-01").adding(days: -1, calendar: Fixtures.utc).string == "2026-02-28") }
@Test func appDataJSONRoundTrip() throws { let d = AppData.pristine(); #expect(try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(d)) == d) }
@Test func pristineHasThreeGoals() { #expect(AppData.pristine().goals.count == 3); #expect(AppData.pristine().isPristine) }
@Test func renamedGoalOrImportedListIsNotPristine() { var d = AppData.pristine(); d.goals[0].name = "DSA"; #expect(!d.isPristine) }
```
- [ ] **Step 2: Run** `swift test --filter ModelsTests`. Expected: FAIL, types not defined.
- [ ] **Step 3: Implement the types** above. `adding(days:)` uses `calendar.date(byAdding: .day, ...)`.
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Commit** `feat: add day key and data models`.

### Task 3: StreakEngine (catch-up rules C2 to C4, C23 to C26)

**Files:**
- Create: `Sources/TodoTargetCore/StreakEngine.swift`
- Test: `Tests/TodoTargetCoreTests/StreakEngineTests.swift`

**Interfaces:**
- Consumes: Task 2 models and fixtures.
- Produces:
  - `struct CatchUp: Equatable { var day: DayKey /* yesterday */; var owedGoalIDs: [UUID] /* goals with no completion on that day */ }`
  - `struct StreakState: Equatable { var current: Int; var atRisk: Int?; var best: Int; var activeDays: Set<DayKey>; var catchUp: CatchUp? }`
  - `enum StreakEngine { static func evaluate(data: AppData, today: DayKey, calendar: Calendar) -> StreakState }`

**Rules the implementation must follow.** `own(d)` is the number of goals with a completion on `d` whose `doneOn == d`. `full(d)` means `own(d) == 3`. `recoveredFull(d)` means all 3 goals have a completion on `d` and `full(d)` is false. `counted(d) = full(d) || (recoveredFull(d) && full(d+1))`. `current` is the run of counted days ending today if `counted(today)`, else the run ending yesterday, else 0. `catchUp` is non-nil only when yesterday `Y` is not counted and `counted(Y-1)` is true. `atRisk` is the run ending at `Y-1` when `catchUp` is non-nil, else nil. `best` is the longest counted run, and at least `current`. `activeDays` is the set of counted days. Scan from `firstUseDay` to `today`. This "streak must be alive" rule for offering catch-up is the assistant's call (spec C24 is silent on it). Report it to the author.

- [ ] **Step 1: Write failing tests.** Today is `2026-11-17` unless noted. `full(a...b)` means own `{0,1,2}` for each day in the range.
```swift
@Test func openTodayDoesNotBreakStreak()   // full 11-06...11-16, today empty
  { #expect(s.current == 11); #expect(s.atRisk == nil); #expect(s.catchUp == nil) }
@Test func fullTodayAddsOne()              // same, today full
  { #expect(s.current == 12) }
@Test func missedDayOpensCatchUpWithAtRiskStreak()  // full 11-06...11-15, 11-16 own {0}, today empty
  { #expect(s.current == 0); #expect(s.atRisk == 10); #expect(s.catchUp?.day == day("2026-11-16"))
    #expect(s.catchUp?.owedGoalIDs == [goalIDs[1], goalIDs[2]]) }
@Test func fullCatchUpPlusFullTodayGivesTwelve()    // full 11-06...11-15, 11-16 recovered {0,1,2}, today full
  { #expect(s.current == 12); #expect(s.catchUp == nil); #expect(s.activeDays.contains(day("2026-11-16"))) }
@Test func recoveredButTodayIncompleteKeepsCatchUpOpen() // 11-16 own {0} recovered {1,2}, today own {0,1}
  { #expect(s.catchUp != nil); #expect(s.catchUp?.owedGoalIDs == []); #expect(s.atRisk == 10); #expect(s.current == 0) }
@Test func noCatchUpWhenNoStreakToSave()   // firstUse 11-16, 11-16 empty
  { #expect(s.catchUp == nil) }
@Test func twoMissedDaysBreakStreak()      // full through 11-14, 11-15 and 11-16 empty
  { #expect(s.current == 0); #expect(s.catchUp == nil); #expect(s.atRisk == nil) }
@Test func bestTracksLongestRun()          // full 5 days, gap, full 3 days ending yesterday
  { #expect(s.best == 5); #expect(s.current == 3) }
@Test func streakSpansYearBoundary()       // full 2025-12-29...2026-01-02, today 2026-01-03
  { #expect(s.current == 5) }
@Test func streakAcrossDSTChange()         // New_York calendar, full 2026-03-06...03-09, today 03-10 full
  { #expect(s.current == 5) }
```
- [ ] **Step 2: Run** `swift test --filter StreakEngineTests`. Expected: FAIL, `StreakEngine` not defined.
- [ ] **Step 3: Implement** `StreakEngine.evaluate` per the rules. Walk days with `DayKey.adding(days:calendar:)`.
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Commit** `feat: add streak engine with catch-up`.

### Task 4: Actions (mark done, undo, list advance)

**Files:**
- Create: `Sources/TodoTargetCore/Actions.swift`
- Test: `Tests/TodoTargetCoreTests/ActionsTests.swift`

**Interfaces:**
- Consumes: `StreakEngine.evaluate`, models.
- Produces:
  - `enum ActionError: Error, Equatable { case notAllowed, unknownGoal }`
  - `enum Actions { static func markDone(_ data: inout AppData, goalID: UUID, forDay: DayKey, today: DayKey, calendar: Calendar) throws; static func undo(_ data: inout AppData, goalID: UUID, forDay: DayKey, today: DayKey, calendar: Calendar) throws }`

**Rules.** `markDone` is allowed when `forDay == today`, or when `forDay == yesterday` and `StreakEngine` reports `catchUp` with `goalID` in `owedGoalIDs`. Anything else throws `.notAllowed`. A goal already done on `forDay` makes `markDone` return with no change (C5). A new completion has `itemIndex = position` when `position < items.count`, else `nil`. It sets `doneOn = today`. When `itemIndex` is non-nil, `position += 1`. The first call sets `firstUseDay = today` if nil. `undo` removes a completion only when `doneOn == today` and it is the latest completion of that goal (`itemIndex == nil` or `itemIndex == position - 1`). Otherwise it throws `.notAllowed`. Undo sets `position = itemIndex` when non-nil.

- [ ] **Step 1: Write failing tests:**
```swift
@Test func markDoneRecordsCompletionAndAdvancesList()   // goal 0 has 3 items; after markDone: position == 1, completion.itemIndex == 0
@Test func markDoneTwiceIsNoOp()                        // second call: data equal to data after first call
@Test func undoRestoresPosition()                       // markDone then undo: data.goals[0].position == 0, no completion
@Test func undoBlockedWhenLaterCompletionExists()       // catch-up goal 1 for yesterday (item 0), then today goal 1 (item 1); undo yesterday throws .notAllowed
@Test func catchUpOnlyForOwedGoalAndOnlyYesterday()     // forDay two days ago throws; forDay yesterday with no streak throws; goal not owed throws
@Test func completedListGivesNilItemIndex()             // 1-item list, two completions on two days: second itemIndex == nil, position stays 1
@Test func pastDayCompletionCannotBeUndone()            // completion with doneOn yesterday; undo today throws
@Test func firstMarkSetsFirstUseDay()
```
- [ ] **Step 2: Run** `swift test --filter ActionsTests`. Expected: FAIL.
- [ ] **Step 3: Implement** the two functions per the rules.
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Commit** `feat: add mark-done and undo actions`.

### Task 5: Planner (owed tasks, progress, icon level)

**Files:**
- Create: `Sources/TodoTargetCore/Planner.swift`
- Test: `Tests/TodoTargetCoreTests/PlannerTests.swift`

**Interfaces:**
- Consumes: `StreakEngine`, models.
- Produces:
  - `struct OwedTask: Equatable { var goalID: UUID; var slot: Int; var forDay: DayKey; var isCatchUp: Bool; var item: ListItem? }` (`item` is `goal.items[goal.position + k]` when in range, where `k` is the number of earlier tasks in the same list for the same goal. A goal owed yesterday and due today therefore shows consecutive items, as in spec C27)
  - `enum Planner { static func owedTasks(data: AppData, today: DayKey, calendar: Calendar) -> [OwedTask]; static func nextTask(...) -> OwedTask?; static func progress(data: AppData, today: DayKey, calendar: Calendar) -> (done: Int, total: Int); static func iconLevel(done: Int, total: Int) -> Int }`

**Rules.** `owedTasks` lists catch-up tasks first (goals in `catchUp.owedGoalIDs`, priority order), then today's goals without an own completion, in priority order. `progress.total` is `3 + (catchUp == nil ? 0 : 3 - own(yesterday))`. `progress.done` is `own(today) + recovered completions of yesterday` while `catchUp` is open, else `own(today)`. `iconLevel`: 0 if `done == 0`; 3 if `done >= total`; 1 if `done/total < 0.5`; else 2.

- [ ] **Step 1: Write failing tests:**
```swift
@Test func catchUpTasksComeFirst()       // Y own {0}, streak alive, today empty: owedTasks.map(\.isCatchUp) == [true,true,false,false,false]; slots == [1,2,0,1,2]
@Test func nextTaskSkipsDoneGoals()      // today own {0}: nextTask.slot == 1
@Test func nextTaskNilWhenAllDone()      // today own {0,1,2}, no catch-up
@Test func taskItemComesFromListPosition() // goal 0 position 1: nextTask.item?.title == items[1].title
@Test func goalOwedOnTwoDaysShowsConsecutiveItems() // goal 1 owed yesterday, position 0, 3 items: catch-up task item == items[0], today's task item == items[1]
@Test func itemIsNilWhenListIsExhausted()           // position == items.count: item == nil
@Test func progressInCatchUp()           // Y own {0}, recovered {1}, today own {0}: progress == (2, 5)
@Test func progressNormalDay()           // today own {0,1}: progress == (2, 3)
@Test func iconLevelTable() {
  for (d, t, l) in [(0,3,0),(1,3,1),(2,3,2),(3,3,3),(1,5,1),(2,5,1),(3,5,2),(4,5,2),(5,5,3)] { #expect(Planner.iconLevel(done: d, total: t) == l) } }
```
- [ ] **Step 2: Run** `swift test --filter PlannerTests`. Expected: FAIL.
- [ ] **Step 3: Implement** `Planner`.
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Commit** `feat: add planner for owed tasks and icon level`.

### Task 6: CSV importer (C6, C7)

**Files:**
- Create: `Sources/TodoTargetCore/CSVImporter.swift`, `examples/sample-list.csv`
- Test: `Tests/TodoTargetCoreTests/CSVImporterTests.swift`

**Interfaces:**
- Produces:
  - `enum CSVImportError: Error, Equatable { case missingHeader, missingColumn(String), emptyTitle(line: Int), invalidURL(line: Int) }`
  - `enum CSVImporter { static func parse(_ text: String) throws -> [ListItem] }`
  - `extension Goal { mutating func replaceList(_ items: [ListItem], keepPosition: Bool) }` (C17: reset to 0 unless `keepPosition`; clamp to `items.count`)

**Rules.** The first non-blank row is the header. Columns `group` and `title` are required. `url` is optional. Header names are case-insensitive. Extra columns are ignored. Blank lines are skipped. Strip a leading BOM. Accept LF and CRLF. Support RFC 4180 quoted fields (commas, doubled quotes, newlines). A present `url` must parse as an absolute `http` or `https` URL, else `invalidURL`.

- [ ] **Step 1: Write failing tests:**
```swift
@Test func parsesBasicRows()            // "group,title,url\nTrees,Max Depth,https://x.dev/1\n" -> 1 item, url == https://x.dev/1
@Test func urlIsOptional()              // header "group,title" -> items[0].url == nil
@Test func handlesBOMAndCRLF()
@Test func handlesQuotedCommaAndQuote() // "\"Trees, binary\",\"Say \"\"hi\"\"\"" -> group "Trees, binary", title "Say \"hi\""
@Test func rejectsMissingTitleColumn()  // throws .missingColumn("title")
@Test func rejectsEmptyTitle()          // throws .emptyTitle(line: 2)
@Test func rejectsNonWebLinks()         // "javascript:alert(1)", "file:///etc/passwd", "ftp://x" each throw .invalidURL(line: 2)
@Test func replaceListResetsPositionUnlessKept()
```
Also create `examples/sample-list.csv` with a header and 6 rows under 2 groups, all `https://example.com/...` links.
- [ ] **Step 2: Run** `swift test --filter CSVImporterTests`. Expected: FAIL.
- [ ] **Step 3: Implement** a small hand-written RFC 4180 tokenizer. Do not add a dependency.
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Commit** `feat: add CSV list importer`.

### Task 7: DataStore (C13)

**Files:**
- Create: `Sources/TodoTargetCore/DataStore.swift`
- Test: `Tests/TodoTargetCoreTests/DataStoreTests.swift`

**Interfaces:**
- Produces: `final class DataStore { init(directory: URL, now: @escaping () -> Date = Date.init); func load() -> AppData; func save(_ data: AppData) throws; static func defaultDirectory() -> URL }`. `defaultDirectory()` returns Application Support `todo-target`, or the path in env `TODO_TARGET_DATA_DIR` when set.

**Rules.** `load()` never throws. A missing file returns `AppData.pristine()`. An unreadable or invalid file is moved to `data.json.corrupt-<unix time>` and `pristine()` is returned. A file with `schemaVersion` above 1 is also moved aside, never overwritten. `save` writes atomically (temp file, then rename) and creates the directory.

- [ ] **Step 1: Write failing tests** using a temp directory:
```swift
@Test func missingFileGivesPristine()
@Test func saveThenLoadRoundTrips()
@Test func corruptFileIsQuarantinedNotDeleted()   // write "{not json"; load -> pristine; a file named data.json.corrupt-* exists with the bad bytes
@Test func newerSchemaIsQuarantined()             // schemaVersion 99 -> pristine, original bytes kept in corrupt file
@Test func saveCreatesDirectory()
```
- [ ] **Step 2: Run** `swift test --filter DataStoreTests`. Expected: FAIL.
- [ ] **Step 3: Implement** `DataStore` per the rules.
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Commit** `feat: add JSON data store with corruption recovery`.

### Task 8: HeatmapModel (D15, C30 to C33)

**Files:**
- Create: `Sources/TodoTargetCore/HeatmapModel.swift`
- Test: `Tests/TodoTargetCoreTests/HeatmapModelTests.swift`

**Interfaces:**
- Consumes: `StreakEngine`, models.
- Produces:
  - `enum HeatmapPeriod: Equatable { case current; case year(Int) }`
  - `struct HeatmapCell: Equatable { enum Kind: Equatable { case beforeStart, future, day(level: Int) }; var day: DayKey; var kind: Kind; var isToday: Bool; var savedByCatchUp: Bool; var tooltip: String }`
  - `struct HeatmapModel: Equatable { var columns: [[HeatmapCell?]] /* weeks, 7 rows each, nil = padding */; var monthLabels: [(column: Int, name: String)]; var activeDays: Int; var maxStreak: Int; var availableYears: [Int] }` (declare `Equatable` by hand, or compare fields in tests)
  - `static func build(data: AppData, today: DayKey, period: HeatmapPeriod, calendar: Calendar, locale: Locale) -> HeatmapModel`

**Rules.** `.current` spans the week containing `today - 364 days` through the week containing `today`. `.year(y)` spans the weeks covering 1 Jan to 31 Dec of `y`. The first weekday is `calendar.firstWeekday`. A day's level is the number of completions linked to that day (0 to 3). A day before `firstUseDay` is `.beforeStart`. A day after `today` is `.future`. `savedByCatchUp` is true for a day that is in `activeDays` and has recovered completions. Tooltip format is `"Tue 10 Nov 2026: 3 of 3"` and for a saved day `"... 3 of 3 (saved by catch-up)"`. `activeDays` counts counted days inside the period. `maxStreak` is `StreakState.best`. `availableYears` lists years that have data, newest first.

- [ ] **Step 1: Write failing tests** (Gregorian UTC calendar with `firstWeekday = 1`, locale `en_US_POSIX`):
```swift
@Test func currentPeriodHasSevenRowsAndAboutFiftyThreeColumns() { #expect(m.columns.allSatisfy { $0.count == 7 }); #expect((52...54).contains(m.columns.count)) }
@Test func todayIsInLastColumnAndOutlined()   // last column contains a cell with isToday == true and day == today
@Test func daysBeforeFirstUseAreGreyAndFutureEmpty()
@Test func levelEqualsCompletionCount()       // own {0,1} -> .day(level: 2)
@Test func tooltipFormat()                    // "Tue 10 Nov 2026: 3 of 3" for 2026-11-10 with own {0,1,2}
@Test func savedDayIsMarkedAndTooltipSaysSo()
@Test func monthLabelsStartAtMonthBoundaries()
@Test func yearPeriodCoversJanToDec()         // .year(2025): first real cell is 2025-01-01, last is 2025-12-31
@Test func firstWeekdayMondayShiftsRows()     // calendar.firstWeekday = 2: row 0 is Monday
@Test func statsMatchEngine()                 // activeDays and maxStreak equal engine values for the period
```
- [ ] **Step 2: Run** `swift test --filter HeatmapModelTests`. Expected: FAIL.
- [ ] **Step 3: Implement** `HeatmapModel.build`. Use `DateFormatter` with the passed locale and `calendar` for tooltips.
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Commit** `feat: add heatmap model`.

### Task 9: Clock, rollover, and AppModel (C1, C12)

**Files:**
- Create: `Sources/TodoTargetCore/DayRollover.swift`, `Sources/TodoTargetCore/Clock.swift`, `Sources/TodoTarget/AppModel.swift`
- Test: `Tests/TodoTargetCoreTests/DayRolloverTests.swift`

**Interfaces:**
- Produces:
  - `enum DayRollover { static func nextMidnight(after: Date, calendar: Calendar) -> Date }`
  - `protocol Clock { var now: Date { get } }`, `struct SystemClock: Clock`, `final class MutableClock: Clock { var now: Date }`. `SystemClock` honors env `TODO_TARGET_TODAY=YYYY-MM-DD` (noon local time, for manual testing only).
  - `final class DayTracker { init(clock: Clock, calendar: Calendar); private(set) var today: DayKey; @discardableResult func refresh() -> Bool /* true when the day changed */ }`
  - `@MainActor final class AppModel: ObservableObject { @Published private(set) var data: AppData; @Published private(set) var today: DayKey (backed by DayTracker); var streak: StreakState; var heatmapPeriod: HeatmapPeriod; init(store: DataStore, clock: Clock, calendar: Calendar); func refreshToday(); func markDone(goalID: UUID, forDay: DayKey); func undo(goalID: UUID, forDay: DayKey); func importList(goalID: UUID, csv: String, keepPosition: Bool) throws; func updateGoals(names: [String], order: [UUID]); func replaceData(_ new: AppData); var onChange: (() -> Void)? }`
  Every mutating call saves through `DataStore` and then calls `onChange` (used by backup, Task 13).

- [ ] **Step 1: Write failing tests** in `DayRolloverTests.swift`:
```swift
@Test func nextMidnightIsStartOfNextDay()          // 2026-11-17 23:59 UTC -> 2026-11-18 00:00 UTC
@Test func nextMidnightAcrossDSTIsNextLocalMidnight() // New_York, 2026-03-08 12:00 -> 2026-03-09 00:00 local
@Test func nextMidnightAtExactMidnightIsNextDay()
@Test func trackerFollowsClockPastMidnight() {   // MutableClock at 2026-11-17 23:50; tracker.today == 2026-11-17
  clock.now = clock.now.addingTimeInterval(20 * 60); #expect(tracker.refresh() == true); #expect(tracker.today.string == "2026-11-18") }
@Test func trackerRefreshWithoutDayChangeReturnsFalse()
@Test func streakChangesWhenDayRollsOver()       // full 11-06...11-16, today 11-17 open: current 11; advance clock to 11-18 with no marks: current == 0 and catchUp != nil (11-17 missed)
@Test func trackerSurvivesMultiDaySleep()        // advance clock 3 days: today == +3 days
```
- [ ] **Step 2: Run** `swift test --filter DayRolloverTests`. Expected: FAIL.
- [ ] **Step 3: Implement** `DayRollover.nextMidnight` with `calendar.nextDate(after:matching:matchingPolicy:)`. Then implement `Clock`, `DayTracker`, and `AppModel`. `AppModel.refreshToday()` calls `DayTracker.refresh()` and republishes `today` and `streak`. The app calls it on three events: a timer at `nextMidnight`, `NSWorkspace.didWakeNotification`, and `.NSCalendarDayChanged`. Wire those three in `AppDelegate` (Task 10).
- [ ] **Step 4: Run** `swift test` and `swift build`. Expected: all tests pass and the build succeeds.
- [ ] **Step 5: Commit** `feat: add day rollover, clock, and app model`.

### Task 10: Status item, icon, and left-click (D4, D6, C15, C16)

**Files:**
- Create: `Sources/TodoTarget/IconRenderer.swift`, `Sources/TodoTarget/StatusItemController.swift`, `Sources/TodoTarget/AppDelegate.swift`; modify `Sources/TodoTarget/main.swift`.

**Interfaces:**
- Consumes: `AppModel`, `Planner`.
- Produces: `enum IconRenderer { static func image(level: Int, doneCount: Int, catchUp: Bool) -> NSImage }` (non-template image, 18 pt tall: a filled circle with the done count as a number inside, plus a small `↺` badge when `catchUp`; colours for levels 0 to 3: red, orange, yellow-green, green, each readable in light and dark menu bars). `final class StatusItemController { init(model: AppModel, showPanel: @escaping (NSStatusBarButton) -> Void); func refreshIcon() }`.

**Behavior.** The button `sendAction(on: [.leftMouseUp, .rightMouseUp])`. A left click calls `Planner.nextTask`. If the task has an `item.url` with scheme `http` or `https`, open it with `NSWorkspace.shared.open`. If the task has no URL, or no task is left, call `showPanel`. A right click always calls `showPanel`. `main.swift` sets `NSApp.setActivationPolicy(.accessory)` and runs `AppDelegate`. `AppDelegate` wires the three refresh events from Task 9.

- [ ] **Step 1: Build.** Run `swift build`. Expected: builds.
- [ ] **Step 2: Run the app with a data folder and a simulated date:** `TODO_TARGET_DATA_DIR=$(mktemp -d) swift run TodoTarget`. Expected: a circle icon appears in the menu bar. It is red with `0`. Quit with `kill`.
- [ ] **Step 3: Verify the four colours.** Write a data file by hand with 1, 2, and 3 completions today. Relaunch for each. Expected: orange `1`, yellow-green `2`, green `3`. Capture each with `screencapture -x -R<menu bar region> <scratchpad>/icon-N.png` and read the images.
- [ ] **Step 4: Verify the left click.** A goal with an `https` link opens it in the browser. Quit the app.
- [ ] **Step 5: Commit** `feat: add status item, icon, and left-click`.

### Task 11: Panel (right click): streak, heatmap, goals (D6b, D15, C8, C30 to C32)

**Files:**
- Create: `Sources/TodoTarget/PanelView.swift`, `Sources/TodoTarget/HeatmapView.swift`; modify `AppDelegate.swift` to host an `NSPopover` (behavior `.transient`, content `NSHostingController`).

**Interfaces:**
- Consumes: `AppModel`, `HeatmapModel`, `Planner`.

**Behavior.** The panel (about 600 pt wide) has a header (current streak, "at risk" text when `atRisk != nil` with the line "Finish yesterday's work today to keep it.", active days, max streak, period selector "Current" plus years from `availableYears`), the heatmap (4 colours, grey and empty cells, outlined today, hover tooltip from `HeatmapCell.tooltip`, month labels), and the goals list. Catch-up goals appear under "Yesterday", today's goals under "Today". Each open row takes its item from the matching `OwedTask.item` (never from `goal.position` directly). It shows slot, goal name, item title (`group` and `title`; "List complete" when the goal has items and `item == nil`). A done row shows the title of `items[completion.itemIndex]` when that index exists. Each open row has a tick button (`markDone`), and an undo control for marks made today. A footer menu has: "Mark [goal name] done" (the first owed goal), Settings, Import list, Backup now, Quit.

- [ ] **Step 1: Implement the views.** Cell size is a constant tuned so 53 columns fit the width.
- [ ] **Step 2: Build** with `swift build`. Expected: builds.
- [ ] **Step 3: Verify with seeded data.** Write a data file with a 10-day streak, a missed yesterday (`own {0}`), and a long history. Run with `TODO_TARGET_TODAY` set. Expected: the header shows the at-risk streak (10) and the catch-up line. "Yesterday" lists 2 goals. "Today" lists 3 goals. The menu bar icon shows the `↺` badge. Capture with `screencapture` after a right click, and read the image.
- [ ] **Step 4: Verify the tick flow.** Tick the 2 owed goals, then the 3 of today. Expected: icon turns green, the catch-up line goes away, the streak shows 12.
- [ ] **Step 5: Commit** `feat: add panel with heatmap and goals`.

### Task 12: Settings, CSV import, launch at login (C12, C14, C17, C33)

**Files:**
- Create: `Sources/TodoTarget/SettingsView.swift`, `Sources/TodoTarget/LaunchAtLogin.swift`; modify `AppDelegate.swift` (Settings window).

**Interfaces:**
- Produces: `enum LaunchAtLogin { static func set(_ enabled: Bool) throws; static var isEnabled: Bool }` using `SMAppService.mainApp`.

**Behavior.** Settings has: 3 goal name fields, up and down buttons to reorder, per-goal "Import list…" (`NSOpenPanel`, `.commaSeparatedText`, then `AppModel.importList`; errors from `CSVImportError` show in an alert in plain words with the line number; a "Keep position" checkbox), a "Start at login" toggle (default on, errors shown, not fatal when the app is not in a bundle), and a Backup section (Task 13). On first run (`AppData.isPristine`), open Settings at launch.

- [ ] **Step 1: Implement.** Reordering calls `AppModel.updateGoals`.
- [ ] **Step 2: Build and run.** Import `examples/sample-list.csv` for goal 1. Expected: the panel shows the first item title. A left click opens its link.
- [ ] **Step 3: Verify bad input.** Import a CSV with a `javascript:` link. Expected: an alert names the line, and data does not change.
- [ ] **Step 4: Commit** `feat: add settings, list import, and launch at login`.

### Task 13: Backup client, sign-in, restore (D8, D9, C9, C10, C19, C20)

**Files:**
- Create: `Sources/TodoTargetCore/Backup/BackupPayload.swift`, `TokenStore.swift`, `BackupClient.swift`, `Sources/TodoTarget/URLSchemeHandler.swift`, `Sources/TodoTarget/BackupCoordinator.swift`, `supabase/schema.sql`
- Test: `Tests/TodoTargetCoreTests/BackupClientTests.swift`

**Interfaces:**
- Produces:
  - `struct BackupPayload: Codable, Equatable { var goals: [Goal]; var days: [String: DayRecord]; var firstUseDay: String?; var savedAt: Date }` (no settings, no keys)
  - `enum RestoreDecision: Equatable { case replaceSilently, needsConfirmation }` and `enum BackupRestore { static func decision(local: AppData) -> RestoreDecision }` (`replaceSilently` only when `local.isPristine`)
  - `protocol TokenStore { func read() -> AuthSession?; func write(_ s: AuthSession) throws; func clear() }`, `struct AuthSession: Codable { var accessToken: String; var refreshToken: String; var expiresAt: Date }`, `KeychainTokenStore: TokenStore`
  - `final class BackupClient { init(baseURL: URL, anonKey: String, session: URLSession, tokens: TokenStore); func sendMagicLink(email: String, redirectTo: URL) async throws; func completeSignIn(callback: URL) throws; func push(_ p: BackupPayload) async throws; func pull() async throws -> BackupPayload?; var isSignedIn: Bool }`
  - `BackupCoordinator`: debounces `AppModel.onChange` by 5 seconds, then `push` when signed in. A failed push sets a quiet status string shown in the panel ("Last backup: ..." or "Backup failed: ..."). No alert, no notification (anti-goal).

**Required first step.** Read the current Supabase docs for passwordless email sign-in (OTP / magic link), session refresh, and PostgREST upsert. Record the doc URLs in code comments. Confirm these expected shapes before the tests fix them: `POST {base}/auth/v1/otp`, `POST {base}/auth/v1/token?grant_type=refresh_token`, `POST {base}/rest/v1/backups?on_conflict=user_id` with `Prefer: resolution=merge-duplicates`, `GET {base}/rest/v1/backups?select=payload`, headers `apikey` and `Authorization: Bearer <access>`. Also confirm how the redirect returns tokens to a custom URL scheme (fragment or code). Adjust `completeSignIn` to match the docs.

`supabase/schema.sql` creates table `backups(user_id uuid primary key default auth.uid(), payload jsonb not null, updated_at timestamptz not null default now())`, enables row-level security, and adds select, insert, and update policies with `user_id = auth.uid()`.

**Token rule.** An ad-hoc signature changes with each build, so the Keychain may refuse to read an item made by an older build. `KeychainTokenStore.read()` returns `nil` on any read error. The app then shows "Signed out" and the sign-in button. It never prompts in a loop and never crashes. Add a test: a `TokenStore` whose `read()` returns `nil` makes `isSignedIn` false and `push` throw `.notSignedIn`.

**Restore rule (C20, Review Focus 5).** "Restore from backup" calls `pull()`. If `AppModel.data.isPristine`, it replaces data. Otherwise it shows a confirmation alert first. Local data stays unchanged until the user confirms.

- [ ] **Step 1: Write failing tests** with a stub `URLProtocol` and an in-memory `TokenStore`:
```swift
@Test func pushSendsUpsertWithAuthHeaders()    // method POST, path /rest/v1/backups, query on_conflict=user_id, apikey + Bearer headers, body contains payload JSON
@Test func pushWithoutSessionThrowsNotSignedIn()
@Test func expiredTokenIsRefreshedBeforePush() // stub 1: refresh request; stub 2: upsert uses the new access token; tokens stored
@Test func pullReturnsNilWhenNoRow()           // stub returns []
@Test func pullDecodesPayload()
@Test func magicLinkRequestBody()              // body has email and the redirect URL
@Test func completeSignInStoresSession()       // callback URL shape per the docs
@Test func payloadNeverContainsSettingsOrKeys() // encode payload; JSON text does not contain "supabaseAnonKey"
@Test func restoreSilentOnlyWhenLocalIsPristine()       // pristine -> .replaceSilently
@Test func restoreNeedsConfirmationWhenLocalHasData()   // data with a done mark, or a renamed goal -> .needsConfirmation
```
- [ ] **Step 2: Run** `swift test --filter BackupClientTests`. Expected: FAIL.
- [ ] **Step 3: Implement** the client with `async`/`await` and the injected `URLSession`.
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Implement the app side.** The Settings Backup section has: URL and anon key fields, email field, "Send sign-in link", status text, "Backup now", "Restore from backup". `URLSchemeHandler` listens for the `todotarget://` Apple event and calls `completeSignIn`. Tokens go to the Keychain, never to `data.json`.
- [ ] **Step 6: Live check (needs the author's own Supabase project).** Ask the author to create a free project, run `supabase/schema.sql`, and paste the URL and anon key. Expected: sign-in link arrives, the click returns to the app, "Backup now" creates a row, a second Mac or an empty data folder restores it. Also test the open question from spec section 9: wait and observe whether daily pushes keep the project from pausing. Report the result. Do not claim it works until this step runs.
- [ ] **Step 7: Commit** `feat: add Supabase backup, sign-in, and restore`.

### Task 14: Packaging and release (D11, C18)

**Files:**
- Create: `resources/Info.plist`, `scripts/build-app.sh`, `.github/workflows/release.yml`

**Interfaces:**
- Produces: `scripts/build-app.sh` writes `build/TodoTarget.app` and `build/TodoTarget.zip`.

**Rules.** `Info.plist` sets `CFBundleIdentifier` to `dev.todotarget.app` (the assistant's call), `CFBundleName` to `TodoTarget`, `LSUIElement` to `true`, `LSMinimumSystemVersion` to `14.0`, and a `CFBundleURLTypes` entry for scheme `todotarget`. The script runs `swift build -c release --arch arm64 --arch x86_64`. If the universal build fails, it falls back to `--arch arm64` and prints a clear message. It copies the binary into `Contents/MacOS`, copies `Info.plist`, signs with `codesign --force --deep -s -`, and zips with `ditto -c -k --keepParent`. The workflow runs on tag `v*` on a macOS runner, runs `swift test`, runs the script, and attaches the zip to a GitHub Release. Do not push or tag.

- [ ] **Step 1: Write the script and plist.**
- [ ] **Step 2: Run** `./scripts/build-app.sh`. Expected: `build/TodoTarget.zip` exists. `codesign -dv build/TodoTarget.app` shows an ad-hoc signature. `lipo -archs build/TodoTarget.app/Contents/MacOS/TodoTarget` prints the architectures.
- [ ] **Step 3: Run the bundle.** `open build/TodoTarget.app`. Expected: the icon appears, there is no Dock icon, and "Start at login" works from the bundle (check System Settings, Login Items). Quit the app.
- [ ] **Step 4: Commit** `build: add app bundle script and release workflow`.

### Task 15: README and docs

**Files:**
- Create: `README.md`

**Content.** What the app is (3 goals, colours, left and right click, catch-up rule in plain words). Install: download the zip from Releases, drag to Applications, the Gatekeeper steps. On macOS 15 and later: open the app once so macOS blocks it, then go to System Settings, Privacy and Security, scroll to Security, and click Open Anyway. (macOS 15 removed the right-click Open shortcut. Sources: Apple's macOS 15 Mac User Guide and eclecticlight.co.) On macOS 14: right click the app, then Open. The "Open Anyway" button can disappear after about an hour, so tell the user to repeat the blocked launch if it is missing. Re-check these steps on macOS 26 when the first release exists. Build from source: `./scripts/build-app.sh`. CSV format with the sample. Backup setup: create a Supabase project, run `supabase/schema.sql`, paste the URL and anon key, add the redirect URL `todotarget://auth-callback` to the project's allow-list, sign in by email link. Privacy note: no keys in the repo; data is local plus the user's own Supabase. State Supabase free-plan limits only after they are verified against the official page (spec section 9). Use `<owner>` placeholders, not a real username.

- [ ] **Step 1: Write the README** in plain, short sentences.
- [ ] **Step 2: Verify the steps.** Follow the README on a clean data folder (`TODO_TARGET_DATA_DIR`). Expected: every command works as written.
- [ ] **Step 3: Commit** `docs: add README`.

### Task 16: End-to-end verification with simulated dates

**Files:** none (verification only). Record results in `docs/superpowers/plans/2026-11-17-todo-target-verification.md`.

- [ ] **Step 1: Run** `swift test`. Expected: all tests pass. Paste the summary line.
- [ ] **Step 2: Walk the spec scenarios** with `TODO_TARGET_TODAY` and seeded data, and capture screenshots: normal day with 1, 2, and 3 goals; catch-up with 2 goals owed (5 tasks, colours at 1, 3, 5 done); two missed days (streak 0, no catch-up); a heatmap with a full year.
- [ ] **Step 3: Check the anti-goals.** Idle CPU of the running app is near 0 percent (`top -pid`). No network calls happen with no Supabase config (`nettop` or the absence of a configured client). `git grep -nE "eyJ|supabase\.co"` finds no keys.
- [ ] **Step 4: Report** which spec items are verified and which are not (the Supabase pause question stays open until Task 13 Step 6 runs).
- [ ] **Step 5: Commit** `docs: record verification results`.
