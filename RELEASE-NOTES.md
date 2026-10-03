# Release notes

Drafts of the App Store "What's New" text, newest first. Trim to fit when submitting.

## 1.1 (draft)

Editorial note (not App Store copy): C5, restaurant and brand nutrition lookup, is implemented and was checked against real restaurant websites in a simulator, but not yet with a real meal photo or on a device (see `ROADMAP.md`). Recheck its bullet against the device validation before publishing.

- **Log food by weight.** Give a food its serving weight and log it in grams or ounces: 35 g of a food measured
  per 100 g logs exactly that. Barcode lookups and label scans fill in the weight when the serving is in grams.
- **Fix logged food.** Tap a food in History or Nutrition to change how much you had, the meal, or the time. If an
  edit is interrupted, Logalyst finishes it next time instead of logging it twice.
- **Build a meal.** Start a meal from several of your foods with New Meal, and add a food you missed or swap one
  that's wrong on any meal screen, including a photo of a meal.
- **Restaurant nutrition for meal photos.** Add the restaurant or brand to a photo of your meal, like Chipotle,
  and Logalyst finds the nutrition it publishes on its website and uses it for each part of the meal, scaled to
  what you had, with a link to the source. Choose between foods that look alike, confirm ones hidden under the
  rest, and fall back to on-device estimates when a food isn't listed or you're offline.
- **Presets on Apple Watch.** Your preset amounts now appear as buttons when you log on the Watch.
- **Privacy policy update:** food entries in Health and saved foods now include a serving weight, and an edit in
  progress is noted on your iPhone until it finishes. When you look up a restaurant's or brand's nutrition, its
  name goes to Apple Maps to find its website, which Logalyst reads like a browser, blocking advertising and
  analytics services; your photo and what you ate stay on your iPhone. Looked-up foods keep their source.
