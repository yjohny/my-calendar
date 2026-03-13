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
- **Models/CalendarStore.swift** — Main `@Observable` store. Manages `dayTexts` (full interleaved text per date — events and journal mixed in user's order) and `eventColorMap` (calendar colors from EventKit keyed by title+time). Parses user text, syncs events to EventKit, stores full text to file preserving layout order. Events and journal text can be freely interleaved.
- **Parsing/** — `LineParser` parses lines into `.event`, `.allDay`, `.eventNote`, `.journal`, `.blank`. `TimePatterns` has regex for time formats and recurrence markers.
- **Persistence/** — `EventKitManager` (actor) wraps EKEventStore CRUD. `EventKitSync` converts between text lines and `EKEvent` objects. `FileStore` (actor) handles per-day text files. `ChangeCoalescer` debounces saves.
- **Views/** — SwiftUI views. `DayTextEditor` toggles between styled display (`StyledTextView`) and edit mode (`TextEditor`). `NavigationStack` with bottom toolbar for Today/Search/Calendars/Help. `DateScrubber` on right edge. `SearchView` provides cross-day search.

## Key Patterns
- Uses rounded (SF Rounded) fonts throughout for a softer, modern feel. Monospaced is used only for time portions in event lines (e.g., `9:00 AM`) to maintain clean tabular alignment.
- Event format: `9:00 AM - Title`, `9:00-10:30 AM - Title`, `* All Day Event`
- Recurrence: `(daily)`, `(every weekday)`, `(every Monday)`, `(monthly 15th)`, `(yearly)`
- Recurring events from EventKit are treated as read-only occurrences during sync — only non-recurring TextCal events are removed and recreated on edit to avoid duplication
- **Multiple calendars**: Read-all, write-to-default model. `EventKitManager.events(for:)` fetches from all calendars (`calendars: nil`). The user picks a default calendar via `CalendarSettings` (stored in UserDefaults); new events go there. The `[CalendarName]` suffix syntax (e.g., `9:00 AM - Meeting [Work]`) overrides the default for individual events. The legacy prefix syntax (e.g., `[Work] 9:00 AM - Meeting`) is still supported for backward compatibility. Default-calendar events are deleted and recreated on each sync; override-calendar events are create-only (matched by title, start time, and end time to avoid duplicates). The "TextCal" calendar is the fallback if no default is set.
- **Calendar colors**: `StyledTextView` uses `EventColorKey` (title+time→Color map built from EventKit) to look up calendar colors for event lines. Events from non-default calendars show a subtle calendar name label.
- **Interleaved text**: The per-day file stores the full text as the user typed it — events and journal text mixed in any order. Events are parsed out for EventKit sync but the layout order is preserved. EventKit-only events (added from other apps) appear as `unmatchedEvents` below the user's text.

## Known Patterns to Watch
- **Calendar name suffix vs prefix**: `LineParser.parse()` checks for a `[CalendarName]` suffix first (new format: `9:00 AM - Meeting [Work]`), then falls back to prefix (legacy: `[Work] 9:00 AM - Meeting`). `EventKitSync.textLine(from:defaultCalendarId:)` renders the suffix format. `StyledTextView.stripCalendarPrefix()` strips both formats for display. Both formats must be kept in sync across these three files.
- **Recurring event sync**: `syncEventsToEventKit` skips parsed events that match existing recurring occurrences (by title, time, all-day status). Non-recurring events are deleted and recreated. Be careful not to break this deduplication logic.
- **Recurrence round-tripping**: "Every weekday" is stored in EventKit as a `.weekly` rule with 5 `daysOfTheWeek` (Mon-Fri), not as `.daily`. `EventKitSync.recurrenceText()` must detect this pattern under the `.weekly` case to render it back as `(every weekday)`.
- **EKWeekday raw values**: When building collections of `EKWeekday.rawValue` (Int), always fully qualify each enum case (e.g., `EKWeekday.monday.rawValue, EKWeekday.tuesday.rawValue`). Swift infers shorthand like `.tuesday.rawValue` as members of `Int` rather than `EKWeekday`, causing build errors.
- **Time validation**: `TimePatterns.parseTime()` validates hours (0-23) and minutes (0-59), returning `nil` for out-of-range values.
- **All-day events**: EventKit requires all-day event `endDate` to be the start of the *next* day, not the same day as `startDate`.
- **DayTextEditor refresh**: Uses a cancellable `refreshTask` to prevent stale async results from overwriting current state when the user scrolls quickly between dates.
- **StyledTextView**: Uses concatenated `Text` views (not `HStack`) so long event names wrap to the next line naturally.
- **Toolbar**: Today, Search, Calendars, and Help are in a standard iOS bottom toolbar (`NavigationStack` + `ToolbarItemGroup(.bottomBar)`).
- **Search**: `SearchView` searches `CalendarStore.searchDayTexts(query:)` across all in-memory `dayTexts`. Debounced 300ms via `.task(id:)`. Results grouped by date (most recent first) with query text highlighted. Tapping a result dismisses the sheet and calls `viewModel.jumpTo(date:)`.
- **Default event duration**: Events without an explicit end time default to 1 hour in `EventKitManager.saveEvent()`. `EventKitSync.timedLine()` detects this default (duration == 3600s) and hides the end time when rendering back to text, preserving the user's original format.
- **SwiftUI List with non-Identifiable types**: When using `EKCalendar` or other non-`Identifiable` EventKit types in a `List`, use `List { ForEach(items, id: \.keyPath) { ... } }` instead of `List(items, id: \.keyPath) { ... }`. The direct `List` initializer fails to infer generic parameters for these types, causing cascading build errors. Additionally, always fully qualify the key path root type *and* the closure parameter type in `ForEach` (e.g., `ForEach(calendars, id: \EKCalendar.calendarIdentifier) { (calendar: EKCalendar) in`), otherwise Swift cannot infer the generic parameters and produces cascading type errors.

## Future Improvements
- **Search: unit tests** — Add tests for `CalendarStore.searchDayTexts()` covering case-insensitivity, empty queries, multi-line matches, and date sorting.
- **Search: EventKit events** — Currently search only covers `dayTexts` (user-typed text). Could also search unmatched EventKit events (from other apps) that haven't been typed into TextCal yet.
- **Smarter text input** — Calendar name auto-complete when typing `[`, natural language shortcuts (e.g., "lunch tomorrow at noon"), or smart suggestions based on past events.
- **Undo/redo** — SwiftUI `TextEditor` supports system undo, but `DayTextEditor.refreshState()` overwrites state on dismiss which can clear the undo stack. Wire up `UndoManager` properly.
- **Accessibility** — VoiceOver labels for styled event lines, Dynamic Type support audit, reduce-motion alternatives for scroll animations.
- **iPad keyboard shortcuts** — Cmd+F for search, Cmd+T for today, arrow keys for date navigation.
