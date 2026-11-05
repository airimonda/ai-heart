# 19 Ask first, guessed mood, model choice

Three changes. Strength labels follow `docs/12-evidence.md`.

## Ask first, hold to let go
Before, an entry that read as hard was let go automatically (resting first). Now, by default, AiHeart asks.
- After a save that the rules call a hard entry, a sheet says "This one was hard. Let it go?", repeats the promise ("AiHeart keeps short notes on how you reacted and what helped"), and offers two equal choices: a large "Hold to let go" control (press and hold about 1.5 seconds, a ring fills, lifting your finger stops it) and "Keep it". Swiping the sheet away keeps it.
- Holding runs the same steps as the old automatic path (`AutoDecide.perform`): numbers kept or not as her setting says, rest days, notes written before the text is purged when "gone at once" is on, otherwise written while it rests. It is recorded as her doing, not automatic.
- The same hold control now sits behind the manual "Let go" on an entry and Listen's "Let it go" buttons.
- VoiceOver gets a normal button labelled "Let it go", because holding is hard with it. With Reduce Motion the ring fills in four steps instead of sweeping.
- "Ask me first" in How it decides turns this off. Off means the earlier automatic let-go.
- Never offered, as before: entries about self-harm (safety page opens) and hopeless typed entries (kept in full, fixed heavy card).

Why: Briñol et al. 2013 (Psychological Science) found that physically discarding written thoughts reduced their influence on judgments, while only imagining it did not. The research tested an act by her own hand, so the app asks and she acts. Strength: Limited. One paper family, evaluations of an unrelated target, not a clinical outcome.

## Mood guessed from long writing
- On the feeling screen, when she has written 40 words or more (or 120 or more Japanese or Chinese characters), the mood pad stays but is marked "Optional. You wrote a lot; AiHeart can guess from your words."
- After saving an entry with that much text and no mood point, the on-device model rates it (the same tone prompt that colours cards) and the result becomes the entry's mood point, marked `moodGuessed`. Only for entries saved from now on; older entries are not touched. If the model is not on the phone at that moment, nothing is set and the card colour comes later as before.
- On the entry, a small line says "AiHeart's guess from your words: ...". "Fits" keeps the values and removes the mark. "Change" opens the pad; her touch removes the mark.
- The mood map draws guessed points hollow. Charts that average a day are left as they are.
- A guess never decides keep or let go: the rules read only what she tapped.

Evidence: none. Nothing here has been checked against how people rate their own mood, so guessed points are marked, and they are kept out of outlook training. Treat them as a convenience, not a measurement.

## Choice of model
Settings, Language model, has a picker.
- Qwen3-VL 4B Instruct 4-bit (`lmstudio-community/Qwen3-VL-4B-Instruct-MLX-4bit`), about 3.1 GB. A 4B dense model that also sees images. Default and the only model in use (owner, 2026-11-05). Gemma 4 E2B and Qwen3 8B are no longer used; the choice below is kept as history.

Only one is in memory at a time: switching unloads the old one first. The old files stay until she taps "Remove the other model's files". Each model has its own folder named after its repo (`Models/gemma-4-e2b-it-4bit`, `Models/qwen3-vl-4b-instruct-mlx-4bit`), so either can be copied from a Mac with `devicectl`. Both are used the same way, including prompts with a photo. The choice is stored on the device (the files are per device) and mirrored in `AppSettings.modelChoice`. Nothing about her leaves the phone with either model.

Not tested on a phone yet: Qwen3-VL 4B speed, memory and whether the existing reply checks suit its wording.
