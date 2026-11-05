# 14 Automatic sources and media

## Goal
The owner finds manual tracking hard to keep up. AiHeart should **fetch everything it can on its own**, and be honest about what cannot be automated. Nothing on the Sources screen needs her to log anything. Entries (a photo, a word, some writing) are optional extras; the outlook and Insights work from passive data alone.

## Principles
- **Passive first.** Collect in the background. No required daily input.
- **Quiet failure.** Sources never send notifications. A broken connection is shown once on the Sources screen in calm words.
- **Weekly framing for media.** Show media as "this week", never as a live counter, to avoid a checking loop.
- **Own the data.** Fetch into the device. Do not route her data through third-party aggregators.
- **Respect each provider's rules,** including their limits on AI use. Respecting them changes what the data can be used for.

## Source tiers
| Source | How it arrives | Automatic? | Used in outlook and LLM? | Notes (verify before building) |
|---|---|---|---|---|
| Apple Health and Watch | HealthKit background delivery | Yes | Yes | Sleep, heart, HRV, respiration, wrist temperature, steps, energy, workouts, cycle, medications |
| Hevy | Hevy API key (needs Pro), daily sync | Yes | Yes | Sets, reps, weights. Check Hevy's API terms |
| Apple Music | MusicKit recently played | Yes (verify) | Verify Apple's terms | Needs an Apple Music subscription |
| New photos | PhotoKit with limited or full access; optionally the Journaling Suggestions picker | Offers drafts; she keeps what she wants | Yes, only photos she keeps | The picker is a system UI: the app receives only what she selects, and it is not a bulk feed (iOS 17.2+, iPadOS 26+, needs an entitlement) |
| Spotify | Web API (recently played) after one sign-in, or her own data export | Yes via API | **No.** Display only | Spotify's developer terms prohibit training or otherwise ingesting its content into ML or AI models. Audio features and recommendations are deprecated for new apps (Nov 2024) |
| Strava | OAuth | Yes | **No.** Display only | See `docs/04` |
| YouTube | Google Data Portability API, resource group `myactivity.youtube` | Weekly after consent (verify) | Verify Google's terms | The scope is "restricted" (app verification applies); available only in some countries; creates an archive job. For a personal app in testing mode, token lifetimes are short. Alternative: Google Takeout export imported from Files |
| Netflix | **No official API.** Method A: she downloads "Viewing activity > Download all" from netflix.com and shares the file to AiHeart. Method B (optional, off by default, unofficial): a web view where she signs in herself, and the app triggers the same download or reads the page in her own session | A: import now and then. B: on demand | Her own data; verify terms | The quick download may have titles and dates only; Netflix's full data request can include times and durations (verify). Method B may breach Netflix's terms and can break; never store credentials; the page is Netflix's own and the session stays in the web view |
| Screen Time (iPhone) | Apple's Family Controls, Device Activity and Managed Settings frameworks, individual authorization | Limited | Only coarse threshold counts | Apple renders usage in a sandboxed report extension that the host app cannot read (writes and network are blocked), so per-app detail cannot be fetched. Monitor extensions can report threshold events (for example a category passing an hour), but these have been unreliable in recent iOS 26 releases. Needs the Family Controls entitlement. App and category identities are opaque tokens |
| App activity (Mac) | A native Mac app can observe which app is frontmost and for how long (workspace notifications) | Yes (verify) | Verify | Stays on the Mac. No window titles unless she grants Accessibility. Android's Digital Wellbeing is a different system and is not part of this project |
| Social aggregators such as Shelf | Not integrated | n/a | n/a | They connect by logging in to platforms and are social products; AiHeart should not send her media history through them |

Policy flag: sources marked display-only carry `aiEligible = false` and must never reach the outlook model, statistics that feed it, embeddings or any LLM prompt.

## Screen Time and app activity
She asked whether the app can fetch which apps she uses, as Apple's Screen Time does. On iPhone, Apple deliberately keeps this out of reach: the usage report can be shown inside the app, but the app cannot read the numbers, and a workaround that extracts them from the report extension must not be used. The supported signal is coarse threshold events from a Device Activity monitor extension, which needs the Family Controls entitlement and has been flaky on iOS 26. The Mac does not have this restriction for app-in-front activity. Use the shortcut-based app-open counts from `docs/04` as the iPhone fallback.

## What counts as a media signal
Only counts and times, never judgments about content:
- Hours per day by type (music, video, podcasts)
- Time-of-day pattern, and a **late-night window** (for example midnight to 5 am)
- Replays: how often one track returns
- Optional, only where terms allow and computed on device: simple title-based tags. Never send titles to a cloud service

## Evidence for media as a mood signal (see `docs/12-evidence.md`)
Limited and mostly correlational: more repetitive listening and sadder-tagged music in people at higher depression risk; late-night binge viewing linked to poorer sleep through pre-sleep arousal. People also choose media to match or change their mood, so the direction can run either way. Show it as a hint with uncertainty.

## Background execution
- HealthKit: observer queries and background delivery.
- Hevy, Apple Music, Spotify, Strava: background app refresh and processing tasks, with backoff on rate limits. Respect each provider's request limits and caching rules.
- Imports: parse on device, de-duplicate, keep only what the app needs.
- Tokens in Keychain. Disconnect deletes the token and that source's cached data.

## Screens
`Sources` (replaces Connections), `Media`, the Media card on Insights Today, the quiet photo suggestions row on Now. iPad and Mac versions exist for Sources and Media.
