# todo-target

A small macOS menu bar app. It holds exactly 3 daily goals.
The icon in the menu bar shows how many goals you finished today.
The icon is red until you start. It turns green when all 3 goals are done.

The idea comes from a LeetCode streak: a signal that is red until you do the work, then green.

- [What it does](#what-it-does)
- [Install](#install)
- [Build from source](#build-from-source)
- [Goal lists (CSV import)](#goal-lists-csv-import)
- [Optional cloud backup](#optional-cloud-backup)
- [Privacy](#privacy)
- [Develop and test](#develop-and-test)
- [License](#license)

## What it does

**Three goals.** You name them. The order is the priority order. You change it in Settings.

**Icon colour.** The circle in the menu bar shows the number of goals done today.

| Done today | Colour |
|---|---|
| 0 | red |
| 1 | orange |
| 2 | yellow-green |
| 3 | green |

The number inside the circle repeats the count, so the colour is not the only signal.

**Left click.** A left click opens the link of the first goal that is not done.
The next left click opens the next goal. If a goal has no link, or all goals are done, the panel opens.

**Right click.** A right click opens the panel. The panel shows:

- the current streak, the active days, and the best streak
- a yearly heatmap, like the one on a LeetCode profile
- the 3 goals, each with a tick button
- a menu with Settings, Import list, Backup now, and Quit

**Streak.** A day counts when all 3 goals are done. The day ends at midnight, Mac local time.
You can undo a tick on the same day. Past days are read-only.

**Catch-up.** You can save a streak after one missed day.

1. You miss a goal on day D. The streak does not break yet.
2. On day D+1 the icon shows a `↺` badge. You owe the goals you missed on day D, plus the 3 goals of day D+1.
3. You finish all of that work before day D+1 ends. Day D now counts, and the streak continues.
4. If you do not finish it, the streak breaks at the end of day D+1.

Catch-up covers only the day right before today. If you miss 2 days in a row, the streak breaks.
Only the goals you missed are owed. If you did 2 of 3 goals, you owe 1 goal from that day.

**Goal lists.** A goal can have an imported list of items, for example a list of problems.
The app shows the next item. Each tick moves the goal to the next item.
A goal without a list works as a plain checkbox.

## Install

1. Download `TodoTarget.zip` from the
   [Releases page](https://github.com/JairajSustained/todo-target/releases).
2. Open the zip. Drag `TodoTarget.app` to your `Applications` folder.
3. Open the app the first time. See the next section.

The app needs macOS 14 or later.

### Open an unsigned app (Gatekeeper)

The app is ad-hoc signed. It is not notarized, because that needs a paid Apple Developer account.
macOS shows a warning the first time.

**macOS 15 and later:**

1. Open the app once. macOS blocks it.
2. Open **System Settings**, then **Privacy & Security**.
3. Scroll down to **Security**.
4. Click **Open Anyway**. Confirm if macOS asks.

macOS 15 removed the right-click **Open** shortcut. The **Open Anyway** button can disappear after about an hour.
If you do not see it, open the app again so macOS blocks it again.

**macOS 14:** right click the app, then click **Open**.

These steps come from Apple's macOS 15 Mac User Guide and eclecticlight.co.
They are not yet re-checked on macOS 26.

### The first start

On the first start, Settings opens. Name your 3 goals. Import a list for a goal if you want one.
**Start at login** is on by default. You can turn it off in Settings.

## Build from source

You need the Swift command line tools (`xcode-select --install`). You do not need the Xcode IDE.

```sh
git clone https://github.com/JairajSustained/todo-target.git
cd todo-target
./scripts/build-app.sh
```

The script writes `build/TodoTarget.app` and `build/TodoTarget.zip`.
It tries a universal build (Apple silicon and Intel).
If that fails, it builds for Apple silicon only and prints a note.
The universal build needs the full Xcode build system, so with only the command line tools you get an Apple silicon app.

## Goal lists (CSV import)

In Settings, click **Import list…** next to a goal. Choose a CSV file.

The first line names the columns. The columns are `group`, `title`, and an optional `url`.
One row is one item. The row order is the order of work.

```csv
group,title,url
Arrays,Two Sum,https://example.com/problems/two-sum
Arrays,Contains Duplicate,https://example.com/problems/contains-duplicate
Trees,Invert Binary Tree,https://example.com/problems/invert-binary-tree
```

- Column names are not case-sensitive. Extra columns are ignored.
- A link must start with `http://` or `https://`. Other links are rejected, and the whole import stops with the line number.
- Use quotes for a value with a comma, for example `"Trees, binary"`.
- A full example is in [`examples/sample-list.csv`](examples/sample-list.csv).

If you import a list again, the position resets to the first item.
Turn on **Keep list position** in Settings to keep the position.

## Optional cloud backup

The app works with no account and no network. Backup is optional.
Each user brings their own free [Supabase](https://supabase.com) project.
The author does not host any backend, and the repository holds no keys.

Backup holds the goal names and order, the imported lists, the list positions, and one record per day.
It holds no settings and no keys. The local copy is always the main copy.

1. Create a Supabase project. For the free-plan limits, check the Supabase pricing page.
2. In the project, open the SQL editor and run [`supabase/schema.sql`](supabase/schema.sql).
3. Copy the project URL and the anon (public) key from the project API settings.
   Supabase can name the key differently in newer dashboards.
4. In the project, open the Auth URL settings. Add this redirect URL to the allow-list:
   `todotarget://auth-callback`
5. In the app, open Settings. Paste the URL and the key into the Backup section.
6. Enter your email. Click **Send sign-in link**. Open the link from the email on this Mac.
   The link returns to the app.
7. Click **Backup now**. After that, the app backs up 5 seconds after each change.

The panel shows a quiet status line, for example "Last backup: …" or "Backup failed: …".
The app never shows an alert or a notification for backup.

**Restore on a new Mac.** Sign in the same way. Click **Restore from backup**.
If the Mac already has goals or history, the app asks before it replaces them.

Google sign-in is not built into the app.

> Status: the backup code is unit tested against a stub server. A live test against a real Supabase project is not done yet.

## Privacy

- Your data is in `~/Library/Application Support/todo-target/data.json`.
- The repository holds no keys, no secrets, and no personal data.
- With no Supabase settings, the app makes no network calls.
- With backup on, the data goes only to your own Supabase project.
- Sign-in tokens are stored in the macOS Keychain, not in `data.json`.

## Develop and test

```sh
./scripts/test.sh          # run all tests
swift build                # debug build
```

With only the command line tools, plain `swift test` cannot find the Swift Testing framework.
`./scripts/test.sh` passes the framework paths. It takes the same arguments, for example `--filter StreakEngineTests`.

Two environment variables help manual testing:

- `TODO_TARGET_DATA_DIR=<folder>` uses another data folder.
- `TODO_TARGET_TODAY=YYYY-MM-DD` pretends that it is that day (noon, local time).

```sh
TODO_TARGET_DATA_DIR=$(mktemp -d) swift run TodoTarget
```

The rules (streak, catch-up, lists, heatmap) are in the `TodoTargetCore` library and have unit tests.
The app in `Sources/TodoTarget` is a thin AppKit and SwiftUI layer.
The design is in [`docs/superpowers/specs/`](docs/superpowers/specs/).

## License

MIT. See [LICENSE](LICENSE).
