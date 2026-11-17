# todo-target: Design

Date: 2026-11-17
Status: Draft for author approval

## 1. Intent and why

The author is preparing for software placements. They need to do 3 fixed things every day. They want a tool that makes them do those 3 things every day.

The author had an 80-day streak on LeetCode. One thing made it work: a daily signal that was red until the problem was solved, then green. The author wants the same signal for 3 daily targets.

todo-target is a small macOS menu bar app. It holds exactly 3 daily goals. The menu bar icon colour shows how many goals are done today. A left click on the icon opens the first goal that is not done, so starting work takes one click. A right click shows the streak and the 3 goals. A user can save a streak after a missed day. On the next day, the user finishes yesterday's missed work and today's work.

The author uses it first. The code is open source in a public GitHub repository, so other people can use it with their own 3 goals.

### The author's own 3 goals (the first use case)

1. DSA: one problem a day from the AlgoTail roadmap. The roadmap is a list of topics. Each topic has about 6 problems.
2. System design: one part of a video playlist from the channel "Jordan Has No Life".
3. AI engineering: one part of a course on how LLMs work.

The app must not hard-code these goals. They are example data.

## 2. Goals

- G1. A native macOS menu bar app. It runs all day and costs almost no CPU or memory.
- G2. Exactly 3 goals. The user names them.
- G3. The icon shows progress with 4 colours, from red to green.
- G4. A streak counts days with all 3 goals done.
- G5. A goal can have an imported list of items. The app shows the next item. A done tap moves to the next item.
- G6. A free cloud backup of the data, in a database that each user owns.
- G7. A new user can install and run the app from the public repository with clear steps.
- G8. Starting work takes one click. A left click on the icon opens the current item of the first goal that is not done. The next left click, after that goal is done, opens the second goal. The third goal works the same way.
- G9. A streak can survive one missed day through catch-up (see D14 and C23 to C28).
- G10. The right-click panel shows a yearly heatmap, like the one on a LeetCode profile, so the user sees the streak pattern at a glance (see D15 and C30).

## 3. Non-goals

- More or fewer than 3 goals. The limit is the design.
- Reminders and notifications.
- Windows, Linux, iOS, or web clients.
- A web dashboard or a phone view.
- Teams, sharing, or social features.
- Automatic detection of work (for example, reading LeetCode or YouTube history).
- A shared backend hosted by the author.
- Catch-up for more than one missed day.

## 4. Anti-goals

These outcomes are a failure, even if the app technically works.

- The app nags or interrupts the user. The icon is the only signal.
- The app needs an account or a network to work. Local use must work with no sign-in.
- Secrets, keys, or personal data appear in the public repository.
- The app uses noticeable CPU, memory, or battery.
- The user can fake a streak easily by accident. A done mark needs a deliberate tap.
- Opening the next target needs more than one click.
- Catch-up becomes a loophole. It covers only the day right before today, and it needs all owed work.

## 5. Constraints

- Platform: macOS only. The author's Mac runs macOS 26 on Apple silicon.
- Tooling: Swift 6.3 is installed. Full Xcode is not installed. Only the command line tools are there. The build must work with Swift Package Manager and a script that makes the `.app` bundle. The build must not need the Xcode IDE.
- Distribution: a downloaded unsigned app shows a Gatekeeper warning on other Macs. The README must explain how to open the app (see C18). A paid Apple Developer account is out of scope.
- The repository is public. No secret goes in it. Each user supplies their own cloud values at run time.
- Cloud cost: free tier only.

## 6. Approaches considered

| Option | Good | Bad |
|---|---|---|
| A. Native Swift (SwiftUI menu bar) | Small and fast. Native look. Easy coloured icon. | Gatekeeper warning for unsigned builds. |
| B. Tauri or Electron | Web skills. Cross-platform. | Heavy. Not native. |
| C. SwiftBar plugin script | Fastest to write. | Needs SwiftBar. Weak CSV import and state. Not a standalone app. |

**Chosen: A.** The author picked it. It fits the "menu bar next to the battery icon" request best.

Backend options for cloud backup:

| Option | Good | Bad |
|---|---|---|
| Supabase, each user's own project | Plain web requests. No large SDK. Free tier. Google sign-in supported. | Each user does a short setup. The free plan pauses a project after 1 week of inactivity. |
| Firebase Spark | Free tier. Google sign-in supported. | Large SDK. It adds weight to a small app. |
| One shared backend hosted by the author | No setup for users. Google sign-in works at once. | The author carries hosting limits and the privacy duty for other people's data. |

**Chosen: Supabase, each user's own project.** The author picked "each user's own". The Supabase choice is the assistant's call.

## 7. Decisions made by the author

- D1. Native Swift menu bar app.
- D2. Exactly 3 goals.
- D3. Each goal can have an imported list. The app shows the next item. A done tap moves to the next item. A goal can also have no list. It then works as a plain checkbox.
- D4. Icon colour follows the number of goals done today: 0 red, 1 orange, 2 yellow-green, 3 green.
- D5. The streak counts a day only when all 3 goals are done.
- D6. A left click on the icon opens the first goal that is not done, in the author's priority order. It opens that goal's current item in the default browser. When that goal is done, the next left click opens the next goal.
- D6b. A right click on the icon shows the streak and the 3 goals. The author confirmed this reading.
- D7. No reminders.
- D8. Cloud data is a backup only. The local copy is the main copy.
- D9. Each user brings their own Supabase project. The public repository holds no keys.
- D10. The app is open source in a public repository under the author's GitHub account.
- D11. The app must be easy to install and use. A user downloads a prebuilt app from GitHub Releases. Build from source stays as a second path.
- D12. The license is MIT.
- D13. The author's own 3 lists are not part of the app build. The repository holds a sample CSV. The author and the assistant make the real CSV files as a separate step after the build.
- D14. A user can save the streak after a missed day. On the next day, the user finishes the work missed yesterday and also today's work. Then the streak continues. The author calls this "twice the amount of work".
- D15. The right-click panel shows a heatmap like the one on the author's LeetCode profile. The author shared a screenshot. It is a grid of small squares for the past year, with month names below and totals above (total active days, max streak). Each day is coloured by its result.

## 8. Calls made by the assistant (the author can change these)

- C1. The day ends at midnight in the Mac's local time zone.
- C2. A broken streak resets the current streak to 0. The app also keeps the best streak. A day with fewer than 3 goals done breaks the streak at the end of the next day, unless catch-up saves it (see C23).
- C3. The current day never breaks the streak while the day is open. The streak breaks only after the catch-up window of a missed day closes.
- C4. The user can undo a done mark on the same day. A past day is read-only. The one exception is yesterday: the user can finish its missed goals today, in catch-up mode.
- C5. One done mark per goal per day. A second done tap on the same day has no effect.
- C6. CSV import format: one row per item. Columns: `group`, `title`, `url`. `url` is optional. `group` is the topic name (for example "Trees"). Row order is the order of work.
- C7. When a list ends, the goal shows "List complete". It then works as a plain checkbox.
- C8. A right click opens a panel with the streak and the 3 goals. A tick in the panel marks a goal done. The panel has a menu with a top line "Mark [goal name] done" for the first goal not done, then Settings, Import list, Backup now, and Quit.
- C14. The order of the 3 goals is the priority order. The user changes it in Settings.
- C15. If a goal has no link, a left click shows that goal's current item title in the panel.
- C16. If all 3 goals are done, a left click opens the panel with the streak.
- C17. Goals use slots 1 to 3 with stable IDs. Renaming a goal keeps its history. A re-import of a list keeps history and resets the list position to the first item. The user can choose to keep the position instead.
- C18. How D11 is met: a script makes the `.app` bundle and a zip file. A GitHub Releases page holds the zip. The build is ad-hoc signed, not notarized, because a paid Apple Developer account is out of scope. The README gives the exact steps to open an unsigned app. On macOS 15 and later, the steps are: open the app once, then System Settings, Privacy and Security, Open Anyway. The right-click Open shortcut works only on macOS 14. (Correction made during planning: the first draft named the right-click shortcut first.) The builder tries a universal build (Apple silicon and Intel). If that fails, the build is Apple silicon only, and the README says so. The minimum macOS version is 14. Build from source is documented as a second path.
- C19. The sign-in link returns to the app through a custom URL scheme. The user adds the redirect URL to the allow-list in their own Supabase project. The README lists this step.
- C20. Backup holds the goal names and order, the imported list items, the list position of each goal, and one record per day. A day record also shows whether its work was done in catch-up. Restore works only on an empty local store. If local data exists, the app asks the user before it replaces anything.
- C23. Catch-up rule. Day D ends with fewer than 3 goals done. The streak does not break yet. During day D+1 the app is in catch-up mode. The owed work is the goals not done on day D, plus the 3 goals of day D+1. If the user finishes all owed work before day D+1 ends, day D counts as done and the streak continues. If not, the streak breaks at the end of day D+1.
- C24. Catch-up covers only the day right before today. If the user misses two days in a row, the streak breaks.
- C25. After a successful catch-up, the streak counts day D and day D+1 as done. Example: the streak is 10, the user misses day D, then finishes all owed work on day D+1. The streak is 12 at the end of day D+1.
- C26. Only the goals missed on day D are owed. A user who did 2 of 3 goals on day D owes 1 goal from day D, not 3.
- C27. List goals: each done tap advances the list by one item. The catch-up item comes first, then today's item. A left click opens the owed goals in this order: first the goals owed from yesterday, in priority order, then today's goals, in priority order.
- C28. In catch-up mode the icon shows a catch-up badge. The colour scale runs over all owed tasks. The icon is green only when all owed tasks are done. The panel marks catch-up tasks as "yesterday".
- C29. Catch-up has no limit in v1, for example no cap per week. The author can add one later.
- C30. The heatmap has one column per week and 7 rows, one row per weekday. The oldest week is on the left. Today is in the last column. Month names are below the columns where a month starts. Each square uses the same 4 colours as the icon, by the number of goals done that day (0 red, 1 orange, 2 yellow-green, 3 green). Days before the user started the app are grey. Days after today are empty. Today has an outline. A hover on a square shows the date, the weekday, and the count, for example "Tue 10 Nov 2026: 3 of 3". A day saved by catch-up says so in the hover text. A visible mark is added if it fits.
- C31. Above the heatmap the panel shows the current streak, the number of active days in the shown period, and the max streak. An active day is a day with 3 of 3 goals done (or saved by catch-up). A selector at the top right shows "Current" (the past 12 months) by default. The user can pick an earlier calendar year that has data.
- C32. The heatmap makes the panel wide, about 600 points. The builder may make the squares smaller to fit.
- C33. The first weekday of the grid follows the Mac's system setting.
- C34. Milestone badges, like the 50-day and 100-day badges on LeetCode, are not in v1.
- C9. Sign-in for backup: email link by default. Google sign-in is optional, and a user who wants it sets up their own Google OAuth client in their own Supabase project.
- C10. The app pushes the backup (see C20 for its content) after each change. A "Restore from backup" action pulls the data to a new Mac.
- C11. The repository name is `todo-target`.
- C12. The app starts at login. The user can turn this off in Settings.
- C13. The app stores local data in a JSON file in `~/Library/Application Support/todo-target/`.

## 9. Known unknowns (not confirmed)

- The Supabase free-plan numbers (500 MB per project, 1-week inactivity pause) come from third-party pages and a changelog entry. They are not read from the official page in full. Verify before the README states them.
- It is not confirmed whether a daily sync counts as activity and prevents the pause. Test this.
- It is not confirmed whether Google sign-in works while a project is paused.

## 10. Left to the builder

- Swift package layout and module split.
- How to make the `.app` bundle without Xcode, and how to set the app to run as a menu bar agent with no Dock icon.
- Exact colours for the 4 icon states. They must be easy to tell apart, also for users with colour blindness. Add a number badge or shape change if colour alone is not enough.
- Panel layout and visual style.
- Supabase table schema and row-level security rules.
- Conflict rule when the backup and local data differ. D8 is the guide: local wins.
- Test strategy. Logic for streak, day rollover, and list progress must have unit tests.
- README and setup steps for a new user, including the Gatekeeper step.
- The release job: a GitHub Actions workflow or a manual script that builds and attaches the zip.
- The icon colour thresholds in catch-up mode (C28).
- Unit tests for the catch-up rule: a missed day, a partly done day, two missed days in a row, and a missed day at the end of a month or year.
