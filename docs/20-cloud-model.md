# 20 Cloud model (OpenRouter)

## Current contract (owner, 2026-11-05)
The cloud model is optional and off by default. With the switch on, it handles all the text features: moment notes (`docs/16`), Talk it through (`docs/21`), Outlook, tone guessing, word suggestions, About me proposals, let-go and after-save checks, and Listen replies. With the switch off, everything uses the on-device model (Qwen3-VL 4B) or fixed rules.

Never sent to the cloud: photos, photo and vibe captions, media (Spotify, Netflix, YouTube), and any text that mentions self-harm. Her own text is checked first on the phone. Flagged text, including an earlier message or entry that would otherwise travel with it, is handled on the phone or by fixed rules.

Rules: CLAUDE.md #2. Rule 6 still holds: photos and media are never sent.

## What is sent, and what is not
- **Sent (text features only, when the switch is on):** the prompt the feature already builds (her entry or conversation, with the fixed instructions), after redaction. For Talk it through that includes retrieved passages and her About me (`docs/21`). Outlook sends facts derived from her logs, not raw health data.
- **Redacted on the phone first** (`PIIRedactor`): names of people, places and organisations (Apple's on-device NLTagger; strongest in English, weaker for Japanese and Tagalog names), emails, phone numbers, links, @handles, and runs of six or more digits. Each becomes a placeholder such as `[PERSON_1]`; the same person keeps the same placeholder within a request. The reply is mapped back on the phone.
- **Kept as written:** feelings, ages and amounts. Family words such as "Mama" are kept. Dates written with six or more digits are caught by the digit rule.
- **Never sent:** photos, photo and vibe captions, media (rule 6), anything that mentions self-harm, voice recordings, and the whole journal.
- **Provider routing:** `data_collection: deny`, so OpenRouter only uses providers that state they do not store or train on prompts. This filters on stated policy. It is not a guarantee of zero retention. Each request is tied to her OpenRouter account and key.

## How it works
- Language model screen: "Use a cloud model (OpenRouter)", her API key (stored in the Keychain, this device only), and a model chosen from OpenRouter's live list (default: the newest Claude Sonnet). "Test the connection" sends a one-word prompt.
- The cloud is used for a request only when the switch is on, a key is set and a model is chosen, and only for text features. Photo and media features always use the on-device model.
- On-device model: Qwen3-VL 4B is the default and the only one in use. It handles everything when the switch is off, and photos and captions always. Gemma 4 E2B and Qwen3 8B are no longer used (`docs/19`).
- Without a connection, the built-in rules stand in.
- Every reply still goes through the same parsing and output checks (labels, advice, reassurance, quiet topics, numbers). Self-harm keyword checks run on the phone before any model is asked.

## Known limits
- Redaction is pattern- and tagger-based. It can miss an unusual name or a nickname, and it cannot remove details that identify her by their content (for example a rare life event). The switch and this page say so.
- Rule 7 cannot reach copies a provider keeps.
- Each moment note makes several short requests (the pipeline was built for small models). Cost per entry is small but not zero.

## History
- 2026-11-04: the owner chose a cloud model after the on-device models (Gemma 4 E2B, Qwen3-VL 4B, Qwen3 8B) misread context in long or mixed entries, and Qwen3 8B ran the phone out of memory on a long entry (iOS closed the app at about 5.5 GB). Scope at that time: notes, checks, Listen and other text features.
- 2026-11-05: scope confirmed as all text features. Never sent: photos, captions, media, self-harm text. Default on-device model fixed as Qwen3-VL 4B.
