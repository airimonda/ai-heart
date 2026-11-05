# AiHeart

A private iPhone journal that learns from my own body: mood, sleep, cycle, labs, training and media in one place. The data and the AI stay on the phone by default. An optional cloud model for text features is off by default.

I built it for myself, as a data scientist who wanted to see how my body and my mood move together without handing that data to anyone. It describes what is happening. It never tells me what to do.

<p>
  <img src="docs/screenshots/03-insights-your-body.png" width="200" alt="Insights">
  <img src="docs/screenshots/04-mood-outlook.png" width="200" alt="Mood outlook">
  <img src="docs/screenshots/12-calendar-mood-glow.png" width="200" alt="Calendar">
</p>
<p>
  <img src="docs/screenshots/06-patterns-mood-map.png" width="200" alt="Mood map">
  <img src="docs/screenshots/13-media-vibe.png" width="200" alt="Media vibe">
</p>

*Screenshots use the app's built-in sample data.*

## What it does

**Capture, in a few taps**
- Write, talk, add a photo, tap a feeling word, or mark where you feel it on a body map.
- Today's log: sleep, medication dose, heart rate, weight and blood pressure as one-tap tiles (no watch needed).
- Weekly body check-in, and lab results read from a screenshot of the report (English and Japanese, on device).

**Insights from my own data, not population norms**
- Body signals against my own 28-day baseline, matched to cycle phase once there are enough cycles.
- Patterns with honest uncertainty: mood by cycle phase, sleep and the next day, activity and mood, a density map of where my mood has been.
- Mood outlook: a small ridge model per day ahead, shown as a lean with an uncertainty band. It says "Not yet" until it beats two naive baselines (same as yesterday, 7-day mean) in a rolling backtest.
- Labs: lab history with the lab's own ranges, dose changes, and what I noticed between tests.

**A journal that colors itself**
- Each entry takes a color from where it sits on a pleasant/unpleasant and still/stirred plane. The calendar glows brighter on good days.
- Entries without a feeling get a tone guess from the language model (on the phone, or the cloud model if switched on), used only for color.
- Keep or release: hard entries can be let go, keeping only a short summary (what happened, feelings, how strong, what was needed). Deleted entries wait 30 days in Recently deleted. Entries about self-harm are always kept and open a safety page.

**Listen**
- When words won't come: talk or type, and it mostly listens. Speech is transcribed on the phone. No persona, no advice, no memory between sessions.

**Talk it through**
- A reflective conversation I start when I want to think a hard moment through, in a warm voice. It can search my own notes and, if I choose "Remember it", my own words from earlier talks (older ones count for less). It never gives a diagnosis or a promise, and a fixed safety card shows when something reads as heavy.
- Uses the cloud model if I switched it on (see Privacy), otherwise the on-device one.

**Safety plan**
- A short plan I write myself, one tap away from the toolbar, opened automatically on entries about self-harm.

**Media**
- Spotify (live), Netflix and YouTube history, shown as the week's hours, late nights and what's on repeat, plus a short "vibe" written on the phone from titles, genres and lyrics.

**Out, on my terms**
- PDF reports for a therapist and a doctor, a "My data" report with charts and tables, a spreadsheet export, and a passphrase-locked backup with restore.
- A few fixed red-flag rules (very high blood pressure, very fast or slow heart rate, chest pain and similar) show the local emergency number. Nothing else is medical advice.

## Privacy by design

**Tier 1: on the phone, by default**
- No servers, no analytics, no accounts. Data lives in an encrypted SwiftData store on the phone.
- The language model (Qwen3-VL 4B, 4-bit, via MLX) runs on the device and does all the work unless I switch the cloud model on. Nothing leaves the phone.
- Every model output is checked before it is shown: no diagnoses, labels, advice or reassurance, and every number must come from the app's own calculations.
- Other network calls only fetch data in: Apple Health is local; Hevy, Spotify and a lyrics lookup send only what they need, each behind a switch.

**Tier 2: an optional cloud model, off by default**
- A switch in Language model, with my own OpenRouter key stored in the Keychain.
- When on, it handles the text features: moment notes, Talk it through, Outlook, tone guesses, word suggestions, About me proposals, keep-or-release checks and Listen replies. With it off, the on-device model or fixed rules do the work.
- Names, places, organisations, emails, phone numbers, links, handles and long numbers are replaced on the phone before sending and restored on the phone after. Redaction is not perfect: it can miss an unusual name or a nickname.
- Requests ask providers not to store or train on them (`data_collection: deny`).
- Photos, photo and vibe captions, and media (Spotify, Netflix, YouTube) are never sent. Text that mentions self-harm is checked on the phone first and never sent.
- Details: `docs/20-cloud-model.md`.

## How it is built

- SwiftUI, SwiftData, Swift Charts, HealthKit, Vision, Speech, App Intents, iOS 26+.
- `Packages/AiHeartCore`: models, statistics, the outlook, parsers, export and backup, with about 280 unit tests on synthetic data.
- `App/`: the iPhone app.
- `docs/`: the product spec, data model, analytics, privacy rules and the research behind the design. `CLAUDE.md` holds the non-negotiable rules the app was built against.
- Built milestone by milestone with Claude Code.

## Building

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen).
2. Create `Config/Local.xcconfig` with your Apple team: `DEVELOPMENT_TEAM = YOURTEAMID`.
3. Run `xcodegen generate` and open `AiHeart.xcodeproj`.
4. To try it without your own data, add `-seedSamples` to the scheme's launch arguments.

This is a personal project, not an App Store product, and not a medical device.
