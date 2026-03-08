# TextCal - Development Guide

## Project Overview
A text-based iOS calendar app (Swift/SwiftUI, iOS 17+) that lets users type events in natural text format. Events sync bidirectionally with Apple EventKit; journal/freeform text is stored as per-day files.

## Build & Run
```bash
swift build          # Build the project
swift test           # Run tests
```
Xcode project: `TextCal.xcodeproj`

## Architecture
- **Models/CalendarStore.swift** — Main `@Observable` store. Manages `journals` (freeform text per date) and `eventLines` (rendered from EventKit). Parses user text, separates events from journal, syncs events to EventKit.
- **Parsing/** — `LineParser` parses lines into `.event`, `.allDay`, `.eventNote`, `.journal`, `.blank`. `TimePatterns` has regex for time formats and recurrence markers.
- **Persistence/** — `EventKitManager` (actor) wraps EKEventStore CRUD. `EventKitSync` converts between text lines and `EKEvent` objects. `FileStore` (actor) handles per-day journal files. `ChangeCoalescer` debounces saves.
- **Views/** — SwiftUI views. `DayTextEditor` toggles between styled display (`StyledTextView`) and edit mode (`TextEditor`). Floating buttons for Today/Help. `DateScrubber` on right edge.

## Key Patterns
- All text uses monospaced fonts for calendar-like appearance
- Event format: `9:00 AM - Title`, `9:00-10:30 AM - Title`, `* All Day Event`
- Recurrence: `(daily)`, `(every weekday)`, `(every Monday)`, `(monthly 15th)`, `(yearly)`
- Recurring events from EventKit are treated as read-only occurrences during sync — only non-recurring TextCal events are removed and recreated on edit to avoid duplication
- **Multiple calendars**: Read-all, write-to-default model. `EventKitManager.events(for:)` fetches from all calendars (`calendars: nil`). The user picks a default calendar via `CalendarSettings` (stored in UserDefaults); new events go there. The `[CalendarName]` prefix syntax (e.g., `[Work] 9:00 AM - Meeting`) overrides the default for individual events. Default-calendar events are deleted and recreated on each sync; override-calendar events are create-only (matched by title, start time, and end time to avoid duplicates). The "TextCal" calendar is the fallback if no default is set.
- **Calendar colors**: `StyledTextView` uses each event's `EKCalendar.cgColor` for the time/star accent color. Events from non-default calendars show a subtle calendar name label.

## Known Patterns to Watch
- **Recurring event sync**: `syncEventsToEventKit` skips parsed events that match existing recurring occurrences (by title, time, all-day status). Non-recurring events are deleted and recreated. Be careful not to break this deduplication logic.
- **Recurrence round-tripping**: "Every weekday" is stored in EventKit as a `.weekly` rule with 5 `daysOfTheWeek` (Mon-Fri), not as `.daily`. `EventKitSync.recurrenceText()` must detect this pattern under the `.weekly` case to render it back as `(every weekday)`.
- **EKWeekday raw values**: When building collections of `EKWeekday.rawValue` (Int), always fully qualify each enum case (e.g., `EKWeekday.monday.rawValue, EKWeekday.tuesday.rawValue`). Swift infers shorthand like `.tuesday.rawValue` as members of `Int` rather than `EKWeekday`, causing build errors.
- **Time validation**: `TimePatterns.parseTime()` validates hours (0-23) and minutes (0-59), returning `nil` for out-of-range values.
- **All-day events**: EventKit requires all-day event `endDate` to be the start of the *next* day, not the same day as `startDate`.
- **DayTextEditor refresh**: Uses a cancellable `refreshTask` to prevent stale async results from overwriting current state when the user scrolls quickly between dates.
- **StyledTextView**: Uses concatenated `Text` views (not `HStack`) so long event names wrap to the next line naturally.
- **Buttons**: Today, Help, and Calendar overlay buttons are intentionally subtle/small to avoid visual clutter.
- **SwiftUI List with non-Identifiable types**: When using `EKCalendar` or other non-`Identifiable` EventKit types in a `List`, use `List { ForEach(items, id: \.keyPath) { ... } }` instead of `List(items, id: \.keyPath) { ... }`. The direct `List` initializer fails to infer generic parameters for these types, causing cascading build errors. Additionally, always fully qualify the key path root type *and* the closure parameter type in `ForEach` (e.g., `ForEach(calendars, id: \EKCalendar.calendarIdentifier) { (calendar: EKCalendar) in`), otherwise Swift cannot infer the generic parameters and produces cascading type errors.
