# Logalyst Privacy Policy

_Effective October 3, 2026_

Logalyst is an iPhone and Apple Watch app for logging health data into Apple Health. It was built to keep
your data on your devices. This policy explains what the app accesses, where that data goes, and how to remove it.

## The short version

- **We don't collect your data.** Logalyst has no accounts, no servers of its own, and no analytics,
  advertising or tracking.
- **Your health data stays in Apple Health.** The app reads and writes it only on your devices, and never sends
  it anywhere.
- **Your saved foods, recipes and settings sync through your own iCloud account**, end-to-end encrypted, so
  only your devices can read them. We can't see them.
- **The only other things that leave your device** are a product barcode number, when you scan a food that
  isn't one of your saved foods (it goes to Open Food Facts), and a restaurant or brand name, when you ask Logalyst
  to use that brand's published nutrition for a photo of a meal (it goes to Apple Maps, to find the brand's
  website, which Logalyst then reads like a browser would). Your photos and what you ate never leave your iPhone.

## Health data

With your permission, Logalyst uses Apple Health (HealthKit) to:

- **Save** the measurements, intake, symptoms and events you enter, such as blood pressure, blood glucose,
  weight, water, nutrition, symptoms and sexual activity. Each food entry also records the food's name, brand,
  serving size and weight, how much you had and the meal, so it can be logged again or corrected, and either
  where its nutrition was published (for a food looked up online) or that it was estimated from a photo.
- **Read** that same kind of data to show your history, prefill your last reading, show today's totals and
  charts, and power the widgets and Watch complications. Nutrition totals include data that other apps have saved
  to Health.
- **Suggest goals:** if you open Suggest Goals, read your height, weight, date of birth, sex and resting energy to
  estimate daily water, calorie and nutrient goals. The estimate is worked out on your iPhone. Your activity level,
  weight goal and whether to use resting energy are saved with your settings (see
  [Data stored on your device and in iCloud](#data-stored-on-your-device-and-in-icloud)); your measurements
  aren't saved anywhere else.

You choose which types of data Logalyst can read and write, and you can change this at any time (see
[Your choices](#your-choices)).

Health data is read and written only on your iPhone and Apple Watch. Logalyst never sends it to us or to
anyone else, and never uses it for advertising, marketing or data mining. It is never sold or shared. If you have
turned on iCloud syncing for Health, Apple handles that under
[Apple's Privacy Policy](https://www.apple.com/legal/privacy/), not Logalyst.

## Data stored on your device and in iCloud

Logalyst keeps a few things in its own storage on your device:

- **Settings:** your preferred units, daily goals and limits, favorite metrics, preset amounts, log reminder
  schedules, and your Suggest Goals answers.
- **My Foods and recipes:** the foods you save, with their nutrition per serving, serving weight and barcode, and
  the recipes you make from them, including where a looked-up ingredient's nutrition was published.
- **Edits in progress:** when you correct an entry, which entry is being replaced and by which, until the
  correction is finished, so an edit cut short (for example by the app closing) can be completed. This stays on
  your iPhone and isn't synced.

- **Lookup results:** restaurant and brand nutrition you've looked up, for up to 24 hours, so the brand's website
  isn't read again. They're kept in the app's cache on your iPhone, which isn't backed up or synced.

If you're signed in to iCloud, the iPhone app also keeps a copy of these in the app's private database in your
iCloud account, so they follow you to a new iPhone or your other iPhones. Every field is end-to-end encrypted with
keys only your devices hold, so neither Apple nor we can read them. Apple can see only that the records exist,
their size and when they changed. If you're not signed in, or turn iCloud off for Logalyst in Settings, they stay
on your iPhone only. Because the keys are in your iCloud Keychain, if you ever reset your end-to-end encrypted
data, the copy in iCloud can't be read any more, but the copy on your iPhone is kept.

Log reminders are scheduled by your iPhone itself, not sent from a server. They can show how much of a daily goal
(like water) you have left, or when you last logged a metric, which appears on your Lock Screen unless you hide
notification previews in Settings.

Your favorites, daily goals and presets sync between your iPhone and Apple Watch directly over Apple's Watch
connection. The Watch doesn't use iCloud for these.

## Camera

If you take or choose a photo of a meal, Apple Intelligence's on-device model estimates the foods in it on your
iPhone. The photo isn't sent anywhere or kept, and nothing is logged until you check it and tap Log. The same goes
for any details you write about the meal. If you also give a restaurant or brand, see
[Restaurant and brand lookup](#restaurant-and-brand-lookup).

If you scan a barcode or a nutrition label, Logalyst uses the camera to read it. Barcodes and label text are
recognized on the device, and camera images are never saved or sent anywhere. If you choose a photo of a label
instead, the app reads only that photo, on the device, and doesn't keep it.

## Open Food Facts

When you scan or type a barcode that doesn't match one of your saved foods, Logalyst looks it up in
[Open Food Facts](https://world.openfoodfacts.org), a free, open food database run by a nonprofit. To do this,
the app sends Open Food Facts:

- the barcode number, and
- the app's name and version, and our support email address, which Open Food Facts asks apps to include so it
  can contact the app's developer.

As with any website, Open Food Facts also receives your device's IP address when it answers the request. Nothing
else is sent: no health data, name, account or device identifier. Open Food Facts' handling of this data is
covered by the [Open Food Facts privacy policy](https://world.openfoodfacts.org/privacy).

## Restaurant and brand lookup

When you take or choose a photo of a meal, you can add the restaurant or brand it's from, such as Chipotle, to
use the nutrition that brand publishes. Only when you tap **Look Up Nutrition** (or search a brand's foods while
checking the meal), Logalyst, on your iPhone:

- asks **Apple Maps** for the brand's website, sending the brand name you typed (if Maps doesn't know it, the
  on-device Apple Intelligence model suggests one, without anything leaving your iPhone), then
- opens the **brand's own website** and the nutrition pages and documents it links to, such as a PDF of its
  nutrition facts, the way a web browser would.

The brand's website, and the file host it keeps a nutrition document with if it uses one, receive your device's IP
address and a standard browser request, as they would if you visited them in Safari. Some sites need other
companies' scripts to show their nutrition, so those scripts and the data they fetch are allowed, except from
well-known advertising, analytics and session-recording services, which Logalyst blocks. Nothing else from other
companies is loaded (no images, frames or tracking pixels), and no cookies are kept: each lookup starts fresh and
nothing from it is stored by the website's code on your iPhone. Apple handles the Maps request under
[Apple's Privacy Policy](https://www.apple.com/legal/privacy/), and each website's own privacy policy covers its
handling of the visit.

Nothing about your meal is sent: your photo, when and where it was taken, the details you wrote and the foods
Apple Intelligence found stay on your iPhone, where the brand's nutrition is searched for them. Your saved foods
and health data are never sent.

What's read from a brand's website is kept in the app's cache on your iPhone for up to 24 hours, so the same
lookup doesn't open the site again. When you log a food that was looked up, its source (the page's title and
link, the website, when it was read and the serving the values are for) is saved with the food entry in Health,
and with a recipe you make from it, so you can check it later.

## Internet use

Logalyst connects to the internet only to look up a barcode in Open Food Facts, to find and read a restaurant's
or brand's published nutrition when you ask, and to reach the App Store to show and buy tips when you open the
Tip Jar.

## Tips

If you leave a tip in the Tip Jar, the purchase is handled entirely by Apple through the App Store. Logalyst
never sees your payment details, and doesn't keep a record of tips.

## Information from Apple

If you agreed to share app analytics or crash reports with app developers in your device's settings, Apple may
give us anonymous crash reports and usage statistics. Apple collects these, not Logalyst, and you can turn
them off in **Settings › Privacy & Security › Analytics & Improvements**.

## Your choices

- **Change Health access:** open the Health app, tap your profile picture, then **Apps › Logalyst**.
  You can also go to **Settings › Apps › Health › Data Access & Devices › Logalyst**.
- **Turn off camera access:** go to **Settings › Apps › Logalyst**.
- **Keep meal photos to your iPhone:** leave **Restaurant or Brand** blank, and nothing about the meal is sent.
- **Delete entries:** swipe to delete in Logalyst's History tab, or delete them in the Health app.
- **Delete saved foods and recipes:** remove them in Add Food. They're removed from iCloud too.
- **Stop syncing with iCloud:** go to **Settings › [your name] › iCloud**, tap **See All** under Saved to
  iCloud, and turn off Logalyst.
- **Remove everything:** deleting Logalyst removes its settings, saved foods and recipes from your iPhone. To
  remove the copy in iCloud as well, go to **Settings › [your name] › iCloud › Manage Account Storage ›
  Logalyst** and delete its data. Entries you logged stay in the Health app until you delete them there.

## Children

Logalyst isn't directed at children, and it doesn't collect personal information from anyone.

## Changes to this policy

If this policy changes, we will update it here and change the effective date above. If a change affects how your
data is handled, we will also say so in the app's release notes.

## Contact

Questions about this policy or your privacy? Email [support@logalyst.app](mailto:support@logalyst.app).
