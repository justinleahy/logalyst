# Logalyst

An iPhone + Apple Watch app for manually logging health data that Apple Watch doesn't capture, written straight into Apple Health (HealthKit).

See the [roadmap](ROADMAP.md) for the 1.1 release plan and later candidates, and the
[security review](SECURITY-REVIEW.md) for the current threat-model findings and remediation checklist.

The first time it opens on an iPhone, Logalyst explains what it does and why it asks for Health access (asking
only then), and offers to star favorites, review goals and set up reminders; every step can be skipped.
iPhones that have used Logalyst before go straight to the app.

## What you can log

| Category | Metrics |
| --- | --- |
| Vitals | Blood pressure, blood glucose (with before/after meal), body temperature |
| Body | Weight, body fat %, lean body mass, waist circumference |
| Intake | Water, caffeine, alcoholic drinks, calories, protein, carbs, fat, saturated fat, sugar, fiber, cholesterol, sodium |
| Symptoms & events | 18 symptoms with severity (and optional duration), inhaler use, toothbrushing (duration), sexual activity (with protection used) |

- **Favorites:** swipe right on a metric (or touch and hold it on iPhone) to star it and pin it to the top of the
  Log list. Favorites sync between iPhone and Watch; if both change at once, the latest edit wins.
- Units follow your Health app preferences (e.g. lb vs kg, mg/dL vs mmol/L) unless you pick one in the
  **Options** tab, and you can switch per entry.
- Measurements like weight and blood pressure are prefilled with your last reading.
- **Presets:** tap a preset amount on an entry screen to fill it in. Type an amount and tap *Save as Preset* to add
  your own (up to 6 per unit, for any number metric), touch and hold one to remove it, or restore the defaults.
  Presets are kept per unit, so a 330 mL preset doesn't show when you enter fl oz. The Water widget's buttons use
  your first water presets, and they're edited on the iPhone and sent to the Watch, which shows them as buttons
  under the Digital Crown amount: tap one to fill it in, then turn the Crown or tap Save. The Watch shows the
  presets for the unit it enters in (your Health app preference, or your region), which may differ from a unit you
  picked in Options on the iPhone, since that choice isn't sent to the Watch.
- **Nutrition** tab tracks today's water against a daily goal (with a progress ring and a
  list of today's water to tap and fix or swipe away), shows calories, macros, sugar, fiber, cholesterol, sodium and caffeine against daily
  targets or limits, and charts any intake metric over the last 7 days. Totals include data other apps
  save to Health. An explicitly recorded zero is shown as zero; no recorded value is unavailable. Known
  omissions in logged foods make a total partial. Older and other-app records can leave coverage unknown,
  so a recorded total does not establish that the day's intake is complete. Tap the target button to edit goals.
- **Log reminders:** in **Options → Log Reminders**, add a reminder for any metric, such as water, blood pressure
  or weight. Each one comes at set times of day, or whenever you haven't logged the metric for a while (1 to 12
  hours) between the times you pick. They repeat every so many days, on chosen weekdays every so many weeks, or on
  chosen dates (or a weekday like the last Friday) every so many months. Logging the metric anywhere (the app,
  widgets, Siri, the Watch or other apps) skips a set-time reminder that's already been answered or pushes the next
  not-logged one back. Metrics with a daily target, like water, can stop for the day once it's reached, and their
  reminders show how much is left. Touch and hold a reminder to log a quick-log amount (your first preset, e.g. a
  glass of water) without opening the app, or tap it to open the metric. Reminders are scheduled on the iPhone
  ahead of time and show on the Watch while the iPhone is locked. Water reminders set up in earlier versions carry
  over.
- **Suggest Goals:** in the goals sheet, estimates water, calories, protein, carbs, fat, sugar and fiber from your weight,
  height, age and sex (read from Health when set, otherwise typed in), activity level, and whether you want to
  lose, maintain or gain weight. Calories burned at rest come from Apple Health's resting energy when there are at
  least 3 days of it in the last two weeks (the median day, so days the Watch was off for a while don't lower it;
  you can turn this off), otherwise from the Mifflin–St Jeor equation. Protein is 1.6 g/kg (1.2 g/kg to maintain),
  capped at 35% of calories. Fat is 30% and carbs are the rest. Sugar stays under 10% and fiber is 14 g per
  1,000 kcal. Losing weight takes off up to 500 kcal (never more than 20%, or below 1,200/1,500 kcal), and
  gaining adds 300 kcal. Water is the US National Academies' adequate intake from drinks (2.2 L for women, 3.0 L
  for men, 2.6 L otherwise; about 80% of total water, since food supplies the rest) plus 250 mL to 1 L for
  activity, and doesn't change with the weight goal. It only suggests goals for adults, and nothing changes until
  you tap *Use These Goals*. The caffeine, saturated fat, cholesterol and sodium limits aren't touched.
- **Foods:** save foods with their nutrition per serving (My Foods), then log them by the serving or, for a food
  with a serving weight, by weight in grams or ounces: 35 g of a food whose serving is 100 g logs 0.35 servings
  of each nutrient, and reads as "35 g". Add the serving weight in the food editor; barcode lookups and label
  scans fill it in when the serving is given in grams, and for a food saved before 1.1 whose serving size states
  a weight, like "1 bar (30 g)", the editor offers to use it. A serving given only as a volume (mL or fl oz) has
  no weight, since that would need the food's density, and nor does one whose weight isn't a single amount, like
  "2 x 30 g" or "20-30 g", or whose printed weight disagrees with Open Food Facts' own. Each one is saved to Health as a single food entry, so
  Health shows it by name and History lists it once. Each food is
  logged at a meal (breakfast, lunch, dinner or snack), which follows the time until you pick one, and the
  Nutrition tab lists today's food by meal. Scan a
  barcode to jump straight to a saved food, or to fill in a new one from
  [Open Food Facts](https://world.openfoodfacts.org), a free, open food database (its data is under the
  [Open Database License](https://opendatacommons.org/licenses/odbl/1-0/), which the editor links to). You can
  also type the number if the camera can't read it. Saved foods are kept on the iPhone and synced through iCloud (see below).
- **Food by volume:** add an explicit **Serving Volume** in the food editor, then log measured portions in mL,
  U.S. fluid ounces or Imperial fluid ounces. For a food defined per 100 mL, 180 mL logs 1.8 times each known
  nutrient. Changing the volume unit keeps the physical amount. U.S. and Imperial fluid ounces have different
  sizes and are separate from weight ounces. Barcode, label and published-nutrition imports retain a compatible,
  explicitly stated volume; ambiguous fluid ounces require review. Volume never supplies a guessed weight,
  a per-100-g column is never treated as per-100-mL, and a photo estimate never establishes a measured volume.
  Existing foods gain no automatic volume conversion; enter a volume or accept a stated volume after review.
- **Missing nutrition:** leave a field blank when its value is unavailable; enter **0** when zero is stated.
  Both survive saving, logging and editing. Meal and recipe summaries total the known values and show missing
  ingredient counts for each nutrient, excluding omitted and zero-portion ingredients. An entirely unknown
  nutrient is unavailable; a subtotal with missing ingredients is partial. Recipes preserve that coverage
  when logged as one food. *Estimate* and *Published* still describe the source, not completeness or accuracy.
  Daily totals, widgets and spoken summaries avoid calling missing or partial data a completed goal.
  A food needs at least one known nutrient (which can be zero) to log directly. If a meal contains an entirely
  unknown food, add nutrition, leave it out, or save the meal as a recipe alongside ingredients with known
  nutrition; the recipe keeps the unknown ingredient's missing-nutrition indicators.
- **Nutrition labels:** *Scan Nutrition Label* (in the Nutrition tab, or under ＋ in Add Food) photographs a
  nutrition facts panel, or reads a photo you choose, and fills in a new food from it: the serving size and each
  nutrient it lists. Tap *Scan Label* in the food editor to fill in a food you're already making, such as one
  whose barcode isn't in Open Food Facts. Scanning a label for a different serving size replaces all the food's
  nutrition, so an amount the scan misses is left empty rather than kept from the old serving. Text is read on the iPhone with Apple's Vision framework, and photos
  aren't kept. It reads US, Canadian and European labels. For European ones it uses the per-100-g or per-100-mL
  column, scaled only to a serving with the same physical basis, and works out sodium from salt. Check
  the amounts before saving, since print can be misread.
- **Logging food again:** *Add Food* starts with your recent meals (two or more foods at the same meal) and the
  foods you've logged in the last 30 days. Tap ⊕ to log one again now, as much as last time, or tap the row to
  change the servings, weight or volume, meal or time first (a meal lets you add, replace or leave out foods). Swipe
  right on a food in History or the Nutrition tab (or touch and hold it) to log it again, and swipe right on a
  saved food to make it a favorite, which keeps it at the top of My Foods. Recents come from Health, which also
  stores each entry's servings, serving size, weight or volume basis, selected unit, nutrition coverage, brand
  and meal, so they work even after the saved
  food is deleted. A food logged before it had a serving weight picks one up when logged again only if its saved
  food has the same name, brand, serving size and nutrition.
- **Meals:** *New Meal* (in the Nutrition tab, or under ＋ in Add Food) starts a meal from several saved foods
  without making a recipe first. On any meal screen (a new meal, a recent meal or a photo of a meal) you can add
  a food you missed, swipe left on one to replace it with one of your foods, change amounts by the serving,
  weight or volume, leave foods out, and save the meal as a recipe. A measured amount stays the same when the
  replacement has a compatible basis; otherwise confirm a serving amount. The totals and coverage shown are
  what's logged.
- **Editing logged food:** tap a food in History or the Nutrition tab to change its servings, weight or volume
  when the entry carries that basis, meal, or date and time. Its nutrition and coverage come from the entry
  itself, so editing or
  deleting the saved food doesn't change it, and editing it doesn't change the saved food or recipe.
- **Photo of Meal** (iOS 27 or later with Apple Intelligence on): take or choose a photo of a meal, optionally
  add details the photo can't show ("double chicken, no sour cream"), and Apple Intelligence's on-device model
  lists each food and drink with the amount shown and its estimated calories, macros, sugar, fiber and caffeine.
  Foods named like one of your saved foods or recipes use your nutrition instead (and a saved food's known
  serving weight or volume). Unknown estimates remain blank rather than becoming zero. Check and correct them
  on the meal screen (add or replace foods, change amounts, leave foods out, meal and time) before logging,
  or save them as a recipe. A photo from your library is logged at the time it was
  taken. Without a restaurant or brand nothing leaves the iPhone, and the button only appears where the model is
  available. Each food from a photo is marked *Estimate*, in the meal and once it's logged.
- **Restaurant and brand nutrition:** give a photo of a meal the restaurant or brand it's from, such as Chipotle,
  then tap *Look Up Nutrition*. The model reads the photo (and your details) on the iPhone, naming each part of the
  meal the way the brand portions it ("chicken", "white rice"). Logalyst then finds the brand's own published
  nutrition: Apple Maps gives its website (or, for a brand Maps doesn't list, the on-device model suggests one,
  used only if it's named for the brand and not another country's), and its nutrition pages are opened in a hidden
  web view that keeps no cookies and blocks advertising, analytics and session-recording services and other
  companies' images and frames. Links that lead to the nutrition, such as Chipotle's *Full Nutrition Facts* PDF,
  are followed, as are nutrition pages in the site's sitemap, preferring ones for your country. Nutrition tables
  are read directly (one food per row, columns named by the header, servings as text, grams or explicit volume);
  other text, such as a menu page, is read by the on-device model, keeping only values printed beside their nutrient's name that
  add up (calories against fat, carbohydrates and protein). Only the brand's name leaves the iPhone; the foods are
  looked for in what's read. A clear match uses the published values per serving, scaled in the app by the
  portions from the photo and details (double chicken is exactly twice each value), and is marked *Published per
  4 oz* (or whatever the serving is), with its source linked under *Sources* with its website and the date it was
  read. Nutrients a source doesn't publish stay unknown; published zeros stay zero. Serving weight and volume
  are kept only when the source explicitly supplies a compatible basis. A food that fits several published ones
  (rice: white or brown?) isn't counted until you *Choose*,
  and one the model thinks may be hidden under the others isn't counted unless you *Include* it. Foods the brand
  doesn't list fall back to the estimate, as does everything if the lookup fails (offline, the site doesn't
  answer), with *Try Again*; if nothing is found, the brand's nutrition pages are linked. A saved food with the
  same name never replaces a published match. Replacing or adding a food offers the brand's foods as well as
  yours, filtered as you type, with a search of what the brand publishes when you tap Search. Logged entries and
  recipes keep each food's published values and source, so later changes to the website don't change them. What's
  read is cached on the iPhone for 24 hours. Checked on October 3, 2026, Chipotle, Panera, Five Guys and Subway
  publish nutrition this can read; sites that build their nutrition only inside an interactive calculator (Taco
  Bell, Wendy's) or lay their PDF out in separate blocks (Qdoba) fall back to estimates with links.
- **Recipes:** in *Add Food*, tap ＋ and *New Recipe* to combine servings, weights or volumes of saved foods into a dish,
  and say how many servings it makes. It's logged by the serving like any food (e.g. "1/4 recipe"); its own
  weight or volume isn't worked out from its ingredients'. It's saved to Health as one food entry with the
  per-serving nutrition and ingredient coverage, so it shows in Recent and can be logged again. You can also
  save a meal as a recipe from its screen. Ingredients are copies, so editing or deleting a saved food later
  doesn't change recipes made with it.
- **iCloud:** saved foods, recipes and settings (units, goals, favorites, presets, log reminders and Suggest
  Goals answers) sync to the app's private database in the user's iCloud account, with every field end-to-end
  encrypted (CloudKit encrypted values), so they carry over to a new or second iPhone. The most recent edit to
  a setting wins. Without iCloud they stay on the device. Health data is synced by the Health app itself, and the
  Watch still gets its settings from the iPhone.
- **Older app versions:** an older app can drop volume or coverage metadata when rewriting a food, recipe or
  logged entry, and may discard explicit zeros. Missing metadata remains unknown and cannot be reconstructed
  from totals. Review serving bases and missing nutrients after edits on an older device; update both devices
  to retain the new information. Two-device and mixed-version iCloud behavior still needs physical-device validation.
- **History** tab lists everything logged from either device; swipe to delete, or tap an entry (food included) to
  fix it. Health can't change a saved entry, so editing saves the corrected one and then deletes the original.
  The edit is noted on the iPhone first, so it can be finished later without saving the correction twice: if the
  original can't be deleted, you can try again right away, or later from History (and the Nutrition tab), which
  lists the unfinished edit with *Remove Original* and *Keep Both*; if the app closes partway, the edit is
  finished the next time it opens, or listed there if it still can't be. Deleting either entry of an unfinished
  edit finishes it, and *Remove Original* keeps the original if the correction has since been deleted. Editing
  the correction of an unfinished edit removes its original first (or, if it still can't, leaves both as they
  are), and editing the original is refused until the edit is finished or both are kept, so a later edit never
  leaves an extra entry.
- **Widgets** (iPhone Home Screen, Lock Screen and Control Center):
  - *Water*: today's water against your goal, with buttons that log a glass without opening the app.
  - *Nutrition*: calories and nutrients against your daily goals. On the Lock Screen it shows a calorie gauge,
    or calories with protein, carbs and fat.
  - *Quick Log*: your favorites (or a few common metrics until you star some); tap one to open its entry screen.
  - *Metric*: pick any metric to see its latest reading, or today's total for intake.
  - *Log Water* and *Log Metric* controls for Control Center and the buttons at the bottom of the Lock Screen.
    Log Metric opens the entry screen for the metric you pick.
- **Siri and Shortcuts** (iPhone and Apple Watch):
  - *Log Water*: "Log water in Logalyst" logs a glass (your smallest water preset) in your unit. In Shortcuts you
    can set any amount and unit.
  - *Log Water Serving*: "Log 16 ounces of water in Logalyst" (or 8, 12, 20, 24 or 32 oz, 250, 330, 500 or
    750 mL, or a liter) logs it in one sentence. Siri phrases can't hold any number, only choices from a list.
  - *Log Metric*: "Log my weight in Logalyst" (or blood glucose, caffeine, or any other metric logged as a
    number that the device offers) asks for the value in your unit, then saves it. In Shortcuts you can set the
    value and unit, which makes automations like "log 95 mg of caffeine when I arrive at the coffee shop" possible.
  - *Log Food* (iPhone): "Log oatmeal in Logalyst" logs a serving of a saved food or recipe; Siri asks which one
    when a name fits several, like "yogurt". In Shortcuts you can set the servings and the meal (otherwise the usual
    one for the time). Each food and recipe has a permanent ID that iCloud syncs with it, so a shortcut works on
    your other iPhones and after a rename, two foods with the same name are offered (and logged) separately, and a
    deleted food is reported rather than replaced by another with its name.
  - *Log Last Meal Again* (iPhone): "Log my last breakfast again in Logalyst" logs the foods from your most recent
    breakfast (or lunch, dinner or snack) before today, in the last 30 days, at the same meal, now.
  - Every phrase has to include the app's name. Siri says what was saved and, for intake, today's total. Like
    the widgets, these ask you to unlock first. Siri learns your food names when you open the app and whenever
    foods or recipes change, including from iCloud.
- The app handles `healthlogger://log/<metric ID>` and `healthlogger://nutrition` links, which the widgets and
  controls use.
- **Complications** on Apple Watch: the Metric widget, showing a metric's latest reading or today's total.
  Tapping it opens that metric's entry screen. For water and caffeine it shows a ring toward your daily goal.
  Goals are set on the iPhone and reach the Watch the next time the Watch app opens.
- **Controls** on Apple Watch (watchOS 26 and later): *Log Water* logs a glass of water in your unit without
  opening the app, and *Log Metric* opens the entry screen for the metric you pick. Add them to Control Center.
- Widgets read Health directly. While the phone is locked, Health can't be read, so they show the last values
  they read (daily totals reset at midnight). Logging from a widget asks you to unlock first.
- Every sample is tagged `HKMetadataKeyWasUserEntered`, so Health shows it as manually entered.
- **Tip Jar:** in **Options → Tip Jar**, optional tips (consumable in-app purchases) support the app. They don't
  unlock anything.

## Running it

1. Open `HealthLogger.xcodeproj` in Xcode.
2. For **all four** targets (`HealthLogger`, `HealthLoggerWatch`, `HealthLoggerWidgets` and
   `HealthLoggerWatchWidgets`), open *Signing & Capabilities* and pick your Team.
   If Xcode says the bundle ID is taken, change the `com.justinleahy` prefix on every target (the Watch target's
   `WKCompanionAppBundleIdentifier` build setting must match the iPhone app's bundle ID, and each widget
   extension's ID must start with its app's ID). The apps and widgets share settings through the
   `group.com.justinleahy.HealthLogger` app group; if you rename it, update `AppGroup.id` in
   `Shared/AppGroup.swift` and the four entitlements files in `Config/`.
3. Select the `HealthLogger` scheme and your iPhone, then Run. The Watch app installs through the Watch app on
   your iPhone (or run the `HealthLoggerWatch` scheme directly on your watch).
4. Approve the Health permission sheet on first launch (on each device).
5. The Tip Jar loads its tips from `Config/TipJar.storekit` when run from Xcode, so they can be bought for free in
   testing. For TestFlight and the App Store, create consumable in-app purchases in App Store Connect with the
   product IDs in `TipJar.productIDs` (`HealthLogger/TipJar.swift`).
6. Restaurant and brand lookup needs no account or key: it uses Apple Maps and the brands' own websites. Its
   code is in `HealthLogger/BrandWebsite.swift` (finding and reading a brand's website) and
   `HealthLogger/NutritionLookup.swift` (caching and matching).

## Testing

### C6 and C7 implementation validation

Volume portions and missing-nutrition indicators are implemented in source after the uploaded 1.1 (26) build.
Implementation began October 3, 2026; final simulator checks span October 3–4.
The latest signed iOS 27.0 unit/HealthKit run passed **201 tests in 28 suites**. Coverage includes conversion
and import cases, zero versus unknown values, recipe coverage, Health metadata, editing and re-logging,
daily totals, and migration of a pre-volume SwiftData store on local disk. The Release simulator build also
passed for the iPhone and Watch apps and both widget targets.

- **UI checks passed:** on iOS 27.0, confirming a serving amount for an incompatible replacement, and logging
  180 mL with U.S./Imperial conversions while retaining zero/unknown nutrition through Health re-logging.
  On iOS 26.5, the existing no-weight food and composed-meal regression cases passed, including the 447 kcal
  meal total and Save as Recipe.
- **Partial-nutrition UI passed on iOS 26.5:** a 100 mg sodium subtotal shows two missing ingredients, all-unknown
  fiber is unavailable, exclusions reduce the sodium missing count from two to one to zero, and the saved
  recipe reopens with its original two missing ingredients.
- **Visual checks:** default-size volume and partial-nutrition screenshots were reviewed. Nutrition, History
  and hydration layouts now stack at the largest text size. Populated History rows and the full Imperial
  volume label were manually verified at that size on iOS 27.0; 180 mL displays as 6.34 Imperial fl oz.
  An iOS 26.5 manual check verified no-data hydration, its unavailable-goal wording and the dash in its ring.
  A later check reproduced an Imperial-label wrap at the intermediate standard XXXL size. Amount and unit
  controls now stack at sizes above the default, and manual XXXL verification confirmed the full label,
  amount and stepper remain readable. Unit/HealthKit tests and the Release build passed again after this fix.
- **Save stability:** food and recipe editors save to disk before closing. A failed save leaves the editor
  open with an error and restores the previous saved data, so the user can retry.
- **Accessibility/relaunch scenario passed:** the saved recipe survived immediate termination and relaunch,
  retaining its 100 mg partial total at the largest text size. Interaction, description, trait and hit-region
  assertions passed at default and largest text sizes.

Before the intermediate-size fix, the system's visual audit reported volume Dynamic Type/clipping findings
and near-threshold contrast at the default size. The full system visual audit was not rerun after that narrow
fix. Reviewed default/largest screenshots show full labels, values and partial/unavailable text; the passing
scenario is not a blanket clean visual-audit result, and the raw audit findings remain recorded.

Physical-device, iOS 27.2 Apple Health overlap, VoiceOver and two-device iCloud checks remain release gates.
The earlier uploaded build's tests and archive do not validate these additions.

The new optional encrypted `Food.millilitersPerServing` field is included in the checked-in CloudKit schema.
Its development import and production deployment must be verified before distributing a build with C6;
the previously deployed weight and UUID fields do not cover this new field. No deployment is implied by a
schema-file change.

### Preparing TestFlight 1.1

The project uses version **1.1**, build **26**, for the iPhone app, Watch app and both widget extensions.
The commands below produced the already uploaded build 26 before C6/C7. For another upload, first use a new
build number and artifact directory, complete the remaining checks, and verify the new volume field in the
production schema. The previous archive/export commands were:

```sh
xcodebuild -project HealthLogger.xcodeproj -scheme HealthLogger \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/testflight-1.1-26/Logalyst.xcarchive \
  -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath build/testflight-1.1-26/Logalyst.xcarchive \
  -exportOptionsPlist Config/TestFlight-ExportOptions.plist \
  -exportPath build/testflight-1.1-26/export -allowProvisioningUpdates
```

The tracked export options produce a local App Store Connect package with production iCloud entitlements and
preserve the configured build number. Keep each archive's dSYMs for crash reports. Before distributing C6/C7,
complete [their remaining distribution gates](RELEASE-NOTES.md#remaining-distribution-gates), including the new
volume schema field. [The build-26 TestFlight notes](RELEASE-NOTES.md#11-26--testflight) are a historical record;
their verified production fields do not include serving volume.

### Simulator tests

`HealthLoggerTests` (unit and HealthKit tests) and `HealthLoggerUITests` (UI tests and accessibility audits) run
from the `HealthLogger` scheme in a simulator: Product › Test, or

```
xcodebuild test -project HealthLogger.xcodeproj -scheme HealthLogger \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

They write to that simulator's Health store, so open the app there once and allow Health access first. Each
test logs foods under its own names. Debug builds take these launch arguments for testing:

- `-InjectEditFault save`, `delete` or `stop` makes the next edit fail at that step (`stop` quits the app right
  after the correction is saved), to check the recovery.
- `-SkipHealthAuthorization YES` doesn't ask for Health access, for UI tests on a simulator whose permission
  sheet they can't reach (the iOS 26 one).
- `-SeedScreenshotData YES` fills a fresh simulator for App Store screenshots, as before.
- `-StubMealPhoto YES` offers Photo of Meal on any simulator, with a *Use Test Photo* button, and finds the same
  foods in any photo (a Chipotle bowl when a brand is given), so the meal screen can be tested without
  Apple Intelligence.
- `-StubNutritionLookup ok`, `offline`, `slow`, `rateLimited`, `unavailable` or `empty` answers lookups with test
  data, or fails the given way, instead of reading brands' websites.

Tests that read real websites (`LiveBrandWebsiteTests`, and the UI test `testLiveBrandLookup`) are skipped unless
run with `TEST_RUNNER_LIVE_LOOKUP=1` in the environment; `TEST_RUNNER_LIVE_BRANDS="Panera Bread:broccoli cheddar
soup,Subway:turkey"` also tries other brands and prints what each gives.

`testComposeAMealWherePhotoOfMealIsUnavailable` is for an iOS 18–26 simulator, where Photo of Meal is hidden;
it's skipped on iOS 27.

## Adding a metric

Everything is driven by the catalog in `Shared/Metric.swift`. Add a `Metric` entry with its HealthKit
identifier and unit options (plus an optional `dailyGoal` for intake metrics), and it will appear in the log list, permission request and history on both devices.

## Layout

```
HealthLogger/        iPhone app (Log, Entry, Nutrition, History, Options screens)
HealthLoggerWatch/   Watch app (Favorites, Digital Crown entry)
HealthLoggerWidgets/ iPhone widget extension (Water, Nutrition, Quick Log)
HealthLoggerWatchWidgets/  Watch widget extension (complications)
HealthLoggerTests/   Unit and HealthKit tests (weights, imports, recipes, editing and its recovery)
HealthLoggerUITests/ UI tests of the food flows, Watch presets setup, and accessibility audits
AppShortcuts/        Siri phrases, compiled into the iPhone and Watch apps
Widgets/             Metric widget, Log Water and Log Metric controls, and widget helpers, compiled into both
                     widget extensions
Shared/              Metric catalog, HealthStore (HealthKit read/write), NutritionGoals, DeviceSync
                     (favorites and goals, Watch ↔ iPhone), app group settings, and the logging intents Siri, Shortcuts,
                     widget buttons and controls run, compiled into every target
Config/              Entitlements and the widget extensions' Info.plists
Website/             logalyst.app: the support and privacy pages (built from PRIVACY.md)
```
