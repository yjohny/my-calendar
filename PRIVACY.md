# TextCal Privacy Policy

_Last updated: April 2026_

TextCal is a text-based calendar app for iOS. Your privacy is straightforward: **TextCal collects nothing.**

## What we collect

Nothing. TextCal has no servers, no analytics, no advertising SDKs, and no third-party tracking. We do not collect, transmit, sell, or share any personal information.

## Where your data lives

- **Journal text and notes** are stored as plain `.txt` files in TextCal's private container on your device.
- **Calendar events** are stored in Apple's Calendar database (EventKit) on your device. If you have iCloud Calendar enabled in iOS Settings, Apple syncs them across your devices using your iCloud account — TextCal is not involved in that sync and never sees the data leave the device.
- **App settings** (default calendar, hidden calendars, dismissed banners) are stored in iOS UserDefaults on your device.

All data stays on your device unless you choose to export it via the iOS share sheet.

## Permissions we request

- **Calendar access** (`NSCalendarsFullAccessUsageDescription`) — required so TextCal can read and write your events. You control this in iOS Settings → Privacy & Security → Calendars.

## Network access

TextCal makes no network requests. The app does not include any networking code beyond what iOS itself uses for system services.

## Third parties

TextCal uses no third-party SDKs. It depends only on Apple's system frameworks (SwiftUI, UIKit, EventKit, Foundation).

## Children

TextCal is suitable for all ages and does not knowingly collect data from anyone, including children under 13.

## Changes to this policy

If this policy ever changes, the updated version will be posted here with a new "Last updated" date.

## Contact

Questions? Open an issue at the project's GitHub repository.
