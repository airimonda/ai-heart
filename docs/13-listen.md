# 13 Listen (the listening tool)

## What it is
A quiet place to talk or type when she cannot journal but needs to get something out. It mostly listens. It does not give advice. Sometimes it offers a small next step (put a word on it, tap where she feels it, keep it, let it go). Everything happens on the phone.

Screens: `Listen`, `Listen, after`, `Listen, reflection`, `Listen settings`. Entry point: the "Cannot find the words?" row on Now. Setting: My rules > Listen.

## What it is not
- Not a therapist, a friend, a person, or a crisis service. **No persona, no name, no character, no relationship language.** The screens say "An AI on your phone."
- No memory of past sessions. Each session stands alone. Nothing is kept unless she chooses to keep it.
- No advice, diagnosis, labels, reassurance, interpretation of causes, or coaching.
- No raising the past or other people unless she does. Quiet topics are respected.

## What it knows about her (owner, 2026-11-02)
"Say it back" reads only her "How to talk to me" section from About me, for tone. It gets no facts about her and nothing from past sessions. "Help me sort it" reads neither.

## Why it is built this way
- The owner asked for something that listens, may suggest sometimes, and helps her let things out, without advice.
- Naming feelings has some support (see `docs/12-evidence.md`), but no research was found on an on-device listener.
- LLM therapy chatbots have shown stigma and missed crises in a 2025 study. So the model has a narrow job, a short leash, and a static safety page.
- A tool that is always available and agreeable can start to stand in for people. The design keeps it session-bound, persona-free and quiet, and keeps a path to the people she names on her Safety page. This is a design judgment, not a research finding.

## Session flow
1. **Listen.** Orb and a fading live transcript. The model says nothing while she speaks. Controls: Pause, I am done, Type instead. Safety page link always visible.
2. **After.** A sheet of offers: Say it back to me, Put a word on it, Where do I feel it, Keep it as an entry, Let it go, or Nothing. Just stop.
3. **Reflection (only if she asks).** "What I heard": a short reflection using her own words, plus "Does that fit?" She can correct it. Then Keep as entry or Let it go, or nothing.
If she does nothing, nothing is kept and the transcript is discarded.

## Sort it, and when it is heavy (owner, 2026-11-02)
She knows what to do once she can see it clearly, so Listen grounds rather than soothes. Offered on the After sheet:
- **Help me sort it** ("Laid out"): her words sorted into What happened, What I feel, What I already know. Every model line must pass the validators and be at least 75% her words, else a rule-based sort of her sentences is used. If she has not said what she knows, one fixed line asks "What do you already know about this?" It never suggests what to do.
- **Notes on this moment** (owner, 2026-11-04): under the sort, the same notes a let-go entry keeps (docs/16): how she reacted (thought, feelings, body, what she did), how strong it read, needs that seemed missing or met, what helped. Fixed lists and her checked words only. Shown for this session only; kept only if she then lets the session go (the notes stay with the let-go entry). Uses no About me and nothing from past sessions.
- **When it reads as heavy:** a fixed word list, never the model, shows one card after she stops: "It may be one for your therapist, or someone on a crisis line." It does not interrupt her. **Who I can reach** is always on the sheet, since a word list can miss. The self-harm stop below is separate and unchanged.
This is an owner exception to "no suggestions": the card points to people and never gives other advice, and Listen is still not a crisis responder.

## Behavior rules for the model
- Stay silent while she talks. Respond only when she taps, or (if she set "Sometimes" or "Often") after a long pause with a tiny non-intrusive line such as "Take your time." or "Anything else?"
- Replies are at most 2 short sentences. At most one question, and only occasionally. A question that separates a thought from the physical feeling in the body tends to land well for her ("Where does that sit in your body?").
- Offers are from a fixed menu, never invented advice. No imperatives ("you should"), no "have you tried".
- Reflection uses her words, shortened. The hedge about itself ("I may have it wrong") lives in the screen's fixed footnote, never in the reply and never about her. A reply must carry words she said, or it is replaced by the extractive fallback.
- Never label a state or condition. Never describe her as "manic", "depressed", "triggered", "dissociating" or similar.
- Never reassure ("it will be okay"). Never validate a blaming narrative or moral judgement; acknowledge the feeling without escalating.
- Do not mention people from her past or the past itself unless she does.
- Soft session length: if enabled, one gentle line once ("We have been at this a while. Want to stop here?"). Never repeat.

### Output validators
Reject and regenerate if the reply contains advice patterns, banned labels, reassurance phrases, more than two sentences, or more than one question. Fall back to silence or a fixed phrase.

## Something to try (docs/15)
A row on the after-sheet and on the heavy card. Fixed, evidence-labeled exercises chosen by the state she taps, with her notes from a steady day first. The model is not involved. The validator also rejects agreement and special meaning ("you're right", "it's a sign", "I am real").

## Safety
- Detect possible self-harm or suicide (lexical check plus classifier) continuously in the transcript.
- If detected: stop normal listening. Do not respond as a counselor. Show a calm, fixed screen with her **Safety page** (written by her), the people on it, and local crisis resources she has chosen. Offer to keep the transcript if she wants. **Never auto-release** it.
- The model must not try to talk her through a crisis.
- If she has not written a Safety page yet, show the prompt to create one when she first uses Listen, not mid-session.

## Privacy
- Speech to text on device (Apple's on-device speech recognition; verify language coverage for English and Japanese). No audio leaves the phone.
- The transcript lives in memory for the session. It is saved only if she chooses Keep as entry. Let it go uses the normal release rules.
- Recording (owner, 2026-11-02): live recognition dropped words after pauses. The session is now recorded to a protected temporary file, and the kept text comes from transcribing the whole recording after "I am done" (Apple's on-device SpeechAnalyzer, with the older on-device recognizer as a fallback). Owner, 2026-11-02 later: no live transcription at all. While she talks the screen shows only a timer and level bars (the orb is gone: it read badly in dark mode). After she is done, "What you said" shows the full transcript; she can fix words or Skip. The self-harm check runs on that full transcript before anything else, so the safety page opens after she finishes rather than mid-sentence. Keep and Let it go store the recording with the entry, so release purges it too. Nothing done or Close deletes it. Talk on Now works the same way: the voice note is kept and its words are added after she stops. While recording, the screen stays on, and a recording she started keeps going if the phone locks (background audio mode; the file stays writable only while open).
- No embeddings and no search index entries are created unless she keeps it.

## Anti-dependency and wellbeing guardrails
- No streaks, counts, or "you have not talked today" prompts.
- Optional, off by default: after a session, one line that offers a person from her Safety page to reach out to. She decides whether to ever show it.
- Optional weekly "Did talking here help?" check (yes, a bit, no). If the answer trends to "no", or sessions get very frequent, the app says so plainly and suggests a person or clinician. It never nags.
- Honest disclosure in the UI that it is an AI and can be wrong.

## Technical notes
- Speech: on-device recognizer with live partial results and voice activity detection for pauses.
- LLM: the same on-device model behind the `LanguageModel` protocol, with a short context window (this session only). Replies use a constrained prompt and the validators above.
- Optional text-to-speech replies (off by default).
- Works on iPhone, iPad and Mac. The Watch only starts a voice note.

## Evaluation
Log, locally and for her only: session length, which offers she chooses, and the optional "did it help" answers. No scoring of her words. Review with her after a month. If it increases rumination or dependence, change or remove it.
