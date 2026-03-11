# TextCal Improvement Plan

## 1. Search Across Days (Main Feature)

**Goal:** Let users search all their events and journal text across every day, with results grouped by date that can be tapped to navigate.

### Changes:

**a) `FileStore.swift` — Add search method**
- Add `searchAllDays(query:)` that reads all per-day `.txt` files and returns matching lines grouped by date
- Case-insensitive substring matching
- Returns `[(date: Date, matchingLines: [(lineNumber: Int, text: String)])]` sorted by date descending (most recent first)

**b) `CalendarStore.swift` — Expose search to views**
- Add `search(query:) -> [SearchResult]` that searches both `dayTexts` (in-memory, includes unsaved changes) and delegates to `FileStore` for dates not yet loaded
- `SearchResult` struct: `date`, `matchingLines` with line text and line type (event/journal/allDay)

**c) New `SearchView.swift`**
- Presented as a sheet from a new search button in the toolbar
- Search bar at top with real-time filtering (debounced ~300ms)
- Results grouped by date, each showing the date header and matching lines with the query highlighted
- Tapping a result dismisses search and scrolls to that day
- Uses `StyledTextView`-style rendering for matched lines (color-coded events)

**d) `CalendarDocumentView.swift` — Add search button**
- Add a magnifying glass icon button in the bottom toolbar (between Today and Calendars)
- Presents `SearchView` as a sheet
- Pass a callback so search results can trigger `viewModel.jumpTo(date:)`

## 2. Default Event Duration (Smarter Input)

**Goal:** Events typed without an end time (e.g., `9:00 AM - Meeting`) currently have no duration in EventKit, which makes them appear as zero-length. Give them a sensible 1-hour default.

### Changes:

**`CalendarStore.swift` — `saveEventToKit`**
- When `endTime` is nil, calculate a default end time = start time + 1 hour
- Pass this to `EventKitManager.saveEvent()`

## 3. Polish: Undo Support in Text Editor

**Goal:** Right now, once you edit and dismiss, there's no undo. Add undo/redo support to the day text editor using the system `UndoManager`.

### Changes:

**`DayTextEditor.swift`**
- Access the SwiftUI `@Environment(\.undoManager)` and wire it into the text editing flow
- SwiftUI's `TextEditor` already integrates with the system undo manager, so the main fix is ensuring we don't replace the text state in ways that break the undo stack (currently `refreshState()` overwrites `text` on dismiss, which clears undo history)
- Add shake-to-undo support by not fighting the system undo manager

---

## Files Modified
- `Sources/TextCal/Persistence/FileStore.swift` — search method
- `Sources/TextCal/Models/CalendarStore.swift` — search API, default duration
- `Sources/TextCal/Views/SearchView.swift` — **new file**
- `Sources/TextCal/Views/CalendarDocumentView.swift` — search button + sheet
- `Sources/TextCal/Views/DayTextEditor.swift` — undo support
