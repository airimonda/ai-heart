# 03 Analytics and the on-device LLM

## Principle
**Statistics are computed in code. The LLM only explains numbers the code produced.** The LLM never sees raw logs, never does the analysis, and every number in its output must match a field in its input.

## Baselines
- Rolling 28-day median and MAD per signal, per user. Never population norms.
- Cycle-adjusted baselines once at least 3 cycles exist (resting HR rises and HRV falls on average after ovulation; wrist temperature steps up). Before that, use the global baseline and label it.
- Reset or flag baselines at life events (move, travel) and for about 6 weeks after a dose change.
- Missing data is informative. Do not impute. Show denominators ("[7] of [9] days").

## Cycle engine
- Start from menstrual flow in HealthKit. Estimate ovulation from the sleeping wrist-temperature shift when available, otherwise by calendar. Mark estimates as estimates.
- Phases: period, follicular, fertile window, luteal. Show day n of N.
- Cycle effects on mood differ widely between people. Show general expectations only labeled as general; replace them with her own cycles as data accrues.

## Insights (Patterns tab)
- A small, pre-specified set of hypotheses (about 6 to 10), not all pairs.
- Lags: test same day and next day.
- Rank correlation with block-bootstrap intervals (autocorrelation matters). Show intervals, not p-values. Gate with minimum paired observations (for example 14).
- Charts: mood by cycle phase (bars with whiskers and n), sleep against next-day mood (scatter, trend, band), lifting days and mood, training load with HRV (8 weeks), and a forest plot of signals against next-day mood. Pale means unclear.

## Mood outlook
- Target: next-day (and 3-day) valence and arousal.
- Features: last night's sleep, HRV z, resting HR z (cycle-adjusted), cycle day and phase, recent training load, days since a dose change or lab shift, weekday.
- Model v0: ridge regression with strong shrinkage toward her recent mean. Predictive interval by quantile or bootstrap. Refit on device, in the background when charging.
- **Honest evaluation:** time-series cross-validation. Always compare with two baselines: "same as yesterday" and 7-day mean. Show the track record and say "Not yet" until the model beats both with a margin.
- Wording is always a lean, never a prediction. Provide a switch to turn it off.

## Body balance
Weekly signed index: weighted lower-side minus higher-side symptoms from the weekly check, plus cycle-adjusted Watch z-scores (resting HR, HRV, wrist temperature, sleep). Mark dose changes and labs. Treat the weeks after a change as lagged. Never suggest a dose. Flag when a mood shift coincides with a dose change or lab shift so she can show both to her doctors.

## The LLM
Default on-device model: Qwen3-VL 4B, 4-bit, through MLX Swift LM, behind a `LanguageModel` protocol (`docs/19`). Gemma is no longer used. Run on demand only, never in the background; watch heat and memory.

Not Apple Foundation Models for the journal: its on-device context window is small (about 4,096 tokens in what we found), its guardrails can refuse emotionally intense but legitimate text, and image input depends on a newer OS. It may be used later for small non-emotional tasks.

Optional cloud model: off by default, her own OpenRouter key, redacted on the phone, never photos, media or self-harm text. See `docs/20` and CLAUDE.md #2.

### What the LLM does
1. **AiHeart's read** and answers to "Ask about it" (outlook, patterns). Input: structured JSON of findings (variables, effect, interval, n, confidence, drivers). Output: 3 to 5 plain sentences.
2. **Words for a photo** (multimodal): offers three words. She accepts, edits or ignores.
3. **Help me find the words:** offers feeling words from her own vocabulary.
4. **Keep or release** (below).

### Output validation
- Every number must appear in the input JSON. Reject and regenerate otherwise.
- Banned unless she wrote them first: mania, hypomania, bipolar, psychosis, depressive episode, disorder, diagnosis, and any medication or dose advice.
- No advice unless she asks, and then only from her own history ("what changed it before"), never what she should do.
- Low temperature. Max length. No reassurance phrases. Voice: see `seed/about-me.private.md` (calm, direct, grounded, an intellectual peer).

### Retrieval
Local embeddings of kept entries (Apple `NLEmbedding` plus BM25; `docs/21`). Retrieve a few entries only when she asks something like "have I felt this before?". Respect Quiet topics. Delete embeddings when an entry is released. Strava data is never embedded.

## Automatic keep or release
The owner asked the app to decide. Implementation:

1. **Classify** each saved entry using: mood point at save, chosen word, and LLM theme labels. Default is **keep**.
2. **Release only if** the entry is confidently hard (valence clearly low AND negative-narrative content AND confidence at least 0.8). Unsure means keep.
3. **Never release** an entry that mentions self-harm or suicide (lexical check plus LLM check). Keep it and open her Safety page.
4. **For a released entry, keep only extractive spans** (sentences already in her words) tagged as: what helped, what she needed, what she learned, a strength or value, or a next small step she named. Never rewrite and never restate painful details. If nothing qualifies, keep only the numbers.
5. **Always keep the numbers** (mood point, body map, vitals) unless she turns that off in settings.
6. **Rest** the entry for 7 days (hidden, restorable), then purge. Settings: 7 days, 3 days, or gone at once.
7. Show the result after Save (22): "Kept in your journal" or "Let go, gently" with Undo.
