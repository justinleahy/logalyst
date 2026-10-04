# Release notes

Drafts of the App Store "What's New" text, newest first. Trim to fit when submitting.

## 1.1 — Unreleased additions after build 26

C6 (food portions by volume) and C7 (missing-nutrition indicators) are implemented in source. The latest signed
unit/HealthKit run on iOS 27.0 passed **201 tests in 28 suites**. The latest Release simulator build passed for the
iPhone and Watch apps and both widget targets. The confirmed UI results and remaining visual-audit findings are recorded
below. These additions are not part of the previously uploaded build 26, and no new archive, upload, website
publication or schema deployment is claimed here.

### Verified in the unit/HealthKit run

The passing cases cover volume conversions and compatible import bases; explicit zero versus omitted values;
recipe ingredient coverage; Health metadata, editing and re-logging; daily totals; and a pre-volume SwiftData
store migrated on local disk. This local migration test does not establish an iCloud round trip or mixed-version
sync.

### UI and visual verification — October 3–4, 2026

- **Passed on iOS 27.0:** incompatible replacement asks for a serving amount; 180 mL logging supports U.S.
  and Imperial conversion and retains zero versus unknown nutrition when re-logged through Health.
- **Passed on iOS 26.5:** existing no-weight food logging, and composed-meal regression with a 447 kcal total
  and Save as Recipe.
- **Partial-nutrition UI passed on iOS 26.5:** 100 mg sodium with two missing ingredients; all-unknown fiber;
  missing counts reduced from two to one to zero when excluding ingredients; and a saved recipe reopened with
  its original two missing ingredients. The recipe editor also retained the partial-total presentation.
- **Reviewed:** default-size volume/partial-nutrition screenshots; largest-text Nutrition, History and hydration
  layouts were changed to stack. On iOS 27.0, populated History rows and the full Imperial volume label were
  manually verified at the largest size, including 180 mL displayed as 6.34 Imperial fl oz. Manual iOS 26.5
  inspection confirmed no-data hydration, an unavailable goal and a dash in the ring.
- **Intermediate text size fixed:** standard XXXL reproduced a wrapped Imperial label after the initial
  default/largest checks. Amount and unit controls now stack above the default text size. Manual XXXL
  verification showed the full Imperial label, 6.34 fl oz amount and stepper clearly; the 201-test unit/HealthKit
  run and four-target Release simulator build passed again after this narrow change.
- **Save stability:** food and recipe editors now save to disk before dismissing. A failed save restores that
  editor's previous saved data and shows an error while leaving the editor open for another attempt.
- **Accessibility/relaunch scenario passed:** immediate termination and relaunch preserved the saved recipe,
  including its 100 mg partial total at the largest text size. Interaction, description, trait and hit-region
  assertions passed at default and largest sizes.
- **Visual-audit caveat:** the preceding system audit flagged volume Dynamic Type/clipping and near-threshold
  default-size contrast. The full system audit was not rerun after the intermediate-size fix; its raw findings
  remain recorded. Reviewed default/largest screenshots show full labels, values and partial/unavailable text.
  The passing scenario does not establish a blanket clean visual audit.

### What to test next

- **Measured liquids:** give a food a serving volume and log 180 mL against a 100 mL serving; each known
  nutrient should scale by 1.8. Switch between mL, U.S. fluid ounces and Imperial fluid ounces and check that
  the physical amount stays the same. Weight ounces are separate. Test barcode, label and published-source
  imports; missing or ambiguous volumes must stay serving-based until reviewed, without assuming a density.
- **Volume preservation:** log, edit and log a volume portion again; add it to a meal and save it in a recipe.
  Replacing it with a food without a compatible basis must ask for a serving amount. A finished recipe remains
  serving-based even when its ingredients have volumes.
- **Zero and unavailable nutrition:** save an explicit zero and leave another nutrient blank. Check both after
  editing and re-logging. Combine one ingredient with known sodium and two without it: the summary should show
  the known subtotal and two missing ingredients. Excluded and zero-portion ingredients should not count.
  A wholly unknown nutrient is unavailable, and a saved recipe must retain partial coverage.
  A food with no known nutrients cannot be logged directly. Add nutrition, leave it out, or save it with
  ingredients that have nutrition as a recipe; the recipe must preserve its missing-ingredient coverage.
- **Daily and compact views:** check Nutrition, widgets and spoken totals with no data, partial food data, and
  older or other-app records. Empty Health results do not prove zero intake or distinguish denied read access.
  Missing or partial data must not produce a completed-goal or under-limit success message.
- **Upgrade and mixed versions:** test local-only use and two iPhones sharing iCloud. Older app versions can
  drop volume or coverage metadata and may discard explicit zeros when rewriting records. Re-review affected
  portions and nutrients after those edits; the new version cannot recover information that was dropped.

### Remaining distribution gates

- `Food.millilitersPerServing` is an optional encrypted `Double`; the schema declaration is
  `CD_Food.CD_millilitersPerServing: ENCRYPTED DOUBLE`. The checked-in schema has been updated. Verify its import
  into Development and deployment to Production before distributing a build with these additions.
- Physical-device, iCloud round-trip, mixed-version and accessibility checks remain open. No current-device
  or iOS 27.2 beta Apple Health comparison was performed for C6/C7. The documentation check found no established
  equivalent of either complete workflow; it does not clear the hands-on release gate.

## 1.1 (26) — TestFlight

### What to Test

This beta adds food logging by weight, editing logged foods, building and correcting meals, restaurant
nutrition lookup for meal photos, preset buttons on Apple Watch, saved-food Shortcuts, and first-run setup.

- **Upgrade and sync:** update from 1.0 without deleting the app. Confirm your foods, recipes, favorites,
  presets and goals are still there. Edit a food's serving weight and check it on a second iPhone using the
  same iCloud account. Also test with iCloud unavailable. If one phone still runs 1.0, check both phones after
  editing a recipe there: the older version does not preserve ingredient weights.
- **Weighed food:** enter a serving weight, then log in grams and ounces. For a food with 200 kcal per 100 g,
  logging 35 g should save 70 kcal to Health. Check barcode and label imports, and existing foods whose serving
  text includes a weight. Volume-only servings should not acquire a guessed weight.
- **Corrections and meals:** edit a logged food's amount, meal and time; check History, Nutrition and Apple
  Health for one corrected entry and the expected totals. Build a meal, add or replace foods, leave an item out,
  and save it as a recipe. Check that old logged entries keep their original nutrition.
- **Meal photos:** on an iOS 27 iPhone with Apple Intelligence available, try real Chipotle photos and a second
  restaurant. Check published nutrition, serving sizes, double portions and source links. Resolve ambiguous
  foods and confirm hidden ingredients before logging. Try offline lookup and retry; estimates must remain
  labeled. Photo analysis is on-device; restaurant lookup sends the brand to Apple Maps and reads its website.
- **Watch and Shortcuts:** change presets on iPhone and use them on Watch, including 330 mL followed by a turn
  of the Digital Crown. Run saved-food and last-meal Shortcuts with Siri, including after renaming or deleting
  a food. Check Health access denied, large text and VoiceOver on the new screens.

Send feedback through TestFlight with your device, OS version, steps, expected result and actual result.

### Distribution prerequisites

- **Verified for the uploaded build 26:** the production schema for `iCloud.com.justinleahy.HealthLogger`
  included `Food.gramsPerServing`, `Food.uuid` and `Recipe.uuid`, all optional encrypted fields. After the owner
  deployed them, Production was exported and matched Development and the schema file as it existed then.
  The current `Config/CloudKit-1.1.ckdb` also declares serving volume, which that deployment did not include.
  TestFlight uses Production; deployment of the new field remains a separate gate above.
- Physical-device and two-device iCloud checks above remain beta test work; simulator results do not establish
  that they pass. See `ROADMAP.md` for the remaining public-release gates.

Build-26 schema preparation on October 3: exported Development and Production with `cktool`; both were
missing the three new fields. Validated and imported the then-current `Config/CloudKit-1.1.ckdb` into
**Development only**, then exported both environments again to verify exactly these additions and no change
to Production:

- `CD_Food.CD_gramsPerServing`: `ENCRYPTED DOUBLE`
- `CD_Food.CD_uuid`: `ENCRYPTED STRING`
- `CD_Recipe.CD_uuid`: `ENCRYPTED STRING`

All existing fields, indexes and permissions were preserved. The owner deployed these changes with
CloudKit Console's **Deploy Schema Changes**; a fresh export verified all three fields in Production.
Schema snapshots, including `production-deployed.ckdb`, are in `build/testflight-1.1-26/cloudkit/`.
The simulator's iCloud key-trust failure prevented automatic initialization;
`cktool` provided the schema-management path without changing the app or requiring device Developer Mode.

### Build verification — October 3, 2026

- Xcode 27.0 (27A266a): Release archive succeeded. The iPhone app, Watch app and both widget extensions are
  version 1.1, build 26; their signatures and matching dSYM UUIDs were verified. Debug test hooks are absent.
- Final simulator run: **153 passed, 0 failed** (151 unit/HealthKit tests, plus the branded-meal and published-food
  replacement UI tests), on iPhone 18 Pro / iOS 27.0 (24A434). The preparation run also passed four UI smoke tests
  for weighed logging, editing, meal composition and skipping onboarding.
- Code validation caught and fixed incorrect acceptance of published nutrition with mismatched units,
  neighboring nutrient values or bounds such as `< 1 g`. Three regression tests cover the fix. The replacement
  UI test now scopes results to its sheet instead of matching older logged foods behind it.
- App Store Connect export and Apple's validation both succeeded. The exported IPA has an Apple Distribution
  signature, production CloudKit/push entitlements and debugging disabled. Version **1.1 (26)** was uploaded
  successfully on October 3, 2026; Xcode reported `Upload succeeded` and `Uploaded package is processing`.
  Processing completed, and App Store Connect shows **1.1 (26) — Testing** in **Vitals Log Internal**
  (one existing tester). The group's automatic Xcode distribution assigned the build. The What to Test
  notes above were saved and verified after reloading the build page. No external testing groups exist;
  the build has not been submitted for external beta review. The 1.0 App Store submission remains
  Waiting for Review. Upload log: `build/testflight-1.1-26/upload.log`.
- Local artifacts: `build/testflight-1.1-26/Logalyst.xcarchive`, `build/testflight-1.1-26/export/HealthLogger.ipa`,
  `build/testflight-1.1-26/VerifiedTests.xcresult`, and `build/testflight-1.1-26/validation-verified.log`.
- IPA SHA-256: `abcf37f5f2f705fa7e3f2d2e1e18a6870a99bc94c0104ca6001d30e7238d4c8d`.
- Deployment of build 26's three schema fields was subsequently verified with a fresh `cktool` export. Physical-device testing,
  real meal photos, Siri and two-device iCloud synchronization remain unverified.

## 1.1 (draft)

Editorial note (not App Store copy): C5, restaurant and brand nutrition lookup, is implemented and was checked against real restaurant websites in a simulator, but not yet with a real meal photo or on a device (see `ROADMAP.md`). C6 and C7 are implemented with the simulator checks recorded above; visual-audit follow-up and the device/iCloud gates remain open. Recheck these bullets against validation before publishing.

- **Log food by weight.** Give a food its serving weight and log it in grams or ounces: 35 g of a food measured
  per 100 g logs exactly that. Barcode lookups and label scans fill in the weight when the serving is in grams.
- **Measure liquid food portions.** Give a food its serving volume and log in mL, U.S. fluid ounces or Imperial
  fluid ounces. Keep the measured amount when editing, logging again or adding it to a recipe.
- **See what's missing.** Keep known zeros separate from unavailable nutrition. Meals and recipes show partial
  nutrient totals and missing ingredients, while daily and compact totals identify incomplete data.
- **Fix logged food.** Tap a food in History or Nutrition to change how much you had, the meal, or the time. If an
  edit is interrupted, Logalyst finishes it next time instead of logging it twice.
- **Build a meal.** Start a meal from several of your foods with New Meal, and add a food you missed or swap one
  that's wrong on any meal screen, including a photo of a meal.
- **Restaurant nutrition for meal photos.** Add the restaurant or brand to a photo of your meal, like Chipotle,
  and Logalyst finds the nutrition it publishes on its website and uses it for each part of the meal, scaled to
  what you had, with a link to the source. Choose between foods that look alike, confirm ones hidden under the
  rest, and fall back to on-device estimates when a food isn't listed or you're offline.
- **Presets on Apple Watch.** Your preset amounts now appear as buttons when you log on the Watch.
- **Privacy policy update:** food entries in Health and saved foods now include an optional serving weight or
  volume, and food entries retain nutrition coverage. An edit in
  progress is noted on your iPhone until it finishes. When you look up a restaurant's or brand's nutrition, its
  name goes to Apple Maps to find its website, which Logalyst reads like a browser, blocking advertising and
  analytics services; your photo and what you ate stay on your iPhone. Looked-up foods keep their source.
