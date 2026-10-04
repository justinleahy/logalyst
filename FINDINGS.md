# Roadmap implementation review

Reviewed: October 3, 2026  
Fixes validated: October 3, 2026, against implementation commit `70e903e`\
Scope: `ROADMAP.md`, the corresponding implementation, and existing tests  
Remaining findings fixed: October 3, 2026, on top of C5 commit `54435f4`\
Status: F2, F4 and F8 were fixed afterwards (see each finding's *Fixed* paragraph and [Fix verification](#fix-verification)); those fixes haven't been independently re-validated. F1, F3, F5 and F6 are resolved for their original cases. F7's fix is source-verified; dedicated UI/iCloud validation remains outstanding. Release validation remains incomplete.

The reviewed 1.1 features are broadly implemented. C5 (restaurant and brand nutrition lookup for meal photos) was added to the roadmap after this review and implemented afterwards, on top of `70e903e`; this review doesn't cover it. The descriptions and initial evidence under F1–F7 document the original review; each finding's validation paragraph records its current disposition. Original source references may have shifted in the fix commit; references in the validation paragraphs and F8 refer to `70e903e`. Neither the review nor the subsequent validation changed implementation files. Fresh tests passed, but additional probes reproduced the remaining defects; see [Fix verification](#fix-verification).

## Implementation findings

### F1 — High: Edit recovery can delete the only remaining entry

**Roadmap:** C3 — Edit logged food and shared edit recovery  
**Source:** [Shared/HealthStore.swift:679](Shared/HealthStore.swift#L679), with ordinary deletion at [line 607](Shared/HealthStore.swift#L607)  
**Evidence:** Source-traced failure sequence; not exercised in HealthKit during this review.

After a replacement saves but deletion of the original fails:

1. Choose **Later** in the recovery alert.
2. Delete the corrected entry through History's normal delete action.
3. Choose **Remove Original** in the unfinished-edit section.

Deleting the correction leaves the pending edit unchanged. `finishEdit` checks only whether the original exists and deletes it without checking that the replacement still exists. Both entries are then gone.

**Suggested correction:** Revalidate the replacement before deleting the original, and reconcile pending operations when either entry is manually deleted.

**Validated — original case resolved:** `finishEdit` looks up the correction before deleting the original; if it's gone, the original is kept, the edit is dropped and `EditError.correctionMissing` is reported (the retry alert closes instead of offering Try Again). `delete(_:)` drops any pending edit whose original or correction was deleted. The fresh simulator run passed `deletingTheCorrectionKeepsTheOriginal`, `finishingAfterTheCorrectionIsDeletedElsewhereKeepsTheOriginal` and `deletingTheOriginalDropsTheEdit`. Editing the correction again exposes a separate recovery defect, recorded as F8 below.

### F2 — Medium: Serving-weight parsing can produce incorrect nutrition

**Roadmap:** C2 — Reliable serving weights and import normalization  
**Source:** [Shared/FoodPortion.swift:218](Shared/FoodPortion.swift#L218), [HealthLogger/Food.swift:147](HealthLogger/Food.swift#L147), and [HealthLogger/LabelScanner.swift:46](HealthLogger/LabelScanner.swift#L46)  
**Evidence:** Reproduced with read-only Swift probes against extracted production parsing/import code.

The parser accepts trailing numeric fragments rather than interpreting or rejecting the full weight expression:

| Serving text | Parsed weight |
| --- | --- |
| `2 x 30 g` | 30 g |
| `1/2 g` | 2 g |
| `.5 g` | 5 g |
| `20-30 g` | 30 g |

A barcode response with serving text `2 x 30 g`, a structured serving quantity of **60 g**, and **240 kcal per serving** imports **30 g per serving** because the parsed text takes precedence. Logging **30 g records 240 kcal instead of 120 kcal**. Label imports also adopt the parsed weight automatically.

This violates C2's requirement that ambiguous weights must not silently produce guessed nutrition.

**Suggested correction:** Parse complete supported expressions, reject ambiguous expressions, and reconcile conflicting textual and structured weights. Add coverage for multipliers, ranges, fractional grams, and leading-decimal grams.

**Validated — partially resolved:** The shared parser now handles the original direct fractional and leading-decimal inputs and rejects the original multiplier/range inputs. Barcode import checks agreement with the structured quantity; the original `2 x 30 g` / 60 g / 240 kcal product now safely imports without a serving weight. The new parser and barcode regression tests passed.

The complete label-import path still produces incorrect nutrition, and some unsupported expressions still yield a partial weight:

| Current input | Reproduced result | Required result |
| --- | --- | --- |
| Label: nutrition per 100 g, serving `1/2 g`, 400 kcal and 20 g protein | Serving weight 0.5 g, but 8 kcal and 0.4 g protein | 2 kcal and 0.1 g protein |
| Label: nutrition per 100 g, serving `.5 g`, 400 kcal | Serving becomes 5 g with 20 kcal | Serving 0.5 g with 2 kcal |
| Shared parser: `2 x (30 g)` or `30 g (x2)` | 30 g | Reject as ambiguous or interpret the complete expression |
| Shared parser: `1 / 2 g` | 2 g | 0.5 g or reject as unsupported |

**Remaining cause and evidence:** [NutritionLabel.amount at line 139](HealthLogger/NutritionLabel.swift#L139) still uses a separate regex that reads the denominator of `1/2 g` as 2 g for normalization, while [label application at line 49](HealthLogger/LabelScanner.swift#L49) assigns 0.5 g through the shared parser. [NutritionLabel.tidy at line 146](HealthLogger/NutritionLabel.swift#L146) strips the leading decimal point. The shared parser also accepts fragments of the expressions above. These results were reproduced by executing extracted production parsing and label-application code in a Swift probe; they are not OCR camera tests. Existing passing tests do not cover these full label cases.

**Still needed:** Use consistent complete-expression parsing for label normalization and serving metadata, preserve numeric punctuation, and reject unsupported ambiguous expressions throughout the import path.

**Fixed (October 3, 2026):** `ServingWeight` reads each amount only from where its number starts, so `1 / 2 g` is 0.5 g, and treats a multiplication sign anywhere in the text (an `x` or `×` that isn't part of a word, or `*` between numbers) as a multiple, so `2 x (30 g)`, `30 g (x2)` and `30 g (2x)` are ambiguous; `1 box (30 g)` and a footnote's `30 g*` still read as 30 g. It also reads milliliters the same way (`ServingWeight.milliliters`). The label path now scales per-100 nutrients with `ServingWeight` instead of its own regex, so the serving weight and the scaled nutrients always agree, and a serving that isn't one amount leaves the label per 100 g. `NutritionLabel.tidy` keeps the point of a leading decimal. New tests: the shared parser cases above, a volume reading, and full label imports of `1/2 g` (2 kcal and 0.1 g protein), `.5 g` (0.5 g, 2 kcal) and `2 x (15 g)` (stays per 100 g).

### F3 — Medium: Rescanning a label mixes different serving sizes

**Roadmap:** C2 — Label imports and a consistent nutrition/weight basis  
**Source:** [HealthLogger/LabelScanner.swift:43](HealthLogger/LabelScanner.swift#L43)  
**Evidence:** Reproduced with a read-only Swift probe of the label-application logic.

`FoodDraft.apply` replaces the serving text and weight but merges scanned nutrients into the existing dictionary. Nutrients absent from the new scan retain their old per-serving values.

For example, an existing food has **100 g / 400 kcal / 20 g protein / 10 g fat**. A replacement scan gives **50 g / 200 kcal / 10 g protein**, with fat missed by OCR. The result retains **10 g fat per 50 g**, doubling its per-gram value while the other nutrients use the new serving size.

This is an existing label-editing weakness that also affects C2's weight calculations.

**Suggested correction:** Clear missing values, consistently rescale them when justified, or explicitly require review when the serving basis changes. Do not silently retain values from the old basis.

**Validated — resolved:** `FoodDraft.apply` replaces all nutrients when the scanned serving differs from the current one (different text and not the same gram weight), so a missed nutrient is left empty. A rescan of the same serving still keeps amounts it missed. Both regression tests passed: `rescanningForADifferentServingClearsWhatItDoesntList` and `rescanningTheSameServingKeepsWhatItDoesntList`. An additional probe of the production application code confirmed that the original 100 g → 50 g example clears fat, while the same-serving control preserves omitted nutrients.

### F4 — Medium: Shortcuts can log a different food record than the selection displays

**Roadmap:** Optional 1 — Saved-food Siri/Shortcuts and ambiguity handling  
**Source:** [HealthLogger/FoodIntents.swift:60](HealthLogger/FoodIntents.swift#L60) and [query ordering/deduplication at line 101](HealthLogger/FoodIntents.swift#L101)  
**Evidence:** Reproduced with a read-only algorithm probe mirroring and checking the source's ordering and resolution logic; not an AppIntents runtime test.

Duplicate name/brand combinations are permitted. The query sorts favorites first and deduplicates records using their name/brand identity, but execution resolves that identity to the most recently logged record.

With two **Oats / Quaker** records—a favorite containing **200 kcal** and a more recently logged nonfavorite containing **100 kcal**—Shortcuts displays the 200-kcal option but saves 100 kcal. Duplicate recipe names also collapse to one selectable identity.

**Suggested correction:** Use identities that distinguish selectable records consistently, or explicitly resolve duplicates. Selection and execution must refer to the same record.

**Validated — partially resolved:** IDs now include creation time rounded to milliseconds, and lookup selects the same-name/brand record whose creation time is closest to that timestamp within one second. The duplicate-food, duplicate-recipe and timestamp-tolerance regression tests passed, including the original widely separated duplicate-record case. This does not guarantee that selection and execution identify the same record.

Two remaining cases were reproduced using extracted production identifier/matching code with record stubs:

1. Two same-name/brand records created at `t + 0.0004 s` (favorite, 200 kcal) and `t + 0.0001 s` (nonfavorite, 100 kcal), with `t` on a whole-second boundary, round to the same ID. Query ordering retains the favorite for display, but lookup chooses the nonfavorite because its timestamp is closer to the rounded value. The displayed 200-kcal selection logs 100 kcal.
2. A saved shortcut refers to a record created at `t`. If that record is deleted and a same-name/brand record created at `t + 0.5 s` remains, the old ID resolves to the remaining record rather than reporting that the selection is unavailable.

**Current source:** [identifier at line 55](HealthLogger/FoodIntents.swift#L55), [matching at line 63](HealthLogger/FoodIntents.swift#L63), and [query deduplication at line 130](HealthLogger/FoodIntents.swift#L130). These probes did not exercise the AppIntents runtime or real CloudKit sync. The duplicate-record test uses records an hour apart; the deletion test leaves no nearby duplicate, so neither catches these cases.

**Still needed:** Use a stable, immutable identifier for each record that syncs through iCloud, and do not substitute another record through fuzzy timestamp matching.

**Fixed (October 3, 2026):** `Food` and `Recipe` gained `uuid`, an optional `UUID` marked for iCloud encryption, set when a record is created. A record without one (saved before 1.1, or by an iPhone still on 1.0) is given one, and saved, the first time `SavedFoodQuery` fetches it. A Shortcuts entity's ID is that UUID, and resolution requires an exact match, so there is no timestamp matching. Food Shortcuts are new in 1.1, so no released shortcut uses the old IDs. The two new fields must join `Food.gramsPerServing` in the CloudKit production schema before a 1.1 build is distributed. If two iPhones give the same older record different IDs before either syncs, iCloud keeps one, and a shortcut made with the other reports the food as unavailable rather than logging another. New tests replace the millisecond-tolerance test: the reviewer's two same-millisecond records (the offered favorite is the one logged), a deleted record with a same-named one 0.5 s later (not found), and an older record gaining an ID that it keeps.

### F5 — Medium: “Log Last Meal Again” can log an incomplete meal

**Roadmap:** Optional 1 — Re-log the selected meal's most recent day within 30 days  
**Source:** [HealthLogger/FoodIntents.swift:209](HealthLogger/FoodIntents.swift#L209) and [HealthLogger/FoodViews.swift:319](HealthLogger/FoodViews.swift#L319)  
**Evidence:** Reproduced with a read-only algorithm probe of the query boundary and filtering; not a HealthKit runtime test.

The intent retrieves only the newest 500 food entries before filtering for the requested meal. This boundary can split a meal or hide it entirely within the promised 30-day window.

For example, 499 newer lunch entries followed by a two-food snack leave only one snack item available to re-log. With 500 newer entries, the intent incorrectly reports that there is no snack in the window.

**Suggested correction:** Query the requested meal and fetch its complete selected day, or paginate until the full relevant meal is available.

**Validated — original case resolved:** `Recents.lastMeal(_:in: HealthStore)` reads Health one day at a time within the lookback window, with no entry limit (`recentEntries` gained `before:` and an optional limit), and stops at the first day with that meal. The 500-entry cap no longer truncates or hides the selected meal. The fresh HealthKit simulator run passed `theLastMealIsWholeAfterManyNewerEntries`, covering a two-food snack followed by 500 newer lunch entries.

### F6 — Medium: Interrupted edits can lose their recovery controls

**Roadmap:** C3 — Relaunch reconciliation and visible recovery state  
**Source:** [Shared/HealthStore.swift:701](Shared/HealthStore.swift#L701), with the visibility filter at [line 643](Shared/HealthStore.swift#L643)  
**Evidence:** Source-traced failure sequence; not exercised in HealthKit during this review.

If the app terminates after saving the correction but before setting `replacementSaved`, relaunch finds the correction but does not update that marker. If cleanup then fails, the error is swallowed and the unfinished-edit section excludes the operation because `replacementSaved` remains false.

Both entries remain without the promised recovery controls while cleanup continues to fail. Existing tests cover interruption and deletion failure separately, but not this combination.

**Suggested correction:** Persist the discovered replacement state before retrying cleanup, and keep unresolved operations visible after a recovery failure.

**Validated — resolved:** Finishing an edit whose correction is found in Health records `replacementSaved = true` before trying the delete, so a failed cleanup on relaunch leaves the edit in History's unfinished-edit section, and it survives a further relaunch. The fresh HealthKit simulator run passed `anInterruptedEditWhoseCleanupFailsStaysListed`, covering the combined interruption and deletion failure, including visible and persisted recovery state.

### F7 — Low: Recents can retain stale serving-weight information

**Roadmap:** C2 — Older Recents acquiring the weight of an exactly matching saved food  
**Source:** [HealthLogger/FoodViews.swift:118](HealthLogger/FoodViews.swift#L118), with editor dismissal at [line 107](HealthLogger/FoodViews.swift#L107) and weight enrichment at [line 273](HealthLogger/FoodViews.swift#L273)  
**Evidence:** Source-traced state-refresh gap; not reproduced through the UI.

Recents are cached and reloaded when `health.changeCount` changes. Editing a saved food's serving weight only dismisses the editor; it does not trigger that reload. Immediately reopening an older recent entry can therefore still offer servings only, despite its saved counterpart now having a matching weight.

**Suggested correction:** Refresh or recompute enriched Recents when the saved-food basis changes, including changes arriving through iCloud.

**Validated — implementation source-verified:** Add Food keeps its raw Health entries and recomputes enriched Recents when the saved-food drafts change: [observer at line 122](HealthLogger/FoodViews.swift#L122), [recomputation at line 278](HealthLogger/FoodViews.swift#L278). The observed draft includes the relevant serving and nutrient fields, so source inspection supports the local-edit and incoming-query-update fix. There is no dedicated UI or two-device iCloud regression test. The successful build and general Add Food UI tests do not independently establish this refresh behavior at runtime.

### F8 — Medium: Editing an unresolved correction can leave a permanent duplicate

**Roadmap:** C3 — Edit logged food and shared edit recovery\
**Status:** Newly identified during fix validation; fixed afterwards (see below)\
**Source:** [replacement deletion at Shared/HealthStore.swift:677](Shared/HealthStore.swift#L677), [missing-correction handling at line 694](Shared/HealthStore.swift#L694), and [History editing at HealthLogger/HistoryView.swift:17](HealthLogger/HistoryView.swift#L17)\
**Evidence:** Reproduced for manual completion and automatic relaunch reconciliation using extracted production recovery methods with a mocked Health sample backend and persistence. This was not a HealthKit or UI runtime test.

1. Edit entry A (200 kcal) into B (400 kcal). Saving B succeeds, deletion of A fails, and the user chooses **Later**. A and B remain, with a pending A → B edit.
2. Open B from History and successfully edit it into C (600 kcal). This deletes B through the replacement path, but leaves the older pending A → B operation unchanged.
3. Finish the pending edit manually or let relaunch reconciliation finish it. B is missing, so the new missing-correction safeguard discards the pending operation while preserving A.

The result is A + C: **800 kcal instead of the intended 600 kcal**, with no pending edit and no recovery controls. The original F1 safeguard prevents data loss, but it does not follow a correction that has itself been replaced. Existing regression tests do not cover this chained-edit sequence.

**Suggested correction:** Track the successor correction when replacing an entry involved in a pending edit, or prevent further editing of that correction until the original cleanup is resolved. Cover both manual completion and relaunch recovery.

**Fixed (October 3, 2026):** before an edit saves anything, `HealthStore.settleEdits(involving:)` resolves any unfinished edit the entry belongs to, so a chain of edits never forms. Editing B, the correction of unfinished edit A → B, first finishes that edit (removing A); if A still can't be removed, `EditError.earlierEditUnfinished` is thrown and nothing changes, leaving A → B listed in History. Editing A, the original, while B is in Health throws `EditError.alreadyCorrected`; if B was never saved, the stale edit is dropped and A is edited normally. Since no pending edit can outlive its correction being replaced, manual completion and relaunch recovery need no changes. New HealthKit tests: the reviewer's sequence ends with only the 600 kcal entry, also after a relaunched store's recovery; editing B while A's removal fails again changes nothing and keeps the edit listed; editing A is refused.

## Feature coverage

| Roadmap scope | Review result |
| --- | --- |
| C1: Watch presets | Implemented; no additional definite defect found. Physical-device Crown validation remains open. |
| C2: Weighed foods and recipe ingredients | Implemented; F2 is fixed (not yet re-validated), F3 is resolved, and F7's fix is source-verified with dedicated UI/iCloud validation outstanding. Optional encrypted weight storage, legacy decoding, shared scaling, recipe snapshots and Health metadata are present. |
| C3: Logged-food editing and shared recovery | Implemented; the original F1 and F6 cases are resolved, and F8 is fixed (not yet re-validated). Food and non-food edits use the shared recovery path. |
| C4: Meal composition and correction | Shared add, replace, adjust, exclude and Save as Recipe workflows are implemented; no additional definite defect found. Real-photo device validation remains open. |
| C5: Restaurant and brand nutrition lookup for meal photos | Added to the 1.1 core and implemented after this review, so not reviewed here. The roadmap's 1.1 implementation status records its simulator validation and what remains. |
| Optional 1: Food Siri/Shortcuts | Implemented on iPhone; F4 is fixed (not yet re-validated) and the original F5 case is resolved. |
| Optional 2: Configurable nutrition widget | Still held; the existing widget remains fixed. |
| Optional 3: Onboarding | Implemented; no additional definite defect found. |
| Backlog | Standalone food search by name, Watch food re-logging, Watch today view, past-day food diary, goal adherence, entry notes and toothbrushing timer remain unimplemented, as planned. |
| 1.2 direction | Localization and iPad support remain unimplemented, as planned. |
| Held/excluded proposals | Remain outside the committed implementation scope. Their absence is not a 1.1 implementation defect. |

## Outstanding release requirements

These are separate from the implementation defects. The roadmap already records most of them as unfinished:

- Deploy `Food.gramsPerServing` to the CloudKit production schema, validate an iCloud round trip, and exercise mixed-version devices including build 25.
- Complete physical-device checks for off-step Watch Crown adjustment, edit recovery, meal-photo correction and Siri phrase recognition.
- Complete the Apple Health overlap checks and record device/build evidence. This review did not independently establish Apple's current device behavior.
- Complete hands-on VoiceOver validation and Health/notification permission-failure checks.
- Verify the affected App Store documentation, which is not stored in this repository.

The roadmap's separate Open Food Facts attribution/User-Agent cleanup was undone at review time: the request identified itself as `HealthLogger/1.0 (iOS)`, and the import screen lacked the planned licence link. This recorded an unmet roadmap task, not a new legal assessment.

**Source changes verified; deployment unverified:** The request now sends `Logalyst/<version> (support@logalyst.app)` ([HealthLogger/Food.swift](HealthLogger/Food.swift), `FoodDatabase.userAgent`), using the support address the privacy policy already publishes. The food editor's note on an imported food links to Open Food Facts and the Open Database License. [PRIVACY.md](PRIVACY.md) now lists the version and contact address among what is sent, and the [roadmap](ROADMAP.md) records the task as done. The website's privacy page is built from PRIVACY.md; deployment of the updated page was not independently verified. The API v2 → v3 decision remains open, as the roadmap says.

## Original review evidence

The initial review covered the roadmap through parallel reviews of C1/optional features, C2 and C3, plus meal composition and release requirements. A generic iOS Simulator `build-for-testing` succeeded for the iPhone app, Watch app, both widget extensions and both test targets. Swift probes reproduced the original F2–F5 cases; F1, F6 and F7 were source-traced. That initial review did not rerun the simulator suites. The subsequent fix validation below supplies fresh execution evidence and supersedes the earlier claim that all seven findings were fixed.

## Fix verification

Independent validation on October 3, 2026, used implementation commit `70e903e` and the iPhone 18 Pro simulator running iOS 27.0 (build `24A434`).

- Fresh `HealthLoggerTests`: **67 passed**, including the parser/import, Shortcuts, edit-recovery and last-meal regression tests. HealthKit tests used the simulator's Health store.
- Fresh `HealthLoggerUITests/FoodFlowUITests`: **8 passed, 1 expected skip, 0 failures**. The skipped `testComposeAMealWherePhotoOfMealIsUnavailable` applies to iOS 18–26. The passing flows exercise recovery UI, but do not cover F8 or establish F7's local/iCloud refresh behavior.
- Combined result: **75 passed, 1 skipped, 0 failures**, with `xcodebuild` exit status 0. Passing existing tests does not resolve the uncovered F2, F4 and F8 cases.
- Additional Swift probes executed extracted production parsing/application code for F2 and F3, identifier/matching code with record stubs for F4, and recovery methods with a mocked Health backend and persistence for F8. These reproduced the remaining F2/F4 defects, confirmed F3's original fix, and reproduced F8 through both manual and automatic recovery.
- Not rerun: the accessibility, onboarding and Watch-preset UI test classes. Physical-device checks, two-device iCloud behavior, CloudKit production deployment and website deployment remain unverified. F7 has no dedicated runtime regression test.
- Validation did not edit implementation files. This report update is the requested documentation change.

Command used for the successful fresh run, from `Logalyst-iOS`:

```sh
xcodebuild test -quiet -project HealthLogger.xcodeproj -scheme HealthLogger \
  -destination 'platform=iOS Simulator,id=9BFEEEB3-FD9C-4B38-A598-D6327ECF7587' \
  -derivedDataPath /private/tmp/logalyst-findings-validation-derived \
  -resultBundlePath /private/tmp/logalyst-findings-validation-signed-20261003.xcresult \
  -parallel-testing-enabled NO \
  -only-testing:HealthLoggerTests \
  -only-testing:HealthLoggerUITests/FoodFlowUITests \
  CODE_SIGN_IDENTITY=-
```

The result bundle is `/private/tmp/logalyst-findings-validation-signed-20261003.xcresult`; the captured log is `/private/tmp/logalyst-findings-validation-signed-20261003.log`. These are temporary local validation artifacts, not committed test fixtures.

### After the F2, F4 and F8 fixes

The fixes were tested on October 3, 2026 by their implementer, not independently, on the same simulator (iPhone 18 Pro, iOS 27.0, build `24A434`), on top of C5 commit `54435f4`:

- `HealthLoggerTests`: **148 passed, 0 failed** (209 runs with parameterized arguments), including every new F2, F4 and F8 test named in those findings' *Fixed* paragraphs. Result bundle: `/private/tmp/logalyst-fix-results.xcresult`.
- `HealthLoggerUITests/FoodFlowUITests`: **11 passed, 2 skipped, 1 failed**. The failure, `testReplaceAFoodWithAPublishedOne` (C5), is at line 373: a Chicken row is still listed after "sofritas" is typed into the Replace search. It fails the same way at `54435f4` without these fixes (checked in a separate worktree), so it predates them, and it's not one of F1–F8. It is open. Result bundle: `/private/tmp/logalyst-fix-ui.xcresult`.
- Not covered: the AppIntents runtime with Siri, two-device iCloud behavior for the new `uuid` fields (including two iPhones giving an older record an ID at once), the CloudKit schema deployment, and camera OCR of real labels.

### TestFlight 1.1 preparation: replacement-test diagnosis

The C5 replacement test's failure above was reproduced on the original iPhone 18 Pro simulator on October 3,
2026. A diagnostic assertion confirmed the search field contained `sofritas`; the accessibility hierarchy showed
the search sheet's empty results correctly, but also exposed an older `Chicken, 3:42 PM, 360 kcal` button in the
Nutrition screen behind the sheet. The test's app-wide `Chicken` query matched that logged entry. The same test
passed unchanged on the separate Logalyst 1.1 Validation simulator.

The published-food list now has the accessibility identifier `publishedFoodResults`, and the regression test
queries Chicken and Sofritas only inside that list. It also checks the entered query and waits for the filtered
row to disappear. This changes test targeting, not food matching or search behavior.

### TestFlight code-readiness review: published-nutrition validation

The subsequent targeted review included C5's website reader, table reader, model-value validation and matching,
plus meal-photo assembly, food identifiers and the release configuration. It found a correctness defect in
`ModelRowExtractor.isLabeled`: its model-value validation accepted `Sodium 0.3 g` as 0.3 mg, the 10 from
`Fat 10g Sodium 350mg` as sodium, and `Sugar < 1 g` as exactly 1 g. These were reproduced by executing the
extracted production `verified` method and its helpers with fixed source lines and model responses; the probe
did not depend on a live model generating the wrong answer.

The validation now checks printed units, rejects bounds, ranges and number fragments, and prevents a value
following one nutrient label from belonging to the next label. Unsupported units stay unknown, as they do in
the table reader; the validator does not guess conversions. Three regression tests cover those cases and valid
controls in `ModelRowCheckTests`. The probe now rejects each reproduced bad value and retains correctly labeled
350 mg sodium.

Final verification: `build/testflight-1.1-26/VerifiedTests.xcresult` records **153 passed, 0 failed** on iPhone 18 Pro /
iOS 27.0 (24A434): all 151 unit/HealthKit tests plus the branded-meal and published-food replacement UI tests.
The final Release archive, App Store Connect export and Apple's server validation succeeded; the artifact paths
and remaining manual CloudKit/device checks are recorded in `RELEASE-NOTES.md`.
