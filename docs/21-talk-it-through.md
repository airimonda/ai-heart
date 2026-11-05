# 21 Talk it through

One current spec. Dated decisions are in History at the end.

## What it is
- A conversation she starts to think a hard moment through. Reflective, CBT-style questions and tentative reflections. It is not Listen (`docs/13`), not open chat, and not therapy.
- It speaks in a warm, plain voice (like Claude): "I" is allowed to show care ("I'm sorry that happened"), validation is allowed ("that makes sense"), a question only when it helps, short and gentle when she is very distressed. Suggestions only when she asks (one or two small options, nothing medical). Replies are at most 90 words (`TalkItThrough.maxWords`).
- Over a talk it helps her process the feeling one step at a time: notice and name it and where it sits in the body, understand the need or value under it, make room for it, then what she needs now or already knows.
- Replies come from the cloud model when it is on (`docs/20`) and from the on-device model otherwise. The screen says which.
- Entry points: a "Talk it through" row on Now (next to "Hard right now?"; hidden while Pause everything is on, because it needs typing), and a row in Listen's after-sheet, which opens the conversation with what she said in Listen as her first message. The Listen row is hidden when the Listen transcript tripped the self-harm check.

## Memory
- At the end of a talk she chooses: "Remember it" (the default), "Remember it and keep it in my journal", "Remember it, without the embarrassing parts" (offered when the talk reads as embarrassing; she picks sentences to take out and may type her own words instead, nothing is rewritten for her), or "Forget this one". Only her own words are remembered (`TalkMemory`, encrypted attribute, in the backup), never the app's replies.
- Memories are never deleted automatically. Each one is dated, and it counts for less as it ages: recency weight with a 90-day half-life and a floor of 0.15, so an old memory is never fully ignored.
- Later talks search memories on the phone like her notes. Each reply that used one shows a chip "From your talk: <date>".
- A mirror, not a personality: each reply may reflect one step beyond her words (the feeling under them, an unmet need, a gap between what she does and what she says she wants, or a link to her own earlier words, quoted with the date), said tentatively, then at most one question that lets her check it.

## About me
- Each request includes her full About me as context (lines with a quiet topic dropped, clipped to about 12,000 characters). With the cloud model on it is sent after redaction (names, places, organisations and contact details are replaced), so health and family details in it do travel. The model uses it only to understand her and pick better reflections. It may not quote it, raise anything from it she has not raised, or diagnose from it.
- After a remembered talk the model proposes up to three short first-person About me lines from her own words in that talk. Each passes the output checks, never touches self-harm or quiet topics, never names other people, and is added only when she taps Add (to the "noticed" section). Nothing is written into About me on its own.

## How the notes are found (on the phone)
`LocalRetrieval` (AiHeartCore):
1. **Documents.** For each kept entry with text: chunks of about three sentences, with the entry's date. For any entry (kept or resting) with a saved note: one document made from the note's one-line summary and the parts of it that are her own sentences. Plus her remembered talks. Never indexed: released entries, entries that mention self-harm (text, kept lines or note), sample (demo) rows, and any chunk that contains a quiet topic.
2. **Search.** Hybrid score: cosine similarity of Apple's on-device sentence embedding (`NLEmbedding`, in the language detected by `NLLanguageRecognizer`, English if unsure) plus BM25 over word tokens (`NLTokenizer`). Embeddings do not exist for every language (checked on this machine: English and Spanish yes; Japanese and Tagalog no), so BM25 alone stands in there. Vectors from two languages are never compared.
3. **Result.** Up to 4 passages above a minimum score, at most one per entry, each cut to 400 characters. The scale and bars were set by hand on a few synthetic pairs, not tuned on real writing; see Gaps.
4. The question for the search is her last two messages. The index is built when the screen opens and kept in memory only.

## What is sent, and what is not
- **Sent** to the model (cloud when it is on, `docs/20`): the instructions, the current conversation (the last 12 turns), up to 4 retrieved passages with their dates, and her About me. All of it is redacted on the phone first (`PIIRedactor`) and the reply is mapped back on the phone.
- **Never sent:** released, quiet-topic or self-harm entries; photos; voice recordings; health data; media history; the whole journal. Text that mentions self-harm is never sent: a message that tripped the self-harm check, and any earlier flagged message in the conversation, is left out of every prompt. A passage she removed with the "x" on its chip is not sent again.
- Each reply shows a chip for every passage the reply actually used ("From your notes: <date>" or "From your talk: <date>"). Tapping a chip shows the passage; the "x" (or long press) stops it being used for the rest of the conversation. Passages that were sent but not used are not shown.
- Message text is never logged. Only lengths and timings are.

## Safety (all on the phone, fixed words)
- Before any model call: if her message mentions self-harm (`SafetyCheck`, `ListenSafety.flags`), the model is not called. The safety page opens and a fixed card stays in the conversation. She can keep talking afterwards.
- If it reads as heavy (`ListenSafety.feelsHeavy`, `KeepOrRelease.readsHopeless`), the model is called as usual and the fixed "This looks heavy" card shows once.
- The safety page is always one tap away in the toolbar.
- Every reply is checked before she sees it (`OutputValidator`, `ListenRules.rejection`, `TalkItThrough.check`). Rejected: diagnosis and condition labels; promises ("it will be okay"); agreeing that a harsh belief about herself is true; special meanings or certainty about causes ("that's why you", "you always", "deep down you"); relationship talk ("I love you", "I'll always be here", "proud of you"); invented memories and quotes she did not say or that were not sent; a second question about her body; advice she did not ask for; asking for trauma details; replies over 90 words; more than one question. Tentative reflections ("It sounds like ...") pass; Listen's stricter interpretation filter does not apply here.
- A failed reply is asked for once more at a slightly higher temperature. Some failures can be repaired (`salvage`: drop an extra sentence, an invented quote or a repeated body question). After a second failure a fixed line stands in ("Say more about that, if you want. What feels most important about it right now?", then other fixed lines, never repeating one). If the model cannot be reached, the app says so; it does not make a reply up.
- Sessions are bounded: after 20 minutes or 30 of her messages, a fixed line (no model) offers to keep a note and stop, or to say one more thing. After that one more message is answered, then the conversation ends.
- If no model is ready the screen says so calmly and offers to write instead.

## What is kept
Only what she chooses (see Memory). "Remember it and keep it in my journal" saves an entry that is only her own words: what she types in "Add your own words", or, if she leaves it empty, what she said in the talk (turns that mention self-harm excluded). The model also writes 2 to 4 short notes about the talk, addressed to her as "you" ("You talked about ..."), describing only; they pass the output checks, are shown read-only, and are stored in the entry's note (`ReleaseNote.talkNotes`, optional, encrypted with the note), never as her text. The entry goes through the same checks as any entry. The app's replies are never stored.

History: 2026-11-04 the model wrote a first-person summary she could edit; 2026-11-05 replaced by notes about the talk plus her own words (owner: the model never writes in her voice).


## Why each guardrail
| Rule | Evidence | Strength |
|---|---|---|
| Never agree with a harsh belief; ask what makes it feel true and what does not | In 2,405 people, one sycophantic AI reply made people more sure they were right and less willing to repair a conflict; they also preferred the agreeable AI (Cheng et al., Science 2026). | Moderate |
| No persona, no relationship, no special meaning, no promises | Replies that endorsed delusions or showed romantic interest were followed by longer conversations in logs of harmful spirals (Moore et al. 2026). | Limited, consistent |
| Memory limited to her own words, dated and fading; a bounded session with a soft stop | Safeguards weaken over long multi-turn chats (Moore et al. 2026). | Limited |
| Short sessions, one question at a time, no open-ended companionship | Heavier daily chatbot use went with more loneliness and emotional dependence (MIT Media Lab and OpenAI 2025; correlational, preprint). | Limited |
| A narrow, purpose-built job with fixed safety rails, rather than open chat | A randomized trial of a purpose-built generative chatbot (Therabot) in adults with symptoms of depression, anxiety or eating concerns found larger symptom reductions than a waitlist over four weeks (Heinz et al., NEJM AI 2025). It was a different system, run with clinician oversight, compared with no treatment; it does not show this app helps. | Limited (one trial, waitlist control) |
| Reflective questions, not advice | Core CBT questioning (what happened, what went through your mind, what you felt, what you needed) is a standard part of the approach; here it is used without any claim that this is therapy. | Design judgment |
| Never ask for details of a traumatic event | Single-session debriefing soon after a hard event did not help and may harm some people (Cochrane, Rose et al.; see `docs/15`). | Moderate |
| Notes shown as chips, removable, only on her request | Transparency and choice (SAMHSA principles, `docs/15`). Also the only way she can see what left the phone. | Framework |

Sources were found by web search on 2026-11-04 and mostly read as abstracts or summaries, not full papers. Check them before relying on a number.

## Gaps
- No study tests this in an app like this. The Therabot trial is the closest and differs in design and oversight.
- Retrieval quality is unmeasured. The embedding and BM25 bars were set by hand on synthetic text. A passage can be related in words and still wrong in meaning, and the chips are how she catches that.
- Redaction can miss an unusual name (`docs/20`). Retrieved passages are her own writing, so a passage can carry details the redactor does not recognise.
- The checks are keyword lists and will miss rephrasings. They are a net, not a guarantee. The system text asks for no advice, but a model can still drift.
- English-only fixed lines (fallback, wrap-up). The model is asked to reply in her language.
- Memory recency weights (90-day half-life, floor 0.15) are a design choice, not tuned.
- Review after a month of use (date not yet set): is it used for a hard moment and then closed, or does it feed checking and dependence? If the second, change it.


## History
- 2026-11-04, the ask: talk a hard moment through with reflective questions; "RAG-style, but the source docs are local"; her kept entries and saved notes are searched on the phone, only the top few passages leave it, redacted. First version: no memory, no "I", no feelings, under 60 words, no "that makes sense", an AI said plainly on the screen.
- 2026-11-04, later: "A memory, not a personality, just a mirror", "like a therapist that holds up a mirror in front of me", and "it should help me process my feelings better". Added Remember it, the mirror and the step-by-step processing. Basis: complex reflections and developing discrepancy in motivational interviewing; Socratic questioning in CBT; affect labeling (Lieberman et al. 2007); emotion-focused therapy's steps of attending, naming, exploring the need and transforming (Greenberg). Strength Limited to Moderate in self-guided form.
- 2026-11-04, About me: she chose "Full About me" as context, and "Talk it through should remember past chats, so About me should be updated" (proposals, each added only by her).
- 2026-11-04, later: "I like how Claude talks to me during hard moments." The model underneath was already Claude Sonnet; the earlier rules made it sound unlike Claude. She chose Claude's own voice with safety rails (see What it is). Trade-off accepted knowingly: docs/15 notes that warmth and personalisation are part of the proposed mechanism behind AI-linked spirals; the remaining rails are the guard.
- 2026-11-05: cloud scope is all text features, never photos, media or self-harm text (`docs/20`). Memories fade with age (90-day half-life, floor 0.15) but are never deleted. Self-harm text is never sent.
