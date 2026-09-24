# Vitals Log

An iPhone + Apple Watch app for manually logging health data that Apple Watch doesn't capture, written straight into Apple Health (HealthKit).

## What you can log

| Category | Metrics |
| --- | --- |
| Vitals | Blood pressure, blood glucose (with before/after meal), body temperature |
| Body | Weight, body fat %, lean body mass, waist circumference |
| Intake | Water, caffeine, alcoholic drinks, calories, protein, carbs, fat, sugar, fiber |
| Symptoms & events | 18 symptoms with severity (and optional duration), inhaler use, toothbrushing (duration), sexual activity (with protection used) |

- **Favorites:** swipe right on a metric (or touch and hold it on iPhone) to star it and pin it to the top of the
  Log list. Favorites sync between iPhone and Watch; if both change at once, the latest edit wins.
- Units follow your Health app preferences (e.g. lb vs kg, mg/dL vs mmol/L) unless you pick one in the
  **Options** tab, and you can switch per entry.
- Measurements like weight and blood pressure are prefilled with your last reading.
- **Presets:** tap a preset amount on an entry screen to fill it in. Type an amount and tap *Save as Preset* to add
  your own (up to 6 per unit, for any number metric), touch and hold one to remove it, or restore the defaults.
  Presets are kept per unit, so a 330 mL preset doesn't show when you enter fl oz. The Water widget's buttons use
  your first water presets, and they're edited on the iPhone and sent to the Watch.
- **Nutrition** tab tracks today's water against a daily goal (with a progress ring and a
  list of today's water to tap and fix or swipe away), shows calories, macros, sugar, fiber and caffeine against daily
  targets or limits, and charts any intake metric over the last 7 days. Totals include data other apps
  save to Health. Tap the target button to edit goals.
- **Water reminders:** turn them on in the **Options** tab to get a notification when you haven't logged water
  for a while (1 to 4 hours), between the times you pick. Water logged anywhere (the app, widgets, Siri, the Watch
  or other apps) pushes the next reminder back, and they stop for the day once you reach your water goal (you can
  turn that off). Touch and hold a reminder to log a glass (your smallest water preset) without opening the app,
  or tap it to open Nutrition. Reminders are scheduled on the iPhone a few days ahead and show on the Watch while
  the iPhone is locked.
- **Suggest Goals:** in the goals sheet, estimates calories, protein, carbs, fat, sugar and fiber from your weight,
  height, age and sex (read from Health when set, otherwise typed in), activity level, and whether you want to
  lose, maintain or gain weight. Calories burned at rest come from Apple Health's resting energy when there are at
  least 3 days of it in the last two weeks (the median day, so days the Watch was off for a while don't lower it;
  you can turn this off), otherwise from the Mifflin–St Jeor equation. Protein is 1.6 g/kg (1.2 g/kg to maintain),
  capped at 35% of calories. Fat is 30% and carbs are the rest. Sugar stays under 10% and fiber is 14 g per
  1,000 kcal. Losing weight takes off up to 500 kcal (never more than 20%, or below 1,200/1,500 kcal), and
  gaining adds 300 kcal. It only suggests goals for adults, and nothing changes until you tap *Use These Goals*.
  Water and caffeine goals aren't touched.
- **Foods:** save foods with their nutrition per serving (My Foods), then log them by the serving. Each one is
  saved to Health as a single food entry, so Health shows it by name and History lists it once. Scan a
  barcode to jump straight to a saved food, or to fill in a new one from
  [Open Food Facts](https://world.openfoodfacts.org), a free, open food database. You can also type the number
  if the camera can't read it. Saved foods live on the iPhone only.
- **History** tab lists everything logged from either device; swipe to delete, or tap an entry to fix it. Health
  can't change a saved entry, so editing saves the corrected one and then deletes the original. Foods can only be
  deleted.
- **Widgets** (iPhone Home Screen, Lock Screen and Control Center):
  - *Water*: today's water against your goal, with buttons that log a glass without opening the app.
  - *Nutrition*: calories and nutrients against your daily goals. On the Lock Screen it shows a calorie gauge,
    or calories with protein, carbs and fat.
  - *Quick Log*: your favorites (or a few common metrics until you star some); tap one to open its entry screen.
  - *Metric*: pick any metric to see its latest reading, or today's total for intake.
  - *Log Water* and *Log Metric* controls for Control Center and the buttons at the bottom of the Lock Screen.
    Log Metric opens the entry screen for the metric you pick.
- **Siri and Shortcuts** (iPhone and Apple Watch):
  - *Log Water*: "Log water in Vitals Log" logs a glass (your smallest water preset) in your unit. In Shortcuts you
    can set any amount and unit.
  - *Log Water Serving*: "Log 16 ounces of water in Vitals Log" (or 8, 12, 20, 24 or 32 oz, 250, 330, 500 or
    750 mL, or a liter) logs it in one sentence. Siri phrases can't hold any number, only choices from a list.
  - *Log Metric*: "Log my weight in Vitals Log" (or blood glucose, caffeine, or any other metric logged as a
    number that the device offers) asks for the value in your unit, then saves it. In Shortcuts you can set the
    value and unit, which makes automations like "log 95 mg of caffeine when I arrive at the coffee shop" possible.
  - Every phrase has to include the app's name. Siri says what was saved and, for intake, today's total. Like
    the widgets, these ask you to unlock first.
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

## Adding a metric

Everything is driven by the catalog in `Shared/Metric.swift`. Add a `Metric` entry with its HealthKit
identifier and unit options (plus an optional `dailyGoal` for intake metrics), and it will appear in the log list, permission request and history on both devices.

## Layout

```
HealthLogger/        iPhone app (Log, Entry, Nutrition, History, Options screens)
HealthLoggerWatch/   Watch app (Favorites, Digital Crown entry)
HealthLoggerWidgets/ iPhone widget extension (Water, Nutrition, Quick Log)
HealthLoggerWatchWidgets/  Watch widget extension (complications)
AppShortcuts/        Siri phrases, compiled into the iPhone and Watch apps
Widgets/             Metric widget, Log Water and Log Metric controls, and widget helpers, compiled into both
                     widget extensions
Shared/              Metric catalog, HealthStore (HealthKit read/write), NutritionGoals, DeviceSync
                     (favorites and goals, Watch ↔ iPhone), app group settings, and the logging intents Siri, Shortcuts and
                     widget buttons run, compiled into every target
Config/              Entitlements and the widget extensions' Info.plists
```
