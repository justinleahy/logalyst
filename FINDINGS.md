# Roadmap implementation review

Reviewed: October 3, 2026  
Scope: `ROADMAP.md`, the corresponding implementation, and existing tests  
Status: All seven implementation findings and the Open Food Facts attribution task fixed October 3, 2026; release validation remains incomplete

The 1.1 features are broadly implemented. The review itself did not change implementation files; the fixes were made afterwards and are recorded under each finding (**Fixed:**) and in [Fix verification](#fix-verification). The release requirements below still need devices, App Store Connect or the CloudKit console, so they remain open.

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

**Fixed:** `finishEdit` looks up the correction before deleting the original; if it's gone, the original is kept, the edit is dropped and `EditError.correctionMissing` is reported (the retry alert closes instead of offering Try Again). `delete(_:)` drops any pending edit whose original or correction was deleted. Tests: `deletingTheCorrectionKeepsTheOriginal`, `finishingAfterTheCorrectionIsDeletedElsewhereKeepsTheOriginal`, `deletingTheOriginalDropsTheEdit`.

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

**Fixed:** `ServingWeight.reading(of:)` reads each weight expression whole: fractions (`1/2 g` = 0.5 g, `1 1/2 g`) and leading decimals (`.5 g` = 0.5 g) are parsed, and multiples (`2 x 30 g`, `30 g x 2`, `2 biscuits x 15 g`), ranges (`20-30 g`, `20 to 30 g`) and zero are ambiguous, giving no weight. The barcode import uses the printed weight only when Open Food Facts' `serving_quantity` agrees (to 0.5 g or 1%), uses `serving_quantity` alone only when the text states no weight, and otherwise leaves the food servings-only. The finding's `2 x 30 g` / 60 g / 240 kcal product now imports with no weight. Tests: `multiplesAndRangesAreAmbiguous` (10 cases), new `readsAStatedGramWeight` cases, `aMultipleServingHasNoWeight`, `aPrintedWeightTheDatabaseDisagreesWithIsntUsed`, `aPrintedWeightTheDatabaseRoundsIsUsed`.

### F3 — Medium: Rescanning a label mixes different serving sizes

**Roadmap:** C2 — Label imports and a consistent nutrition/weight basis  
**Source:** [HealthLogger/LabelScanner.swift:43](HealthLogger/LabelScanner.swift#L43)  
**Evidence:** Reproduced with a read-only Swift probe of the label-application logic.

`FoodDraft.apply` replaces the serving text and weight but merges scanned nutrients into the existing dictionary. Nutrients absent from the new scan retain their old per-serving values.

For example, an existing food has **100 g / 400 kcal / 20 g protein / 10 g fat**. A replacement scan gives **50 g / 200 kcal / 10 g protein**, with fat missed by OCR. The result retains **10 g fat per 50 g**, doubling its per-gram value while the other nutrients use the new serving size.

This is an existing label-editing weakness that also affects C2's weight calculations.

**Suggested correction:** Clear missing values, consistently rescale them when justified, or explicitly require review when the serving basis changes. Do not silently retain values from the old basis.

**Fixed:** `FoodDraft.apply` replaces all nutrients when the scanned serving differs from the current one (different text and not the same gram weight), so a missed nutrient is left empty. A rescan of the same serving still keeps amounts it missed. Tests: `rescanningForADifferentServingClearsWhatItDoesntList` (the finding's 100 g → 50 g example), `rescanningTheSameServingKeepsWhatItDoesntList`.

### F4 — Medium: Shortcuts can log a different food record than the selection displays

**Roadmap:** Optional 1 — Saved-food Siri/Shortcuts and ambiguity handling  
**Source:** [HealthLogger/FoodIntents.swift:60](HealthLogger/FoodIntents.swift#L60) and [query ordering/deduplication at line 101](HealthLogger/FoodIntents.swift#L101)  
**Evidence:** Reproduced with a read-only algorithm probe mirroring and checking the source's ordering and resolution logic; not an AppIntents runtime test.

Duplicate name/brand combinations are permitted. The query sorts favorites first and deduplicates records using their name/brand identity, but execution resolves that identity to the most recently logged record.

With two **Oats / Quaker** records—a favorite containing **200 kcal** and a more recently logged nonfavorite containing **100 kcal**—Shortcuts displays the 200-kcal option but saves 100 kcal. Duplicate recipe names also collapse to one selectable identity.

**Suggested correction:** Use identities that distinguish selectable records consistently, or explicitly resolve duplicates. Selection and execution must refer to the same record.

**Fixed:** Entity IDs now add the record's creation time (in milliseconds; it syncs through iCloud) to the name and brand, so duplicate foods and duplicate recipes are each offered. `entities(for:)` and `perform()` resolve an ID through the same lookup and ordering: same name and brand, creation time closest and within a second (allowing for iCloud storing it less precisely). A renamed or deleted record still resolves to nothing. These intents were added after build 25, so no shipped shortcut used the old IDs. Tests: `duplicateFoodsAreEachOfferedAndLoggedAsThemselves` (the finding's two Oats / Quaker records), `duplicateRecipesAreEachOffered`, `anIDAMillisecondOffStillFindsItsFood`.

### F5 — Medium: “Log Last Meal Again” can log an incomplete meal

**Roadmap:** Optional 1 — Re-log the selected meal's most recent day within 30 days  
**Source:** [HealthLogger/FoodIntents.swift:209](HealthLogger/FoodIntents.swift#L209) and [HealthLogger/FoodViews.swift:319](HealthLogger/FoodViews.swift#L319)  
**Evidence:** Reproduced with a read-only algorithm probe of the query boundary and filtering; not a HealthKit runtime test.

The intent retrieves only the newest 500 food entries before filtering for the requested meal. This boundary can split a meal or hide it entirely within the promised 30-day window.

For example, 499 newer lunch entries followed by a two-food snack leave only one snack item available to re-log. With 500 newer entries, the intent incorrectly reports that there is no snack in the window.

**Suggested correction:** Query the requested meal and fetch its complete selected day, or paginate until the full relevant meal is available.

**Fixed:** `Recents.lastMeal(_:in: HealthStore)` reads Health one day at a time, from yesterday back to 30 days, with no entry limit (`recentEntries` gained `before:` and an optional limit), and stops at the first day with that meal, so the meal is always complete. Test: `theLastMealIsWholeAfterManyNewerEntries` (a two-food snack followed by 500 newer lunch entries).

### F6 — Medium: Interrupted edits can lose their recovery controls

**Roadmap:** C3 — Relaunch reconciliation and visible recovery state  
**Source:** [Shared/HealthStore.swift:701](Shared/HealthStore.swift#L701), with the visibility filter at [line 643](Shared/HealthStore.swift#L643)  
**Evidence:** Source-traced failure sequence; not exercised in HealthKit during this review.

If the app terminates after saving the correction but before setting `replacementSaved`, relaunch finds the correction but does not update that marker. If cleanup then fails, the error is swallowed and the unfinished-edit section excludes the operation because `replacementSaved` remains false.

Both entries remain without the promised recovery controls while cleanup continues to fail. Existing tests cover interruption and deletion failure separately, but not this combination.

**Suggested correction:** Persist the discovered replacement state before retrying cleanup, and keep unresolved operations visible after a recovery failure.

**Fixed:** Finishing an edit whose correction is found in Health records `replacementSaved = true` before trying the delete, so a failed cleanup on relaunch leaves the edit in History's unfinished-edit section, and it survives a further relaunch. Test: `anInterruptedEditWhoseCleanupFailsStaysListed` (interruption plus delete failure combined).

### F7 — Low: Recents can retain stale serving-weight information

**Roadmap:** C2 — Older Recents acquiring the weight of an exactly matching saved food  
**Source:** [HealthLogger/FoodViews.swift:118](HealthLogger/FoodViews.swift#L118), with editor dismissal at [line 107](HealthLogger/FoodViews.swift#L107) and weight enrichment at [line 273](HealthLogger/FoodViews.swift#L273)  
**Evidence:** Source-traced state-refresh gap; not reproduced through the UI.

Recents are cached and reloaded when `health.changeCount` changes. Editing a saved food's serving weight only dismisses the editor; it does not trigger that reload. Immediately reopening an older recent entry can therefore still offer servings only, despite its saved counterpart now having a matching weight.

**Suggested correction:** Refresh or recompute enriched Recents when the saved-food basis changes, including changes arriving through iCloud.

**Fixed:** Add Food keeps the Health entries it loaded and works out recents from them again whenever any saved food's fields change (`onChange` of the saved foods' drafts, which `@Query` updates for local edits and iCloud changes alike), without reading Health again. Not covered by an automated test; verified by build and by the existing Add Food UI flows passing.

## Feature coverage

| Roadmap scope | Review result |
| --- | --- |
| C1: Watch presets | Implemented; no additional definite defect found. Physical-device Crown validation remains open. |
| C2: Weighed foods and recipe ingredients | Implemented; F2, F3 and F7 fixed. Optional encrypted weight storage, legacy decoding, shared scaling, recipe snapshots and Health metadata are present. |
| C3: Logged-food editing and shared recovery | Implemented; F1 and F6 fixed. Food and non-food edits use the shared recovery path. |
| C4: Meal composition and correction | Shared add, replace, adjust, exclude and Save as Recipe workflows are implemented; no additional definite defect found. Real-photo device validation remains open. |
| Optional 1: Food Siri/Shortcuts | Implemented on iPhone; F4 and F5 fixed. |
| Optional 2: Configurable nutrition widget | Still held; the existing widget remains fixed. |
| Optional 3: Onboarding | Implemented; no additional definite defect found. |
| Backlog | Online food search, Watch food re-logging, Watch today view, past-day food diary, goal adherence, entry notes and toothbrushing timer remain unimplemented, as planned. |
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

**Fixed:** the request now sends `Logalyst/<version> (support@logalyst.app)` ([HealthLogger/Food.swift](HealthLogger/Food.swift), `FoodDatabase.userAgent`), using the support address the privacy policy already publishes. The food editor's note on an imported food links to Open Food Facts and the Open Database License. [PRIVACY.md](PRIVACY.md) now lists the version and contact address among what is sent, and the [roadmap](ROADMAP.md) records the task as done. The website's privacy page is built from PRIVACY.md and has **not** been redeployed. The API v2 → v3 decision remains open, as the roadmap says.

## Verification and limits

- Reviewed implementation and existing tests against the roadmap, using parallel reviews of C1/optional features, C2, and C3, plus review of meal composition and release requirements.
- Ran `xcodebuild build-for-testing` for the `HealthLogger` scheme with a generic iOS Simulator destination, signing disabled, and build output under `/private/tmp`. The result was **TEST BUILD SUCCEEDED**, covering the iPhone app, Watch app, both widget extensions, and both test targets.
- Read-only Swift probes reproduced F2 and F3. Read-only algorithm probes reproduced F4 and F5; these were not executions of AppIntents or HealthKit.
- F1, F6 and F7 are source-traced findings, with their runtime verification limits stated above.
- The full simulator UI and HealthKit suites were **not rerun**. The roadmap's earlier successful test runs were not treated as fresh execution evidence.
- Existing tests do not cover the failure combinations and edge cases described in these findings.
- Git status was clean at the end of the review. Creating this report is a subsequent, explicitly requested documentation change.

## Fix verification

- `xcodebuild build-for-testing` for the `HealthLogger` scheme (generic iOS Simulator): **TEST BUILD SUCCEEDED**, covering the iPhone app, Watch app, both widget extensions and both test targets.
- `HealthLoggerTests` on the iPhone 18 Pro simulator (iOS 27.0, Health access allowed): **67 tests in 10 suites passed**, including every test named above. The HealthKit tests ran against the simulator's Health store.
- `HealthLoggerUITests/FoodFlowUITests` on the same simulator: **8 passed, 1 skipped** (`testComposeAMealWherePhotoOfMealIsUnavailable`, which is for iOS 18–26), 0 failures. These cover the edit-recovery alert and History's Remove Original paths changed by F1 and F6.
- The parser was also checked separately against the finding's inputs and 40 further serving texts.
- Not rerun: the other UI test classes (accessibility, onboarding, Watch presets), which these fixes don't touch.
- F7 has no automated test. F4's iCloud tolerance is covered by a unit test, not by a real two-device sync.
