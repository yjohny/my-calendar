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
- **Persistence/** — `EventKitManager` (actor) wraps EKEventStore CRUD. `FileStore` (actor) handles per-day journal files. `ChangeCoalescer` debounces saves.
- **Views/** — SwiftUI views. `DayTextEditor` toggles between styled display (`StyledTextView`) and edit mode (`TextEditor`). Floating buttons for Today/Help. `DateScrubber` on right edge.

## Key Patterns
- All text uses monospaced fonts for calendar-like appearance
- Event format: `9:00 AM - Title`, `9:00-10:30 AM - Title`, `* All Day Event`
- Recurrence: `(daily)`, `(every weekday)`, `(every Monday)`, `(monthly 15th)`, `(yearly)`
- Recurring events from EventKit are treated as read-only occurrences during sync — only non-recurring TextCal events are removed and recreated on edit to avoid duplication
- **Multiple calendars**: Read-all, write-to-default model. `EventKitManager.events(for:)` fetches from all calendars (`calendars: nil`). The user picks a default calendar via `CalendarSettings` (stored in UserDefaults); new events go there. The `[CalendarName]` prefix syntax (e.g., `[Work] 9:00 AM - Meeting`) overrides the default for individual events. Events are managed per-calendar: non-recurring events in each target calendar are removed and recreated during sync. The "TextCal" calendar is the fallback if no default is set.
- **Calendar colors**: `StyledTextView` uses each event's `EKCalendar.cgColor` for the time/star accent color. Events from non-default calendars show a subtle calendar name label.

## Known Patterns to Watch
- **Recurring event sync**: `syncEventsToEventKit` skips parsed events that match existing recurring occurrences (by title, time, all-day status). Non-recurring events are deleted and recreated. Be careful not to break this deduplication logic.
- **StyledTextView**: Uses concatenated `Text` views (not `HStack`) so long event names wrap to the next line naturally.
- **Buttons**: Today, Help, and Calendar overlay buttons are intentionally subtle/small to avoid visual clutter.
