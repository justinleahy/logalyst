# Security Review

- Reviewed: October 4, 2026
- Reviewed revision: `1809951` on `release-1.1`
- Status: All three findings remediated in source on October 4, 2026 (see [Remediation status](#remediation-status));
  the physical-device checks listed there remain before closing them

## Purpose

This review gives maintainers and release reviewers enough context to prioritize, implement and verify the
identified security improvements. It covers the native iPhone app, Apple Watch app, widgets, App Intents and the
shared persistence and networking code.

This is a source and configuration review, not a claim that the app or its dependencies are free of
vulnerabilities.

## Executive summary

The app has a generally strong privacy-oriented design. Health data is kept in HealthKit, App Intents that write
health data require authentication, CloudKit-backed fields opt into encryption, internet requests use HTTPS, and
the project has no external iOS package dependencies or embedded service credentials.

The review found two Medium-severity issues and one Low-severity issue:

| ID | Severity | Finding | Primary impact |
| --- | --- | --- | --- |
| SR-1 | Medium | HealthKit records are identified by forgeable metadata instead of their system-assigned source | False attribution and unsafe interpretation of another app's metadata |
| SR-2 | Medium | Widget health readings are not marked as privacy-sensitive | Health information can remain visible on locked or Always-On surfaces |
| SR-3 | Low | Remote nutrition responses are bounded only after buffering | App memory pressure, stalls or termination |

Recommended remediation order: SR-1, SR-2, then SR-3.

## Scope and method

The review used a STRIDE pass over the app's trust boundaries:

- HealthKit authorization, reads, writes, history, deletion and edit recovery
- SwiftData, private CloudKit synchronization, app-group defaults and caches
- iPhone and Watch communication through WatchConnectivity
- widgets, complications, controls, Siri and Shortcuts App Intents
- custom URL handling and notification actions
- camera and photo selection, Vision processing and on-device Foundation Models
- Open Food Facts requests, Apple Maps lookup, hidden web rendering and PDF parsing
- entitlements, privacy manifest, generated Info.plist settings and release build settings

The audit included static inspection of all 55 non-test Swift source files, targeted searches for secrets and
unsafe APIs, entitlement inspection and a review of every application network call site. No application code was
changed during the audit.

## Attack surface

### HealthKit

HealthKit is the main sensitive-data boundary. The app reads and writes health samples, stores food metadata on
food correlations, reads data written by other apps for totals and identifies records it considers its own for
History and editing.

### Shared and synchronized storage

Saved foods, recipes and settings use SwiftData and a private CloudKit database. Widget snapshots and some
settings use app-group `UserDefaults`. Favorites, goals and presets are sent between a paired iPhone and Apple
Watch through WatchConnectivity.

### System surfaces

Widgets and complications render health readings outside the app. App Intents and notification actions can write
health data. Custom URLs navigate to known screens but do not perform a save by themselves.

### Network and untrusted documents

The app sends barcodes to Open Food Facts. For restaurant lookups, it asks Apple Maps for a brand website, renders
same-site pages in a nonpersistent hidden web view, follows selected nutrition links and parses remote PDFs and
text. Website content, redirects, PDFs and API responses must all be treated as untrusted.

## Findings

### SR-1 — HealthKit records can be spoofed as Logalyst records

- **Severity:** Medium
- **Category:** Spoofing and tampering
- **Exploitability:** Another installed app with user-approved write access to the same HealthKit types
- **Business impact:** False attribution, confusing or duplicated edit state, and attacker-controlled source links

Logalyst tags each sample it creates with the custom metadata key `HealthLoggerEntry`. Its History query treats
every sample carrying that key as a Logalyst record. The query does not check the sample's `sourceRevision`, even
though HealthKit assigns that property from the app or device that actually created the sample.

HealthKit permits apps to add custom metadata. Another health app with the user's permission to write the same
sample type can therefore create a sample with `HealthLoggerEntry = true`. Logalyst will display that sample in
its own History and interpret its other custom metadata as food names, serving information and nutrition-source
details.

A forged entry cannot be silently deleted by Logalyst because HealthKit only allows an app to delete objects it
created. That limits the attack, but it also makes editing hazardous: Logalyst can save its replacement and then
fail to delete the forged original, leaving duplicate records and an unfinished edit. A forged food correlation
can additionally supply a misleading nutrition-source title and URL for the user to open.

Apple references:

- [HealthKit metadata and custom keys](https://developer.apple.com/documentation/healthkit/hkobject/metadata)
- [HealthKit source revision](https://developer.apple.com/documentation/healthkit/hkobject/sourcerevision)
- [HealthKit deletion ownership](https://developer.apple.com/documentation/healthkit/hkhealthstore/delete(_:withcompletion:)-17hzm)

#### Remediation

1. Centralize a provenance check that accepts only the iPhone and Watch bundle identifiers that legitimately
   create Logalyst samples.
2. Apply it before displaying, editing, deleting, recovering or interpreting Logalyst-specific metadata.
3. Require stored nutrition-source URLs to use `https` before presenting them as links.
4. Namespace new custom keys with the app's reverse-DNS identifier. Namespacing reduces accidental collisions but
   is not a substitute for validating `sourceRevision`.
5. Decide how older legitimate samples with unexpected source identifiers should appear before enforcing the
   allowlist.

#### Verification

- A sample created by the iPhone app appears in History and remains editable.
- A sample created by the Watch appears after Health synchronization and remains editable.
- A fixture sample from another signed HealthKit app with `HealthLoggerEntry = true` does not appear as a
  Logalyst-owned entry.
- A foreign food correlation cannot create a source link or enter the edit-recovery workflow.
- Existing genuine entries from supported released bundle identifiers still work.

### SR-2 — Widget readings are not redacted on locked surfaces

- **Severity:** Medium
- **Category:** Information disclosure
- **Exploitability:** A nearby person viewing a locked phone, Lock Screen or Always-On display
- **Business impact:** Disclosure of sensitive health readings

Widgets copy HealthKit-derived readings into app-group defaults. When HealthKit becomes inaccessible because the
device is locked, the providers intentionally fall back to those cached readings. This supports continuity, but
the widget views do not mark health values with SwiftUI's `privacySensitive()` modifier. The widget extension also
does not request complete Data Protection.

A user can configure the Metric widget for blood glucose, blood pressure, symptoms, sexual activity or another
sensitive metric. After the reading is cached, locking the device does not give WidgetKit the information it
needs to redact that value according to the user's Lock Screen or Always-On privacy preference.

The user deliberately chose the widget, which limits the severity. However, Apple specifically provides
privacy-sensitive redaction so that choosing a widget does not imply choosing to expose its value while locked.

Apple reference:

- [Hiding sensitive widget content](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)

#### Remediation

1. Mark health-value content, or each health widget's root view, with `.privacySensitive()`.
2. Provide useful redacted placeholders that identify the widget without revealing the measurement.
3. If all widget content should disappear while locked, add the Data Protection capability with
   `NSFileProtectionComplete` to the widget extensions.
4. For stronger at-rest protection, replace health snapshots in app-group defaults with a small shared file written
   using complete file protection. Accept that a protected cache will be unavailable while locked.
5. Keep action intents protected by `requiresAuthentication`.

#### Verification

- With sensitive widget access disabled in Face ID and Passcode settings, configured health values are redacted on
  the Lock Screen.
- Watch complications hide sensitive values during Always On when the corresponding setting is enabled.
- Values reappear after authentication without losing the widget configuration.
- Quick-log controls still require authentication and do not write health data from a locked device.
- A reboot-before-first-unlock test does not expose cached values.

### SR-3 — Remote nutrition responses can consume excessive resources

- **Severity:** Low
- **Category:** Denial of service
- **Exploitability:** A compromised or malicious remote nutrition site after the user starts a lookup
- **Business impact:** Temporary app stalls, memory pressure or process termination

Open Food Facts responses are completely buffered and then decoded without a response-size limit. Sitemap and PDF
downloads have nominal byte limits, but the code checks those limits only after `URLSession` has returned the full
body. A PDF below the compressed byte limit can also expand into an excessive number of pages or a very large
amount of extracted text, and the reader currently traverses every page.

The existing lookup timeout, page-count limit for websites, PDF-count limit and HTTPS requirement reduce exposure.
The remaining impact is local availability rather than data disclosure or code execution, so the issue is Low
severity.

#### Remediation

1. Reject a response before download when a trustworthy `Content-Length` exceeds the relevant limit.
2. Stream response bytes and cancel as soon as the actual limit is crossed; do not rely on `Content-Length` alone.
3. Validate HTTP status and MIME type before JSON, XML or PDF parsing.
4. Cap PDF page count, per-page extracted characters and total extracted characters.
5. Add a reasonable maximum barcode length before constructing the Open Food Facts URL.
6. Keep the outer task timeout as a final backstop rather than the primary resource limit.

#### Verification

- A fixture server that omits `Content-Length` and streams beyond the limit is cancelled at the configured byte
  boundary.
- An oversized declared response is rejected without downloading its body.
- A small PDF with excessive pages or extracted text is rejected before traversing the whole document.
- Normal Open Food Facts JSON, sitemap and nutrition PDF fixtures still parse successfully.
- Cancellation leaves the UI responsive and does not cache a partial result.

## Remediation status

Remediated on October 4, 2026, on `release-1.1`. The full `HealthLoggerTests` run on the iPhone 18 Pro (iOS 27.0)
simulator passed 218 tests in 32 suites, including the new `SecurityReviewTests.swift`. The full
`HealthLoggerUITests` run on the same simulator ran 27 tests: 23 passed, 3 were skipped as designed and
`testReplaceAFoodWithAPublishedOne` failed once, finding "Lime Wedge" text still on screen after the replacement.
That test uses stubbed lookups and passed when rerun alone, both with these changes and on `1809951` without them.
The likely cause is a food logged by an earlier test showing behind the sheet, since the test checks the whole
screen; this hasn't been confirmed. All four targets built for the simulator in Debug; a Release build and an
App Store-exported artifact haven't been checked.

### SR-1 — Remediated

- `HealthStore.isOwn(_:)` accepts a sample only when it carries `HealthLoggerEntry` **and** its
  `sourceRevision.source.bundleIdentifier` is one of `HealthStore.ownBundleIdentifiers`: the iPhone app, the Watch
  app and their two widget extensions, matched exactly.
- `recentEntries` filters with it, so History, Nutrition, recents, edit sources and daily food coverage never list
  or interpret another app's metadata. `delete(_:)` and edits refuse a foreign entry with `EntryError.notOwn`, and
  edit recovery (`finish`) neither accepts a foreign correction nor deletes a foreign original.
- Nutrition sources read from Health metadata must be `https` with a host (`URL.isSecureWeb`), and `SourceRow` only
  offers a link for such a URL, which also covers sources synced through iCloud.
- Custom keys keep their existing names so earlier entries still read; new keys are to be named
  `com.justinleahy.HealthLogger.<name>`, as noted beside them.
- Legacy sources: the four bundle identifiers are unchanged since the first commit, so every genuine entry from a
  released build matches and none needed special handling.
- Tests: `EntryProvenanceTests` (allowlist, look-alike identifiers, untagged samples, `https`-only sources) and
  `OwnEntryHealthTests` (an entry the app saves is listed as its own and deletes); the existing edit, recovery and
  food tests pass with the check in place.
- Remaining: the cross-app spoof test with a separately signed fixture app, and confirming Watch-written samples
  appear after Health sync on paired devices.

### SR-2 — Remediated

- A `healthPrivate` modifier (`Widgets/WidgetSupport.swift`) marks readings, totals, gauges and progress bars in
  the Metric, Nutrition and Water widgets and Watch complications `privacySensitive()`. When WidgetKit redacts for
  privacy it shows a placeholder instead, the metric's symbol or name, so the widget still identifies itself.
  Spoken accessibility labels carrying values are inside the redacted content.
- Quick Log shows no readings. The Log Water and Log Metric controls are unchanged, and every health-writing intent
  still uses `requiresAuthentication`.
- Optional steps 3–4 were not adopted: complete Data Protection for the extensions and a completely protected cache
  would make widgets show nothing while locked even for users who allow it. The cache stays in app-group
  defaults, which are unreadable before first unlock, and its values are now redacted wherever the user asked.
- Remaining: on-device Lock Screen, Always On and reboot-before-first-unlock checks; redaction isn't observable in
  simulator unit tests.

### SR-3 — Remediated

- `BoundedDownload.data` (`HealthLogger/BoundedDownload.swift`) streams responses, checks the status and Content-Type
  before reading the body, refuses an oversized declared length before downloading, and cancels as soon as the
  bytes received pass the limit. It's used for Open Food Facts (1 MB, JSON), robots.txt and sitemaps (5 MB, text or
  XML) and PDFs (15 MB, PDF or generic binary).
- `PDFText` refuses a PDF over 60 pages before reading any page, and stops at 40,000 characters on a page or 600,000
  in all. PDFs are read off the main actor.
- Barcodes longer than 14 digits (GTIN-14) aren't looked up. The outer lookup timeout stays as a backstop, and
  failures throw before anything is cached.
- Tests: `BoundedDownloadTests` (normal response, an unlengthed stream cut off at the limit with the server told
  to stop, a declared oversize refused, 404 and wrong type refused, overlong barcode) and `PDFTextTests`.

## Positive controls observed

- Health-writing App Intents require device authentication and validate numeric input ranges.
- Profile data such as date of birth and biological sex is requested only when the user opens Suggest Goals.
- SwiftData uses a private CloudKit database, and every synced model field opts into CloudKit encryption.
- Internet endpoints use HTTPS, and App Transport Security is not weakened.
- The hidden web view uses a nonpersistent data store, blocks selected tracker classes and restricts top-level
  navigation to the chosen registrable site.
- Deep links accept only known routes and known metric identifiers, and they navigate rather than writing data.
- No embedded passwords, API keys, private keys or third-party iOS package dependencies were found.
- Nutrition cache files use atomic writes and protection until first user authentication.

## Remediation and release recommendation

SR-1 and SR-2 should be resolved before treating the current release as hardened for sensitive health data. SR-3
is suitable for the same hardening pass but does not need to block a release by itself if the current functional
limits and timeout are accepted.

After remediation:

1. Add targeted regression tests for every verification item above.
2. Run the full unit, HealthKit and UI suites on the supported simulator versions.
3. Perform SR-1's cross-app source test and SR-2's locked-device checks on physical devices.
4. Inspect the final App Store-exported artifact, not only a development-signed archive.
5. Recheck the privacy policy and App Store Connect privacy answers against the final behavior.

## Limitations

The review did not include:

- dynamic instrumentation or penetration testing on a physical device
- a separate signed attacker/fixture application for HealthKit source-spoofing validation
- verification of the deployed production CloudKit schema or record permissions
- inspection of App Store Connect privacy declarations
- the final App Store-resigned binary
- Apple framework or operating-system vulnerability research
- the public website, except where the native app reads remote brand content

These limitations do not invalidate the source findings; they define the additional evidence required before
closing them.
