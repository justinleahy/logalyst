# Logalyst Roadmap

Updated: October 3, 2026 · Baseline: 1.0, build 25

Status: Release plan. Its statements about the current app were checked against the build 25 source, and the external pages it relies on were opened, on October 3, 2026. Sizes are untested estimates, and Apple Health overlap checks are provisional (see [Evidence](#evidence-and-sources)). The 1.1 core and optional additions 1 and 3 have since been implemented and validated in simulators; device checks and release steps remain (see [1.1 implementation status](#11-implementation-status)).

This roadmap is for the people planning, implementing, and validating Logalyst's next releases. Use it to choose the next feature, understand its dependencies, and determine when it is ready to ship.

## Release direction

**1.1 focuses on faster, more accurate food logging and correction, plus Watch preset buttons.** Its core is weighed portions, editing logged food, the missing meal-composition workflows, and Watch presets. Online food search, the largest candidate, sits outside the 1.1 commitment; it cannot be scheduled until its data access and privacy approach are resolved.

**Standing rule:** Logalyst does not build anything Apple Health already has or Apple has announced. Check each overlap question against the current iOS release or beta (the iOS 27.2 beta as of October 3, 2026) before building the feature, and recheck before release. Compare the complete interaction, not just whether Health stores the same metric: an equivalent Apple workflow removes the feature, and an unresolved question keeps it held, or flagged as a validation item, until it is checked. A feature can also be deferred for product focus without claiming Apple offers an exact equivalent.

Sizes below are relative planning estimates, not delivery dates: Small is a contained change; Medium spans several flows or needs recovery/synchronization work; Large introduces substantial data or service dependencies. The core takes precedence: optional scope is added only under the rule in "Optional additions to 1.1" and must not delay the core.

Four sizes need explanation. Editing logged food is Medium rather than Small, because a Health entry cannot be changed in place and the save-then-delete replacement needs recovery work. Notes on entries is Small–Medium rather than Small, because its storage and synchronization are undefined. C4 is Medium although its two meal-screen gaps are small in themselves, because it covers every path into the meal screen and C2's weighed portions. Goal adherence is unsized until its gate is settled.

## 1.1 implementation status

Implemented on October 3, 2026, on top of build 25, and validated in simulators only (devices and builds under [Simulator validation](#simulator-validation-october-3-2026)). Nothing here has been on a physical iPhone or Apple Watch, and the Apple Health checks of the build sequence's first step are still open. Decisions this needed are recorded under [Open decisions](#open-decisions-and-checks) and are the implementer's, for the owner to confirm.

| Item | State | Validated in simulators | Still open before release |
| --- | --- | --- | --- |
| C1 Watch preset buttons | Implemented | Paired iPhone and Apple Watch SE 3 (40 mm): six mL presets edited on the iPhone reached the Watch, smallest first, fitting with the amount and Save; a unit whose presets were all removed shows none; the iPhone's fl oz presets stay off the Watch, which enters in mL; tapping a preset fills the amount without saving; Save logs it. | How an off-step amount (330 mL) behaves when the Crown is turned, on a device. |
| C2 Weighed food | Implemented | Unit tests of weight parsing, the 35 g and ounce cases, imports (Open Food Facts responses for a drink, a gram serving and per-100 g and per-100 mL products; US and European labels), build 25 recipe data, and weighed recipe totals. HealthKit tests of weight metadata, and of a build 25 entry staying by the serving. Upgrade in place from build 25: the store gained the column and kept every food and recipe, with the iCloud-configured container. UI tests of logging by weight. | Deploy `Food.gramsPerServing` (an optional `Double`) to the CloudKit production schema; an iCloud round trip; a second iPhone on build 25 (its recipe edits drop ingredient weights but keep nutrition). |
| C3 Edit logged food | Implemented, with the same recovery for every entry type | HealthKit tests with injected save and delete failures, retry, Keep Both, and edits cut short before and after the save, reconciled by a new store as on relaunch. UI tests of editing, both failures, and a real app exit after the save, finished on relaunch. | On a device. |
| C4 Meals | Implemented | UI tests of New Meal, adding, replacing, weighing in ounces, leaving out, the total, and Save as Recipe, on iOS 27 and on iOS 26.5, where Photo of Meal is hidden. | Photo-of-meal correction with a real photo on an Apple Intelligence device. |
| Optional 1: Siri and Shortcuts for saved foods | Implemented, iPhone only | Tests of finding foods by name (several for an ambiguous one, none once deleted), logging, the error for a deleted food, and re-logging the last meal. The iPhone app registers the two new App Shortcuts; the Watch app doesn't. | Siri recognizing the phrases, on a device; the Apple overlap recheck. |
| Optional 2: Customizable nutrition widget | Held | — | Its entry gate: a configurable multi-nutrient Health widget, checked on the iOS 27.2 beta. |
| Optional 3: Onboarding | Implemented | UI tests: the walkthrough (with accessibility audits), Skip, a new simulator seeing it, and an upgraded one not. | — |

Accessibility audits of the new and changed screens pass at the default and largest text sizes for descriptions, hit areas and traits. Their contrast and Dynamic Type findings are the system's own styles (secondary footers, the tint, disabled bar buttons), and the largest-size screenshots were checked by eye; two layouts were fixed for it. A hands-on VoiceOver pass is still to do.

How it's tested: `HealthLoggerTests` (unit and HealthKit) and `HealthLoggerUITests` (UI and accessibility) in the HealthLogger scheme; the README's Testing section lists the Debug launch arguments for injected failures. Documentation was updated: the README, the website support and home pages, `PRIVACY.md` (with a new effective date), and draft release notes in `RELEASE-NOTES.md`. The App Store listing isn't kept in this repository.

## 1.1 core

| ID | Feature | Size | Main dependency |
| --- | --- | --- | --- |
| C1 | Watch preset buttons | Small | Existing preset synchronization; a decision on whether to sync the iPhone's unit choice |
| C2 | Log food and recipe ingredients by weight | Medium–Large | Numeric serving-weight model and migration |
| C3 | Edit logged food | Medium | Recoverable Health replacement and deletion; C2 for weighed edits |
| C4 | Compose meals and correct meal-photo items | Medium | Existing meal screen and recipe ingredient picker; C2 for weighed portions |

**Apple Health check status, October 3, 2026.** C1 has a hands-on check: Apple Health's Quick Log has no presets and no widget (see Evidence). C3 was checked against Apple's September 2026 announcement, Apple's documentation, and coverage of the iOS 27.2 beta. C2 and C4 were checked against Apple's documentation only. No equivalent was found for any of the three, and none has a hands-on check yet; that check is the first step of the build sequence.

### C1. Watch preset buttons

- Show each metric's presets on the Watch's numeric (Digital Crown) entry screen. The Watch already holds them: lists edited on iPhone arrive through the existing sync, and unedited units use the built-in lists compiled into both apps. Until the user saves their own on iPhone, only Water, Caffeine, Alcoholic Drinks, and Inhaler Use have presets. A unit can hold up to six, so the layout must fit six alongside the amount and Save.
- Tapping a preset fills the amount; retain Digital Crown adjustment and the existing Save action. Check on a device how an amount off the Crown's step (a custom 330 mL, for example) behaves when the Crown is turned afterwards.
- Show the list for the unit the Watch enters in. The Watch has no unit picker and does not receive the iPhone's Options → Units choice, so it uses the Health-preference or regional unit, and presets saved on iPhone under a different unit will not appear on the Watch. Decide before starting whether to accept and document this or to add the iPhone's unit choices to the iPhone-to-Watch sync; recheck the Small estimate if the sync is extended.
- Keep the stored order (always smallest first; there is no custom ordering), use the built-in list for a unit the user has not edited, and show no buttons where the user removed every preset. Preset management stays on iPhone.
- Decided: the Watch shows the presets of the unit it enters in, and the iPhone's unit choice is not synced (Open decisions 2). The README and support page say so.

**Ready when:** the Watch shows the presets for the unit it enters in, smallest first; a unit the user has not edited shows the built-in list, and a unit whose presets were all removed shows none; an iPhone preset change reaches the Watch by the next time the Watch app opens; presets never cross units; selecting a preset fills the amount without saving; and the existing in-flight Save guard (already on iPhone and Watch in build 25) still prevents a repeated Save tap from logging twice. C1 has no dependency on the food work. Whether it is released ahead of the rest of 1.1 is an open decision; until that is decided, it ships with 1.1 under the release gate.

### C2. Log food and recipe ingredients by weight

- Add an optional numeric serving weight in grams to saved foods and food portions, while retaining the human-readable serving description. Serving size is free text in both today, so food can be logged only in servings.
- Accept grams or ounces when a reliable serving weight exists; calculate nutrition from the equivalent number of servings. Keep serving-based entry available when weight is unknown.
- Carry weight information through the saved-food editor, barcode imports, label scanning, recipe ingredient snapshots, recent-food and recent-meal re-logging (including the Log Again actions in Add Food, History, and Nutrition), logged-food metadata, and the portion summaries shown in Recents, the meal screen, and the recipe editor, so a weighed entry reads as "35 g" rather than "0.35 × 100 g". Meal-photo estimates carry no weight and stay servings-only unless an item matches a saved food, which then brings its weight along. Widgets, Siri/Shortcuts, and the Watch app do not read the serving model today and need no change.
- Support weighed recipe ingredients. Do not infer a finished recipe's weight from ingredient weights. The recipe model has no weight today (a recipe is logged as a fraction such as "1/4 recipe"), so finished recipes stay logged by the serving in 1.1. Logging a finished recipe by weight would need its own per-serving weight on the recipe and is not part of C2 unless added here explicitly.
- Extend the three places serving data is stored today, without losing foods or recipes:
  - **Saved foods** are SwiftData models mirrored to the user's private iCloud (CloudKit) database, with no versioned schema or migration plan. The weight must be an optional or defaulted attribute, as iCloud syncing requires of every field, and marked for iCloud encryption like the existing fields, so the privacy policy's statement that every field is end-to-end encrypted stays true.
  - **Recipe ingredients** are stored inside each recipe as a JSON-encoded list of food portions that loads as an empty list if decoding fails. Make the weight an optional key, or decode it with a fallback; a required key would make every existing recipe load with no ingredients and no error.
  - **Logged entries** keep servings, serving text, brand, and meal as metadata on the Health food entry. Add a weight metadata key for new entries; entries already in Health cannot be rewritten.
- Older records and logged entries without weight metadata must remain readable and usable by servings.
- Decide how foods saved before 1.1 get a weight. Their serving is text only, including the "100 g" the barcode lookup writes when a product lists no serving, so the 35 g case will not work for an already-saved food until it has one. Options: enter it in the food editor, or offer a weight parsed from an unambiguous gram amount in the existing text (the label scanner already parses text like "1 bar (30 g)"). Never back-fill a weight the text does not state. Recents re-log the portion read back from Health rather than the saved food, so also decide whether an entry logged before 1.1 picks up the weight of a saved food with the same name and brand or stays servings-only.
- Both import paths already reduce nutrients to one serving; what C2 adds is the numeric weight. The barcode lookup prefers Open Food Facts' per-serving values and otherwise uses its per-100 values with the serving text "100 g". The label scanner scales a per-100 g or per-100 mL column to the printed serving when the units match, and otherwise calls the serving "100 g" or "100 mL". One existing behavior must change: the barcode fallback writes "100 g" even though Open Food Facts defines its per-100 values as per 100 g or 100 mL, so a drink with no listed serving must not gain a 100 g weight. The lookup reads only the serving text today, so a per-serving product's weight has to come from that text or from additional database fields.
- Do not treat milliliters or fluid ounces as mass without a known conversion. Foods defined by volume stay servings-only unless volume entry is scoped separately.

**Ready when:** a 35 g portion of a food defined per 100 g logs 0.35 times each nutrient; the same portion entered in ounces logs the same nutrients to displayed precision; foods created by barcode import and by label scanning can be logged by weight when the source states a gram serving weight; a serving stated only in milliliters or fluid ounces, with no known conversion, offers servings entry only; recipes created before the upgrade show unchanged per-serving nutrition, and a recipe with weighed ingredients totals its ingredients' scaled nutrients; and existing foods and recipes survive the upgrade from build 25, an iCloud round trip, and local-only use, with entries lacking weight metadata still loggable by servings. Ambiguous or missing weights must not silently produce guessed nutrition.

### C3. Edit logged food

- Open a food logged by Logalyst from History or Nutrition and change servings, meal, or date and time. Support weight entry when the entry carries C2's weight metadata. History lists only the 200 most recent entries of any kind and Nutrition lists only today's foods, so older foods stay out of reach until the food diary (a later candidate) adds past-day navigation.
- Recalculate nutrients from the logged entry itself, which is its snapshot: the entry's nutrient samples hold the totals and its metadata holds the servings, serving text, brand, and meal, so per-serving nutrition is the totals divided by the servings (entries from before servings were recorded count as one serving). Nothing links a logged entry to a saved food except a matching name and brand, so editing or deleting the saved-library counterpart does not change the entry's basis. No new snapshot storage is needed for serving-based edits; weighed edits need the weight metadata C2 adds.
- Replace the Health food entry and its nutrient samples, then remove the original entry and its samples. Treat this as a multi-step operation that can partially fail.
- Editing already works this way for every non-food entry: the entry screen saves the corrected entry, then deletes the original, and if the delete fails it tells the user both are in History and to swipe away the one they do not want. It has no retry and keeps nothing across a relaunch. Matching that flow for foods is the smaller part of C3; the recovery below goes beyond what ships today and is why C3 is Medium. Decide whether the stronger recovery also replaces the non-food behavior or applies to foods only, so the two edit paths do not diverge by accident.
- Preserve the original if saving the replacement fails. If replacement succeeds but cleanup fails, show the incomplete state and provide a recovery path that retries cleanup without saving another replacement.
- Retain enough operation state to reconcile an interrupted edit after relaunch. Today's Health helpers do not provide this: the food save returns nothing and builds its Health entry privately, delete needs an entry already loaded from Health, entries can be re-read only through the recent-entries query (there is no lookup by identifier), and no edit state is stored anywhere. C3 includes extending them so the pending original/replacement pair is recorded before the save and found again after a relaunch.
- Refresh affected days, recents, totals, and widgets after completion or recovery. The Health store's existing save and delete paths already trigger this (they reload Nutrition, History, and Recents, reload widget timelines, and reschedule log reminders), so route edits and recovery through them rather than adding a separate refresh mechanism.

**Ready when:** successful edits leave one corrected food entry and the expected nutrient totals; an injected save failure leaves the original entry unchanged; an injected delete failure shows the incomplete state, and a retry removes only the original without saving another replacement; an edit interrupted by app termination is reconciled after relaunch; affected days, recents, totals, and widgets refresh after completion or recovery; and when the entry carries C2 weight metadata, changing the weight recalculates nutrients, while entries without it remain editable by servings. Do not claim duplicate entries are impossible during a partial failure. Editing a logged food must not modify the saved food or recipe definition, including its last-logged date: today's logging screens set that date on every save, which would move an edited food to the top of My Foods.

### C4. Compose meals and correct meal-photo items

Extend the existing meal screen with the two missing workflows:

1. Start a meal by selecting multiple saved foods, without first creating a recipe.
2. Add a missing food or replace an incorrectly identified item in the meal review screen, including results from a meal photo.

Reuse the existing portion adjustment, item exclusion, combined nutrition preview, meal/time controls, and Save as Recipe flow, plus the recipe editor's Add Ingredient picker (search saved foods or create one), which today is private to the recipe editor and offers saved foods only. These are existing capabilities, not new features to rebuild. Integrate C2's weighed portions into the same review flow.

Apple overlap check: iOS 27's Siri mode in Camera gives nutritional information about a plate of food on Apple Intelligence iPhones. Apple's material does not describe logging that result to Health, and beta-period press coverage (MacRumors, iGeeksBlog) reports that it gives no exact calorie counts and records nothing in Health. C4 stays distinct because it composes, corrects, and logs itemized portions. Recheck this on a device before release positioning.

**Ready when:** every path into the meal screen (a recent meal, a meal photo, and the new manual start) supports adding, replacing, adjusting, and excluding foods; portions can be entered by weight for foods with a known serving weight, and by servings otherwise; preview totals match the logged result; and saving as a recipe preserves the chosen ingredients and amounts. Manual meal composition must work where meal-photo analysis is unavailable: the app runs on iOS 18 and later, while Photo of Meal needs iOS 27 with Apple Intelligence available, and its button is hidden otherwise. Validate the new manual start on an iOS 18–26 device or with Apple Intelligence off.

## Optional additions to 1.1

These are candidates in priority order, not release blockers. Start them only when the core's remaining work and validation are understood; otherwise carry them forward.

| Priority | Feature | Size | Scope and completion condition |
| --- | --- | --- | --- |
| 1 | Siri and Shortcuts for saved foods | Medium | iPhone only initially. Log a saved food or recipe with servings and meal, or re-log a recent meal. Resolve ambiguous names, handle unavailable items, require an unlocked device as the existing log actions do, confirm only successful writes, and reuse the shared food-logging behavior. |
| 2 | Customizable nutrition widget | Medium | Make the existing iPhone Nutrition widget configurable: select and reorder the nutrients it shows. Totals, progress bars, target/limit colors, the Home Screen and Lock Screen layouts, and the locked-device cached fallback already ship and are kept, not rebuilt. Entry gate: before starting, check the current iOS release and beta for a configurable multi-nutrient Health widget; if Apple has one, move this to Held or excluded. |
| 3 | Onboarding | Small–Medium | A skippable first-launch flow explaining Health access, choosing favorites, setting goals (including the existing Suggest Goals), and optionally enabling reminders. Returning users keep their settings, and declining a permission leaves the rest of the app usable. |

As built (October 3, 2026):

- **Siri and Shortcuts.** *Log Food* takes a saved food or recipe, servings (default 1) and an optional meal (the usual one for the time otherwise). *Log Last Meal Again* takes a meal and logs the foods of that meal's most recent day before today, from the last 30 days, at the same meal and now; that's how a phrase picks a recent meal ("Log my last breakfast again in Logalyst"). Foods are identified by name and brand, as the app tells them apart, so a shortcut keeps working on the user's other iPhones; a name matching several foods offers each, and one that's gone is reported without logging anything. Both ask for an unlocked device, speak only after the write succeeds, and log through the same code as the Log screen, marking the saved food as logged. The phrases are compiled for iPhone only, and Siri's list of food names is refreshed when foods or recipes are saved or arrive from iCloud.
- **Nutrition widget.** Held: its entry gate needs the Apple check on the iOS 27.2 beta, which hasn't been done.
- **Onboarding.** Shown the first time Logalyst opens on an iPhone: what it does and why it asks for Health access (asking only after that), favorites, goals (with Suggest Goals), and reminders, each skippable. 1.0 asked for Health access at launch and kept no first-launch marker, so an iPhone where Health has already asked, or that has favorites, goals or saved foods (including ones iCloud brought), is treated as upgrading and goes straight to the app; settings that arrive from iCloud during onboarding show on its pages as they come. Skipping asks for Health access as 1.0 did. The Watch has no introduction of its own and still asks when it first opens.

Dependencies found in the build 25 source:

- **Siri and Shortcuts.** No food action exists today; the three App Shortcuts cover water and single-number metrics. The Health food save, the reading of past food entries, and the portion type are shared code. The saved-food and recipe models, their data store, the recent-meal grouping, and the last-logged update live in the iPhone app target and must be made reachable from an intent. Recent meals have no names (the app shows them as a meal and day, such as "Breakfast, Yesterday", from the last 30 days), so define how a phrase or Shortcuts parameter selects one. The App Shortcuts provider is compiled into both the iPhone and Watch apps, so food phrases must be kept out of the Watch build. If phrases include food names, refresh Siri's list when the library changes, including after iCloud sync; today it is refreshed only at launch.
- **Nutrition widget.** The widget is static today, with a fixed list: calories, protein, carbohydrates, total fat, sugar, fiber, and caffeine (saturated fat, cholesterol, and sodium are deliberately left out). It must become configurable without breaking widgets already placed. The medium size shows four rows and the large seven, and the Lock Screen layouts assume calories followed by protein, carbs, and fat, so define what they show for other selections. The single-metric Metric widget already lets the user pick any one nutrient with its total and goal progress. The Watch has no Nutrition widget, so this is iPhone-only scope. Its differentiation from Apple's offerings has only moderate confidence, from documentation alone, so it remains a validation item, not a proven absence of equivalent functionality.
- **Onboarding.** 1.0 requests Health access automatically at launch on both iPhone and Watch, so the request must move behind the explanation. 1.0 stores no first-launch marker, so decide how 1.1 recognizes people upgrading from 1.0, and people whose settings arrive from iCloud after launch, so they are not treated as new users. State whether the Watch app gets its own introduction.

Saved foods and recipes are stored by the iPhone app, with an end-to-end-encrypted copy in the user's private iCloud database when iCloud is on. The Watch app has no iCloud entitlement, and the iPhone-to-Watch sync carries only favorites, goals, and presets, so logging a saved food or recipe from the Watch requires a separate data-access design. Watch food re-logging is one of the strongest additions, alongside saved-food Siri/Shortcuts and Watch preset buttons. It is listed under Next candidates rather than here because its Watch data access is not yet defined; that definition is its entry gate.

## Next candidates

The following proposals remain in the backlog. Listing them preserves the ideas without expanding the 1.1 commitment.

| Feature | Size | Scope or entry gate |
| --- | --- | --- |
| Food search by name | Large | Search online, review nutrition, then save or log a result. Depends on C2's weight model for per-100-g normalization. Resolve every question in the gate below before scheduling delivery. |
| Watch food re-logging | Medium | Re-log a recent food or meal, rebuilt from Health's food entries rather than the saved-food library. The shared code that reads and re-logs those entries is already compiled into the Watch app but has not been exercised there, and the recent-meal grouping lives inside the iPhone's Add Food screen and would need to be shared. Verify how much food history Health makes available on the Watch, how quickly iPhone entries appear there, and what happens without the phone. |
| Watch today view | Small–Medium | Water, calories, and macros against today's goals, as a screen in the Watch app. Today the Watch app has only the Log list and entry screens; the Metric complication already shows today's total for a Watch metric, with a goal ring for water and caffeine. Calories and macros are phone-only metrics, so neither the Watch list nor its complications offer them. The Watch already asks to read every catalog metric and already receives goals from the iPhone. Define freshness and unavailable-data states, and update the Watch's Health usage description, which currently mentions only prefilling the last reading. |
| Food diary for past days | Small–Medium | A Nutrition day switcher with water, foods grouped by meal, and daily totals; Nutrition lists today only at present. Reuse food editing, which this also extends to older foods. Keep this focused on the food diary rather than general health-history browsing. |
| Goal adherence | Unsized | Days meeting configured nutrition targets or limits over 30/90 days, subject to the gate below. Longer charts alone are not the feature; they overlap Health's existing history views. Medium is more plausible than Small if goals effective on each historical day must be stored. |
| Notes on entries | Small–Medium | Optional entry notes shown in History. Deferred by product choice; define storage, edit/re-log preservation, and synchronization before implementation. General tagging is not included. |
| Toothbrushing timer | Small | Add a start/stop timer beside the existing duration entry (iPhone: a 15-second stepper from 15 s to 10 min plus 1/2/3-minute presets; Watch: 1/2/3-minute buttons that log on tap). State whether the timer is on iPhone, Watch, or both; how a measured time outside the stepper's range or step is saved and later edited; and interruption/cancellation behavior. Reuse the existing repeated-Save guard. |

### Food-search gate

Food search is not part of the 1.1 commitment and does not set its release date. The questions below can be investigated alongside 1.1, but the investigation must not delay the core, and food search is not scheduled into any release until all five are resolved and a separate scope decision is made.

1. **Coverage and access:** choose packaged-food and generic-food sources. The working proposal is Open Food Facts for packaged foods and a second source such as USDA FoodData Central for generic foods like "banana".
   - Confirm which Open Food Facts endpoint will serve name search before estimating. Its API documentation says API v2 offers structured, filter-based search only, API v3 has no search, and full-text search is offered only through the legacy `/cgi/search.pl` endpoint, with a separate Search-a-licious service (search.openfoodfacts.org) intended to provide it. No limits or terms specific to that service were found. Record the chosen endpoint's stability, limits, and terms, and treat a change of endpoint as a known risk.
   - Decide whether generic-food access uses a proxy, user-provided credentials, or a bundled/downloaded dataset. USDA publishes its generic-food datasets as public-domain (CC0) downloads, so the bundled or downloaded option is viable in principle: in the October 2026 listing, Foundation Foods is about 0.5 MB zipped (6.5 MB as JSON), FNDDS 2021–2023 about 3.7 MB (64 MB), and SR Legacy about 12 MB (205 MB as JSON) and no longer updated. The Branded dataset is 195 MB zipped (3.1 GB) and is not a bundling candidate. Measure the app-size or download cost of a trimmed dataset before choosing. A local generic dataset would need no API key and would send no generic-food search terms off the device.
   - Do not ship an extractable shared publisher API key.
2. **Interaction:** keep saved-library filtering local. Use an explicit Search online submission rather than sending each keystroke. Include caching, pagination, request throttling, rate-limit recovery, and clear offline/error states.
3. **Normalization:** map per-serving and per-100-g nutrients into C2's model, preserve source/portion context, and let the user review the result before saving or logging.
4. **Privacy and operations:** identify which queries and identifiers leave the device, their destinations, and any server retention. Today the only request the app sends to a third-party service is the barcode lookup: the barcode number, an app-name User-Agent and, as with any request, the device's IP address go to Open Food Facts, and only when no saved food matches. Any online search, even one sent directly to Open Food Facts, contradicts two current policy statements: that a barcode number is the only other thing that leaves the device, and that the app never connects to the internet unless a barcode is scanned or typed (apart from the App Store, for the Tip Jar). A second provider adds a new recipient to disclose. A proxy additionally requires revisiting the claim that Logalyst has no servers of its own, and rechecking the app's privacy manifest (which declares no collected data) and the App Store privacy answers. Update `PRIVACY.md` before shipping (the website privacy page is generated from it), change its effective date, and note the change in the release notes, as the policy promises.
5. **Licensing, attribution, and identification:** Open Food Facts publishes its database under the Open Database License (ODbL), its contents under the Database Contents License, and product images under CC BY-SA. Its reuse terms require naming the licence and attributing Open Food Facts with a link, and its data page asks apps for prominent attribution on product and search screens and in an About or Settings section. It also asks integrators to send a User-Agent of the form `AppName/Version (ContactEmail)` and to fill in its API usage form. A publicly used adapted database must be offered under the ODbL, so confirm how share-alike applies before choosing a proxy cache or bundled dataset that combines Open Food Facts records with another source, and keep the sources separable. USDA FoodData Central data is public domain (CC0); USDA asks that FoodData Central be listed as the source. Open Food Facts states its data is indicative and not for medical use, so keep the existing prompt to check imported values against the label.

Provider facts, checked against the providers' published documentation on October 3, 2026. Recheck them when the architecture is chosen, because limits can change.

- **Open Food Facts** ([API introduction](https://openfoodfacts.github.io/openfoodfacts-server/api/)): search is limited to 10 requests per minute per IP address and product (barcode) reads to 15 per minute. The documentation says not to use search for search-as-you-type, which is the reason for the explicit Search online step, and exceeding the limits can lead to an IP ban. When requests come directly from users' devices the limits apply per user, so a shared proxy would put every user behind one limit unless it serves its own copy of the data.
- **USDA FoodData Central** ([API guide](https://fdc.nal.usda.gov/api-guide/), [downloadable datasets](https://fdc.nal.usda.gov/download-datasets/)): every request needs a data.gov API key. The key holder is responsible for keeping it from becoming public, and keys found online are deactivated. The default limit is 1,000 requests per hour per IP address, and exceeding it blocks the key for an hour. The shared `DEMO_KEY` is limited to 30 requests per hour and 50 per day per IP address, so it is not a shipping option.

The shipped barcode lookup already uses Open Food Facts, whether or not food search ships. It names the source but shows no licence link, it identifies itself as `HealthLogger/1.0 (iOS)` with no contact address, and it calls API v2, which Open Food Facts now marks deprecated but still supported (v3 is recommended for new integrations). Bring it to the attribution and User-Agent standard independently of food search, and update the privacy policy's list of what is sent to Open Food Facts if the User-Agent changes. Moving to v3 is not a C2 completion condition; decide it when the import code is next changed.

### Goal-adherence gate

Define and re-estimate the feature before scheduling it:

- Check Apple's Longevity tab first. Apple announced that it analyzes long-term data across seven areas including nutrition, and beta coverage describes a status per area measured against clinical guidance plus a nutrition-habits questionnaire. Confirm on a device whether its nutrition view evaluates logged intake over time. Keep this feature only if day-by-day adherence to the user's own configured targets and limits is not shown there.
- Choose comparison against **current goals** or **goals effective on each historical day**. Label a current-goal comparison explicitly; historical comparison requires storing and synchronizing goal changes because only current goals are stored today.
- Every goal-bearing nutrient always has a goal: an unedited goal uses the built-in default (general guidelines for a 2,000-calorie diet), and a goal cannot be switched off. Decide whether adherence counts default goals or only goals the user set or accepted from Suggest Goals; "configured" is otherwise undefined.
- Treat missing intake data as unknown, not zero and not automatic success under a limit. The underlying daily totals already keep "nothing recorded" distinct from zero (the 7-day average relies on this); only the display helper flattens it, so build adherence on the raw totals.
- Define which days enter the denominator, how partial records are handled, and how unfinished today is presented separately.
- The model already marks each goal as a target to reach or a limit to stay under, but the kind is fixed per nutrient and the user cannot change it: water, calories, protein, carbohydrates, and fiber are targets; total fat, saturated fat, sugar, cholesterol, sodium, and caffeine are limits. Decide what "met" means for calories and carbohydrates, where reaching or exceeding the amount currently counts as success; a range or a user-selectable direction may be needed.
- Describe results as based on **intake recorded in Health**; totals include other apps' entries. Some entries on a day do not prove that day's intake is complete.

## 1.2 direction

- **Localization:** German, French, and Spanish first, including app, Watch, widgets, and Shortcuts text. The project is English-only with no string catalogs yet. Much user-facing text is held as plain strings outside views (metric and category names, unit labels, severity and meal titles), reminder summaries are assembled from English fragments with hand-written plurals, Siri phrases and spoken water sizes are English, and the nutrition-label scanner recognizes English and French label terms only. Estimate after auditing these, localized units/formatting, and per-language Siri phrases. Apple's redesigned Health app launches in U.S. English first, so recheck its language availability when positioning this work.
- **iPad support:** the iPhone app and its widget extension are built for iPhone only, and the app is portrait-only. Enable the iPad device family, adapt navigation and layouts, and decide how per-device features behave when an iPhone and an iPad share an iCloud account: settings, including log reminders, sync through iCloud, and each device schedules its own reminder notifications, so both devices would remind unless that is changed. Confirm how the iPhone-to-Watch sync code behaves on a device with no paired Watch. Estimate after a platform and layout review.

These two items are the whole of the 1.2 direction so far. Other backlog candidates need a separate scope decision before joining that release; no calendar dates are committed here.

## Held or excluded

Each row carries one basis:

- **Confirmed overlap:** Apple's documentation or announcements describe the same workflow. This is documentation-based, not a hands-on check. Under the standing rule the item is not planned for any release.
- **Unverified overlap:** Apple may cover it. Held until the complete workflow is checked on a device running the current iOS release or beta.
- **Product choice:** no overlap claim; left out for focus.

Apple's feature-specific PDFs and cycle-related symptom entry do not establish arbitrary multi-metric reports or general multi-symptom logging, so those two are listed separately below as unverified.

| Proposal | Basis | Disposition |
| --- | --- | --- |
| Generic charts and longer trends for every metric | Confirmed overlap | Not planned. Health already has history and trend views, which Apple's "View your data in Health" page documents. |
| General insights or personalized health interpretation | Confirmed overlap | Not planned. Apple's September 9, 2026 announcement describes an Insights tab with personalized recommendations and a Longevity tab with long-term analysis in the redesigned Health app. Also outside the product focus. |
| Broad history browsing, filtering, and paging | Confirmed overlap | Not planned: general Health-history overlap, though filter and paging details were not individually checked. A known limit stays: History loads only the 200 most recent Logalyst entries, with no filter, search, or "load more". The food-specific day diary remains a candidate. |
| Mood | Confirmed overlap | Not planned. Apple documents State of Mind logging in Health. |
| Export of Health data | Confirmed overlap | Not planned. Apple documents an XML export of all Health data. |
| Doctor-oriented or multi-metric PDFs | Unverified overlap | Held. Apple documents feature-specific PDFs: the Blood Pressure Log (described as for sharing with a doctor), the medication list, and mental-health assessment results. Beta coverage also reports a Longevity PDF. A PDF of user-chosen metrics was not found in the sources reviewed. Revisit only with a specific unmet workflow, and leave blood-pressure and medication reports out of it. |
| More symptom types | Confirmed overlap | Not planned unless a specific gap is shown. Health accepts manual entry of individual symptoms, and Logalyst already logs 18 symptoms one at a time, each with a severity. |
| Multi-symptom entry | Unverified overlap | Held. A single form that logs several symptoms together was not found in the sources reviewed, and Apple's cycle-related symptom entry does not establish a general workflow. Reassess only for that gap. |
| Siri for blood pressure | Confirmed overlap | Not planned. Apple lists blood pressure among the Health data Siri can read and write (U.S. English and Mandarin Chinese only; Apple Support 118493). |
| Siri for symptoms | Unverified overlap | Held, and outside the food-focused Shortcuts scope. Siri symptom logging was not found in the Apple pages reviewed, and whether the Shortcuts Log Health Sample action covers it is unchecked. Logalyst's own Log Metric action covers only single-number metrics today. |
| Pulse alongside blood pressure | Unverified overlap | Held. Apple's documented blood-pressure entry (Apple Support 122995) has date, time, systolic, and diastolic fields and no pulse field, so no documented equivalent of a combined entry was found; separate heart-rate entry does not prove equivalence. Confirm the form on a device, including the redesigned Health app, then make the scope decision. |
| Label micronutrients: vitamin D, calcium, iron, potassium | Unverified overlap | Held pending one device check. Apple's iOS 27 material describes Siri mode in Camera giving nutritional information about a plate of food and does not mention nutrition-label scanning or writing nutrients to Health; MacRumors reports the camera's nutrition data does not sync to Health. A pre-release Bloomberg report and some third-party guides say a label scan logs calories and macronutrients to Health. Settle it by scanning a label in Siri mode in Camera on iOS 27 and checking which Health nutrition samples, if any, are written. If none, or macronutrients only, the micronutrient gap is not an Apple duplicate. |
| Siri "what's my total today" as a standalone question | Unverified overlap | Held. Apple documents Siri reading and writing certain Health data only with Siri set to U.S. English or Mandarin Chinese, gives blood pressure and body temperature as its examples, and states that reading Health data is not available with Siri AI (Apple Support 118493). No source reviewed shows Siri answering nutrition or water totals. Test the specific totals on a device, with and without Siri AI. Logalyst's existing log actions already speak today's total after logging an intake metric, and that stays. |
| General notes and tags | Product choice | Notes kept as a later candidate; tags excluded. |
| Manual Snooze and Skip buttons on reminders | Product choice | Excluded from 1.1 and not listed as a later candidate. Reminders already skip themselves when the metric has been logged, can stop once a daily target is met, and offer a one-tap Log button for metrics with a preset. Apple's medication reminders do not by themselves establish equivalence to every Logalyst reminder workflow. |

Watch preset buttons are in the 1.1 core as the contained, Small improvement that does not depend on the food work: presets already sync to the Watch, which receives them but does not show them. No Apple equivalent has been found: the hands-on Quick Log check found no presets. Built-in Health logging through Siri (documented for U.S. English and Mandarin Chinese, on iPhone and on supported Apple Watch models; Apple Support 118493) or through a Shortcuts Log Health Sample action can approximate the outcome, but neither provides the same preset interface or a saved-food workflow.

## Build sequence and release gate

1. **Validate against Apple Health first:** before starting C2–C4, check on the current iOS release and beta whether Apple offers an equivalent to weighed portions, editing a logged food entry, or multi-food meal entry. Record the device, build, and date under Evidence. If Apple covers a workflow, move that item to Held or excluded.
2. **Build the contained improvement first:** implement C1 against existing preset synchronization, once its unit decision is made.
3. **Establish the food foundation:** define and migrate C2's numeric weight data, then connect imports, recipes, logging, and re-logging. In parallel, design and test C3's replacement/cleanup recovery. Before distributing a 1.1 build, add the new field to the CloudKit development schema and deploy it to production. The Debug `-InitializeCloudKitSchema YES` launch argument exists for this, because syncing alone creates only fields that have held a value, and App Store builds can reach only the production environment. A field cannot be deleted once it is in production, so settle its name and type first.
4. **Complete correction and composition:** deliver C3 and C4 using the shared portion calculations and existing meal UI. C3's servings, meal, and time edits and C4's servings-based composition do not depend on C2 and can be completed first if C2 slips.
5. **Assess capacity:** add optional 1.1 features in the order above only if they do not delay core validation. Investigate food-search access separately.
6. **Validate the release:** exercise upgrades from build 25, iCloud round trips and local-only use, foods without weight metadata, recipe snapshots, permission failures, interrupted edits, meal composition and correction (including on a device where meal-photo analysis is unavailable), and Watch preset synchronization. Confirm Health totals and UI refreshes after logging, editing, deleting, and re-logging. After upgrading from build 25, confirm the saved-food store still opens with iCloud sync on: the app falls back to a device-only store, without telling the user, if the iCloud-backed store cannot be created, and stops at launch if neither opens. Include a second iPhone still on build 25 syncing the same iCloud data: it must keep working, and what happens to weights when a food or recipe is edited there must be observed and decided (build 25 rewrites a recipe's ingredient list without any weight key).

Release 1.1 when all of the following hold:

1. C1–C4 each meet their Ready-when conditions.
2. The "Validate the release" step passes, including the injected C3 failures and Health permission failures.
3. Each shipped feature has been rechecked against Apple Health on the then-current iOS release and beta, with device and build recorded under Evidence.
4. User-facing documentation describes the shipped behavior: the README and the website support page (both currently say foods cannot be edited), and the App Store listing where it describes affected behavior. `PRIVACY.md` is updated if stored or transmitted data changes.
5. New and changed screens have been validated with VoiceOver and supported text sizes.

An unfinished optional feature moves to the backlog rather than becoming an implicit release blocker. If a core feature cannot meet its condition, cutting it or delaying 1.1 is an owner decision.

## Open decisions and checks

Decisions and checks this plan leaves open. Record each outcome here when made.

1. **C1 release timing.** Release Watch presets ahead of the rest of 1.1, or with it? *Open: built into 1.1, so it ships with it unless the owner decides otherwise.*
2. **C1 units.** Accept that the Watch shows only presets for its own unit, or add the iPhone's unit choices to the iPhone-to-Watch sync? *Decided October 3, 2026: accept and document. Syncing units would also change the unit the Watch logs and its complications show, which is more than C1. Recheck if users ask for it.*
3. **C2 slip.** The release gate requires all four core features. If the weight model slips, hold 1.1 or re-scope it to servings-only C3 and C4? *Moot: C2 is implemented.*
4. **C2 existing foods.** Offer a weight parsed from existing serving text (including the "100 g" barcode fallback), or leave existing foods unweighted until edited? Does an entry logged before 1.1 pick up a matching saved food's weight? *Decided October 3, 2026: existing foods stay unweighted until edited; the food editor then offers a weight its serving size states in grams ("Use 30 g from Serving Size"), never filling one in itself, and doesn't offer the barcode fallback's "100 g", which may be per 100 mL. New barcode imports get a 100 g weight only for a product sold by weight, and say "100 mL" for one sold by volume. An entry logged before 1.1 picks up its saved food's weight in Add Food's recents only when the saved food has the same name, brand, serving size and nutrition per serving; it isn't used when editing that entry, which stays by the serving.*
5. **C3 recovery scope.** Does the stronger edit recovery apply to foods only, or replace the existing edit behavior for every entry type? *Decided October 3, 2026: every entry type, through one shared path, so the two edit flows can't diverge.*
6. **Apple Health device checks.** Still needed on a device: C2–C4 equivalents; a configurable nutrition widget; whether the Longevity tab's nutrition view evaluates logged intake (goal adherence); whether Siri mode in Camera writes anything to Health from a plate photo or a label scan (C4, label micronutrients); the blood-pressure form (pulse); Siri totals and Siri symptom logging; multi-symptom entry. Also record the device model and beta build for the Quick Log check. *Still open. An attempt in the iOS 27.0 simulator's Health app found its Browse tab empty, so it can't stand in for a device; see Evidence.*
7. **Food search.** The five questions in the food-search gate, including whether Logalyst will run a server of its own, and which release it targets once the gate clears.
8. **Goal adherence.** The definitions in the goal-adherence gate, starting with the Longevity check.
9. **Food data on Watch.** What is available, how it refreshes, and what happens without the phone. Blocks Watch food re-logging and food Shortcuts on Watch.
10. **Notes and toothbrushing timer.** Notes storage, edit/re-log preservation, and synchronization; which devices get the timer, and its interruption and cancellation behavior.
11. **The Quick Log name.** Logalyst already ships a Home Screen widget named Quick Log, the name Apple now uses in the redesigned Health app. Decide before release positioning whether the shared name needs a change or an explanation.
12. **1.2 scope.** Which backlog candidates, if any, join localization and iPad support.

## Evidence and sources

On October 3, 2026 this roadmap's statements about the current app were checked against the build 25 source (food models and storage, the meal screen, Health save/delete helpers, the Watch app, widgets, Shortcuts actions, goal storage, reminders, the README, and the privacy policy), and every external link listed below was opened. Nothing was built or run, and this is not a hands-on audit of Apple's products: the link check covers what the pages say, not device behavior.

The overlap checks rest on Apple's September 2026 Health announcement and iOS 27.2 beta material. Those sources establish less than a quick read suggests:

- The iOS & iPadOS 27.2 release notes (beta 2 on October 3) contain a single Health item, a known issue with Insights summaries, and describe no logging features.
- Apple's September 9 announcement covers the Insights and Longevity tabs, Health Age, movement evaluations, labs, and Cycle Tracking. It does not mention Quick Log, food logging, or widgets.
- The iOS 27 "View your data in Health" page still documents the Summary and Browse screens of the earlier Health app, and no Apple page reviewed documents Quick Log.
- Apple's "About actions in complicated shortcuts" guide covers actions suited to shortcuts run from a widget or Apple Watch and mentions the Log Health Sample action in one example; it is not Health-logging documentation.
- The redesigned Health app is still a preview. Apple says it will be available later this year, starting in U.S. English, on Apple Intelligence-enabled iPhone and iPad models, and press coverage of the beta reports it will not ship in the iOS 27.2 release itself. Overlap findings taken from the beta can therefore change before release, and some Logalyst users (the deployment target is iOS 18) will be on devices or languages the redesign does not cover. Record each overlap check against both the current and the redesigned Health app.

**Quick Log.** Here "Quick Log" means the section at the top of the redesigned Health app's Browse tab, not Logalyst's own Quick Log widget. A hands-on check by the owner on an iOS 27.2 beta device found that it opens a plain entry sheet (date, time, amount) with no presets and no widget; the device model and beta build are still to be recorded, and the check has not been repeated. One independent hands-on with beta 1 (Tech Between the Lines, September 17, 2026) describes the same section as two shortcuts by default that can be edited and reordered from Health's categories, including individual nutrients and symptoms; it mentions no preset amounts and no widget.

Apart from the Quick Log check, treat "no equivalent found" as documentation-based and provisional. Before starting work on each feature, verify its complete workflow on the current iOS beta, and record official sources plus device and build details for hands-on checks here.

### Simulator validation, October 3, 2026

Xcode 27.0 (27A266a). Simulators: iPhone 18 Pro on iOS 27.0 (24A434), upgraded in place from a build 25 install seeded with saved foods, a recipe and a week of Health entries; iPhone 17 Pro on iOS 26.5 (23F77), where Photo of Meal is unavailable; Apple Watch SE 3 (40 mm) on watchOS 27.0 (24R362), paired with the iPhone 18 Pro; and a new iPhone 18 Pro on iOS 27.0 for first-launch onboarding. The unit and HealthKit tests (52) and the UI tests passed there. What was validated, and what wasn't, is in [1.1 implementation status](#11-implementation-status).

The iOS 27.0 simulator's Health app was opened to check C2–C4 against it, but its Browse tab and search showed no data types, so the simulator can't stand in for the device checks in Open decisions 6.

### External sources

Opened on October 3, 2026.

Apple:

- [iOS & iPadOS 27.2 beta release notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27_2-release-notes)
- [Apple's September 2026 Health announcement](https://www.apple.com/newsroom/2026/09/apple-advances-health-and-fitness-capabilities-using-apple-intelligence/)
- [View your data in Health](https://support.apple.com/guide/iphone/view-your-health-data-iphe3d379c32/ios): history, highlights, and trend views
- [Log your state of mind in Health](https://support.apple.com/en-euro/guide/iphone/iph6a6decb13/27/ios/27)
- [About actions in complicated shortcuts](https://support.apple.com/en-ae/guide/shortcuts/apd081d9d61f/ios): the page with the Log Health Sample example
- [Meet the HealthKit Medications API (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/321/): Apple's medication reminders
- [Blood-pressure logging instructions (Apple Support 122995)](https://support.apple.com/en-gb/122995): entry fields and the Blood Pressure Log PDF
- [Health data sharing and export](https://support.apple.com/en-am/guide/iphone/iph5ede58c3d/ios)
- [Health data with Siri (Apple Support 118493)](https://support.apple.com/en-us/118493)
- [About iOS 27 Updates (Apple Support 149076)](https://support.apple.com/en-us/149076): Siri mode in Camera

Food data:

- [Open Food Facts API introduction](https://openfoodfacts.github.io/openfoodfacts-server/api/), [data and licences](https://world.openfoodfacts.org/data), and [terms of use](https://world.openfoodfacts.org/terms-of-use)
- [USDA FoodData Central API guide](https://fdc.nal.usda.gov/api-guide/) and [downloadable datasets](https://fdc.nal.usda.gov/download-datasets/)

Press coverage from the beta period, used only where no Apple page covers the point:

- [MacRumors: iOS 27.2 Health app beta](https://www.macrumors.com/2026/09/16/ios-27-2-health-app-beta/) and [iOS 27 Health guide](https://www.macrumors.com/guide/ios-27-health-app/)
- [Tech Between the Lines: the redesigned Health app in the iOS 27.2 beta](https://www.techbetweenthelines.com/inside-apples-redesigned-health-app-everything-we-found-in-the-ios-27-2-beta/)
- [iGeeksBlog: Health app features in iOS 27](https://www.igeeksblog.com/ios-27-health-app-features/)
