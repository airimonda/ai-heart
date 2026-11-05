# 09 Open questions and things to verify

Check these yourself where you can; ask the owner for the rest.

## To verify (technical)
1. HealthKit identifiers and the Medications API (availability, iOS version, authorization). Cycle types available.
2. Qwen3-VL 4B on the owner's phone through MLX Swift LM: tokens per second, peak memory, heat. Which iPhone exactly.
3. Whether Foundation Models guardrails refuse the owner's kind of text (informs the "not Apple's model" decision).
4. Decided: Apple `NLEmbedding` plus BM25 for local retrieval (`docs/21`).
5. Hevy API: current terms, pagination, the events endpoint for incremental sync, rate limits.
6. Strava: the current API Agreement and policy, especially AI use, caching, and display limits.
7. Whether a free developer account is enough for HealthKit on her own device (re-signing every 7 days) or a paid account is needed. The iCloud and CloudKit capability very likely needs a paid Apple Developer account; verify.
8. HealthKit availability on iPad and on Mac. As far as we know it is not available to third-party apps on Mac, so the iPhone and Watch act as the sensor hub and other devices receive synced summaries. Verify.
9. That photo and audio payloads are covered by cloud encryption; if not, encrypt the files yourself before storing.

8b. Netflix: whether its terms allow even the optional in-app sign-in, and which export columns she has. Screen Time: the Family Controls entitlement and the reliability of threshold events on the owner's iOS version. Apple Music and MusicKit terms on using listening data in analysis; Google Data Portability availability in the owner's country, its restricted-scope verification, and its terms on AI use; Spotify's current terms.

## To decide with the owner (DECIDE)
- Backup and sync: with sync on, the data also lives in her iCloud. Does she want to keep excluding the local store from device backups?
- Does she want to turn on iCloud Advanced Data Protection (recommended with sync)?
- Which attributes are encrypted. This cannot be changed after the first production deploy of the CloudKit schema.
- Language mix for the LLM voice (English and Japanese) and Japanese-specific word suggestions.
- Whether the Watch Today screen should show the outlook.

## Newly open (2026-11-05)
- Does `data_collection: deny` really keep prompts from being stored? Check with OpenRouter.
- How well does redaction work for names in the languages she writes in?
- Cost of the cloud model per month of normal use.
- Retrieval score bars and the Talk it through memory weights are hand-set; tune on real use.
- Date for the one-month Talk it through review.
