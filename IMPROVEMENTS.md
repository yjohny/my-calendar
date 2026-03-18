# TextCal — Improvement Proposals

A prioritized list of improvements based on a thorough review of the codebase, current feature set, and gaps relative to what users expect from a modern calendar app.

---

## High Impact — Core Experience

### 1. Inline Autocomplete & Smart Input
**Problem:** Users must memorize exact syntax for calendar names, recurrence patterns, and time formats.
**Proposal:**
- Show an autocomplete dropdown when the user types `[` — list available calendars from EventKit.
- Offer recurrence pattern suggestions when typing `(` — e.g., `(daily)`, `(every weekday)`, `(every Monday)`.
- Auto-suggest times in 15-min increments when the user starts typing a digit at the beginning of a line.
- Natural language shortcuts: typing "lunch tomorrow at noon" could auto-expand to `12:00 PM - Lunch` on the next day's text.

**Complexity:** Medium — requires a custom text input overlay or SwiftUI `.searchSuggestions()`-style approach.

### 2. Undo/Redo Support
**Problem:** CLAUDE.md documents that `DayTextEditor.refreshState()` overwrites state on dismiss, clearing the undo stack. Users lose edits with no recourse.
**Proposal:**
- Wire up `UndoManager` properly in `DayTextEditor` so that switching between display/edit modes preserves undo history.
- Add Cmd+Z / Cmd+Shift+Z keyboard shortcuts explicitly.
- Consider keeping a per-day edit history (last N snapshots) in `FileStore` for manual revert.

**Complexity:** Medium — SwiftUI's `UndoManager` integration is tricky but well-documented for iOS 17+.

### 3. Search EventKit Events (Not Just User Text)
**Problem:** `SearchView` only searches `dayTexts`. Events added from other apps (Mail invites, shared calendars) are invisible to search unless the user has typed them in.
**Proposal:**
- Extend `CalendarStore.searchDayTexts(query:)` to also query `EKEventStore` via a predicate-based search across a date range.
- Merge results: show user-typed matches first, then EventKit-only matches in a separate "From other apps" section.
- This makes TextCal a true unified search across all calendar sources.

**Complexity:** Low — EventKit's `predicateForEvents(withStart:end:calendars:)` already supports this; just need to add title filtering client-side.

---

## High Impact — New Features

### 4. Home Screen & Lock Screen Widgets
**Problem:** Users must open the app to see today's events. Every major calendar app has widgets.
**Proposal:**
- **Small widget:** Today's date + count of events.
- **Medium widget:** Today's events list (first 4-5 lines of styled text).
- **Large widget:** Today + tomorrow, showing the interleaved text view.
- **Lock screen widget:** Next upcoming event with time.
- Use `WidgetKit` + shared `AppGroup` container so `FileStore` data is accessible from the widget extension.

**Complexity:** Medium — requires a widget extension target, shared container, and timeline provider.

### 5. Notifications & Reminders
**Problem:** No way to get alerted before an event. Users must rely on the system Calendar app for notifications.
**Proposal:**
- Add optional alert syntax: `9:00 AM - Meeting (!15m)` to set a 15-minute reminder.
- Default alerts configurable in settings (e.g., "remind me 10 minutes before all events").
- Use `UNUserNotificationCenter` for local notifications, scheduled when events sync.
- Alternatively, set `EKAlarm` on the `EKEvent` during sync so the system Calendar handles notifications.

**Complexity:** Medium — `EKAlarm` approach is simpler and leverages existing infrastructure.

### 6. Multi-Day & Week View
**Problem:** The current scroll-through view works well for daily use but makes it hard to see the week at a glance.
**Proposal:**
- Add a compact "Week view" toggle showing 7 days in a condensed grid with event dots/bars.
- Tapping a day in week view navigates to that day's full text view.
- Keep the existing scroll view as the default — week view is an optional mode.
- Consider a month-grid view as well (dots for days with events, tap to jump).

**Complexity:** Medium-High — new view hierarchy, but can reuse existing `CalendarStore` data.

---

## Medium Impact — Quality of Life

### 7. Drag Events Between Days
**Problem:** Moving an event to a different day requires manually cutting text from one day and pasting it into another.
**Proposal:**
- Long-press an event line in display mode to pick it up.
- Drag to a different day section (or to the date scrubber to target a distant date).
- On drop, remove the line from the source day's text and append it to the target day's text.
- Update EventKit sync for both days.

**Complexity:** Medium — SwiftUI's `draggable()` / `dropDestination()` modifiers (iOS 16+) handle most of this.

### 8. Event Templates / Quick Add
**Problem:** Users re-type the same events frequently (daily standups, weekly meetings).
**Proposal:**
- Let users save "templates" — named text snippets that can be inserted with a shortcut.
- Quick-add button ("+") that shows recent/frequent event titles for one-tap insertion.
- Templates stored in a simple JSON file alongside day text files.

**Complexity:** Low — small UI addition + simple persistence.

### 9. Calendar Visibility Toggles
**Problem:** `CalendarPickerView` only lets users choose a default calendar. There's no way to hide calendars you don't want to see (e.g., "Holidays" or a spouse's calendar).
**Proposal:**
- Add toggle switches per calendar in `CalendarPickerView`.
- Hidden calendars are excluded from `EventKitManager.events(for:)` queries.
- Store visibility preferences in `UserDefaults`.

**Complexity:** Low — filter the `calendars` parameter in the EventKit predicate.

### 10. Conflict & Overlap Warnings
**Problem:** No visual indication when events overlap in time.
**Proposal:**
- After parsing event lines, detect time overlaps within the same day.
- Show a subtle warning icon or highlight on conflicting events in `StyledTextView`.
- Optional: show a "You have overlapping events" banner at the top of the day.

**Complexity:** Low — compare parsed start/end times in `CalendarStore.update()`.

### 11. Export & Backup
**Problem:** No way to export data outside the app. Day text files exist on disk but aren't user-accessible.
**Proposal:**
- "Export" option in settings: generate a `.zip` of all day text files, or a single `.ics` file of all events.
- Share sheet integration for individual days (share as text or `.ics`).
- iCloud backup of the day text directory (via `NSUbiquitousKeyValueStore` or iCloud Documents).

**Complexity:** Low-Medium — `.ics` generation requires building the iCalendar format, but text export is trivial.

---

## Lower Impact — Polish & Robustness

### 12. Implement Documented but Missing Features
**Problem:** `SyntaxHelpView` documents two features that aren't implemented:
- "Repeating events show slightly faded" — no visual differentiation visible in `StyledTextView`.
- "Long-press a repeated event to skip one day or stop all future occurrences" — no long-press gesture handler exists.

**Proposal:**
- Add `.opacity(0.7)` or a subtle style change in `StyledTextView` for recurring event lines.
- Add `.contextMenu` or `.onLongPressGesture` to recurring event lines with "Skip this day" / "Stop repeating" actions.

**Complexity:** Low — the parsing already identifies recurring events; just need UI hooks.

### 13. Sync Error Recovery & Retry
**Problem:** Sync errors auto-dismiss after 5 seconds and can be missed. No retry mechanism.
**Proposal:**
- Keep the last error visible until explicitly dismissed (not auto-dismiss).
- Add a "Retry" button on error banners.
- Show a persistent badge on the sync status indicator if there are unsaved changes.
- Add a "Sync Now" manual trigger button for users who want explicit control.

**Complexity:** Low — UI changes in the toolbar status indicator.

### 14. Improved Accessibility for Unmatched Events
**Problem:** Unmatched EventKit events (from other apps) appended at the bottom of each day have no VoiceOver announcement distinguishing them from user-typed content.
**Proposal:**
- Add an accessibility header: "Events from other calendars" before the unmatched events section.
- Each unmatched event should have a label including its calendar name for context.

**Complexity:** Low — small `StyledTextView` addition.

### 15. Markdown Support for Journal Text
**Problem:** Journal/freeform text is plain — no formatting options.
**Proposal:**
- Support basic markdown in journal lines: **bold**, *italic*, ~~strikethrough~~, `- bullet lists`.
- Render in `StyledTextView` using `AttributedString(markdown:)` (available in iOS 15+).
- Keep the raw text as-is in the file — only render styled in display mode.

**Complexity:** Low — `AttributedString(markdown:)` does the heavy lifting.

---

## Summary Priority Matrix

| Priority | Improvement | Effort | User Impact |
|----------|------------|--------|-------------|
| P0 | Inline Autocomplete (#1) | Medium | High |
| P0 | Undo/Redo (#2) | Medium | High |
| P0 | Search EventKit Events (#3) | Low | High |
| P1 | Widgets (#4) | Medium | High |
| P1 | Notifications (#5) | Medium | High |
| P1 | Implement Documented Features (#12) | Low | Medium |
| P1 | Calendar Visibility Toggles (#9) | Low | Medium |
| P2 | Week/Month View (#6) | High | Medium |
| P2 | Drag Between Days (#7) | Medium | Medium |
| P2 | Event Templates (#8) | Low | Medium |
| P2 | Conflict Warnings (#10) | Low | Medium |
| P2 | Export & Backup (#11) | Medium | Medium |
| P3 | Sync Error Recovery (#13) | Low | Low |
| P3 | Accessibility Fixes (#14) | Low | Low |
| P3 | Markdown Journal (#15) | Low | Low |
