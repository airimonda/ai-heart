# 04 Integrations

All integrations only bring data **in**. Nothing from the journal or body data is sent to any provider. Tokens and keys live in the Keychain. A Connections screen (19) lets her connect, disconnect and see what each source provides. Define small protocols (`SignalProvider`, `ActivityProvider`, `ImportProvider`) with capability flags, including `aiEligible: Bool`.

## Apple Health (primary)
Read with granular per-type permission. Use anchored object queries plus `HKObserverQuery` with background delivery where useful. Handle timezones and de-duplicate by sample UUID.

Types to read (verify exact identifiers in current Apple docs):
- Sleep analysis (core, deep, REM, awake)
- Heart rate, resting heart rate, HRV (SDNN), respiratory rate
- Apple sleeping wrist temperature
- Steps, active energy, basal energy, exercise minutes
- Workouts (type, duration, energy, average heart rate) and heart rate samples within them
- Menstrual flow (and related cycle category types if she uses them)
- Medications and dose events (introduced in recent iOS versions; **verify availability and API shape**)
- Body mass (optional, for context next to labs)

Write (optional, off by default): State of Mind (iOS 18+) so her mood entries appear in Health.

The Watch writes most of this to Health. No separate Watch sync is needed except the capture app and complications, which use WatchConnectivity and shared SwiftData or a lightweight queue.

## Hevy (strength detail)
Why: Health has duration, heart rate and calories for a lift, but **not sets, reps or weights**. Hevy has them.
- Hevy has a public REST API at `api.hevyapp.com` (docs at `/docs`). It requires a **Hevy Pro** subscription; the user creates an API key at `hevy.com/settings?developer`.
- Auth: the key goes in an `api-key` header. Store in the Keychain.
- Resources seen in client libraries: workouts (list with page and page size, get, count, events for syncing), routines, routine folders, exercise templates, exercise history, user info. Use read-only calls.
- Sync on foreground and once daily. Use the events endpoint if it supports incremental sync; otherwise page by date.
- Map to `Workout` plus `HevySet`. Match to the HealthKit workout by overlapping time (for example plus or minus 10 minutes) and keep both: Hevy supplies sets, Health supplies heart rate and calories.
- Read the current Hevy API terms before building.

## Strava (display only)
Research notes (verify against Strava's current API Agreement and policy before building):
- OAuth 2. Read scopes only (`read`, `activity:read`; avoid `activity:read_all` unless she needs private activities).
- Strava's current API policy was reported to **prohibit using API data in AI applications**, including prompts, embeddings and retrieval, and to cover derived and anonymized data. It was also reported to limit caching to about 7 days and to restrict display to the contributing user. A new app was reported to start with access for one athlete (upgradable to ten), which is fine for a personal app.
- Rate limits were reported as about 200 requests per 15 minutes and 2,000 per day per app. Verify.

Therefore:
- Mark every Strava record `aiEligible = false`.
- Never feed Strava data to the outlook model, Insights statistics, embeddings or any LLM prompt.
- Show it only on her own Today and Journal lists, cache at most 7 days, and do not include it in exports by default.
- Alternative that avoids all of this: if she records with the Apple Watch, those workouts already arrive in Apple Health. Ask her whether she needs the Strava API at all. **DECIDE.**

## Imports from files (ImportProvider)
- Lifting app CSV exports (other than Hevy).
- YouTube history exports (Google Takeout), parsed on device.
- Netflix viewing activity (Download all on netflix.com), parsed on device. See `docs/14` for the optional, unofficial sign-in method.
- Journal from Markdown.
Parse locally. Never upload.

## Other signals (later)
- App-open counts for social or media apps through Shortcuts personal automations that call an App Intent (no special entitlement).
- Apple Music recently played through MusicKit.
- Not feasible on iOS: reading Screen Time per app into your own database, or seeing what other apps display. Do not use screen recording.
- Spotify: connected for counts and times only and kept out of analysis (see `docs/14`).

## Errors and privacy
Back off on rate limits. Show a calm "could not reach [provider]" note, never a red banner. Provide Disconnect, which deletes the token and the provider's cached data.

## Lyrics lookup (owner, 2026-11-02)
lrclib.net `GET /api/get?track_name=&artist_name=`, no key. Used only for the week's media vibe line, only for her Spotify songs (live, at her request against Spotify's developer terms, or exported), behind the "Use lyrics for the vibe" switch in Sources. Sends title and artist only; lyrics are kept in memory for one read and never stored. The site therefore sees which songs she looks up.
