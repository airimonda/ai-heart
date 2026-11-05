# 16 Moment notes (kept from an entry, shown for a let-go entry)

Current format: version 3. Older versions are described under History at the end.

## What a note holds (version 3, owner 2026-11-05)
"Just summaries, and some direct lines if they're really helpful." A note is laid out like a careful clinician's session note.

| Part | What it holds | Who writes it |
|---|---|---|
| What happened | One neutral line, under 12 words, no painful detail | The model (see Who writes notes), checked; dropped if it fails |
| One summary line per part | For each part she wrote about (trigger, thought, feeling, body, what she did, what it gave her, what it cost, what she wants, what helped; or, for long reflective entries, what hurt, what she longs for, what she is proud of, what she understands now, other people) | The model, one short line each, checked |
| In your words | At most two of her own sentences worth keeping word for word | Picked by the model, copied whole, checked against the entry |
| Feelings | From a fixed list of 22 words (pleasant and unpleasant) | Model picks, code checks |
| How strong it read | Mild, strong or very strong, with the sentence that shows it | Model or rules; dropped without her words behind it |
| Your mood point | Her own tap on the mood pad, in words | Code, from her tap only |
| Needs that seemed missing or met | Up to three needs from a fixed list of nine, each with her words | Model picks, a strict yes/no check must agree; or rules |

Underneath, her sentences by part (`parts`) are still stored on kept entries. They feed the honest affirmations, the therapist PDF and Talk it through retrieval. They are not shown as the note itself.

## What each entry state keeps
| State | What the note keeps |
|---|---|
| Kept | The full v3 note, including "In your words" and the sentences by part |
| Resting (let go, waiting out the rest period) | A note is written while it rests. The retelling is purged at the end of the rest |
| Let go (after the rest, or "Gone at once") | Summary only: the what-happened line, feelings, how strong it read, and which needs seemed met or missing. Never her exact lines: not the "In your words" lines, not the quotes, and not the "kept lines" from older versions, even after the purge. Notes on entries let go earlier are reduced the same way at the next launch |
| Released (gone) | Nothing, except what a purge rule keeps (`docs/06`) |
| Deleted | Held 30 days in Recently deleted (`docs/22`), then gone |

## Who writes notes
Moment notes use the cloud model when she has switched it on (`docs/20`, CLAUDE.md rule 2). Otherwise the on-device model (Qwen3-VL 4B) writes them, and with no model the rules write notes from the same fixed lists. Model notes are merged with rule notes so gaps fill in. Text that mentions self-harm is never sent to the cloud, and an entry saved with the self-harm outcome gets no model-written note.

## Rules (unchanged non-negotiables)
- On the phone by default; cloud only as above (CLAUDE.md #1, #2).
- Describe, never prescribe (#3): no advice, no diagnosis, no state labels, no reassurance. Every model line goes through `OutputValidator`.
- The model never invents a feeling or a need: both come from fixed lists in `ReleaseNote.swift`.
- Every direct quote must be at least 3 in 4 words from what she wrote (`ListenSort.isHerWords`) and at most 16 words. At most two are kept.
- "What happened" may not contain any hard-retelling word (`KeepOrRelease.hardNarrative`) or self-harm term.
- Quiet topics never appear.
- Self-harm in any note blocks release (`SafetyCheck.mentionsSelfHarm(entry)` reads the notes too).
- Bring it back clears the notes, as it clears kept lines.


## Evidence for each part
Strength labels as in docs/12.

| Part | Basis | Strength | Caveat |
|---|---|---|---|
| Situation, then the reaction split into thought, feeling, body and behaviour | The five-part model used in cognitive behavioural therapy (Padesky and Mooney 1990; Greenberger and Padesky, *Mind Over Mood*). Standard way clinicians write down a reaction. | Moderate as a clinical structure | It is a teaching and formulation tool, not a tested intervention by itself |
| Naming the feeling from a list | Putting feelings into words lowered amygdala response (Lieberman et al. 2007). Finer emotion differentiation goes with better coping (Kashdan, Barrett and McKnight 2015). | Limited to moderate | Lab and correlational. A fixed list can anchor her; she can bring the entry back if it is wrong |
| Notes written as a separate record, not a retelling | Self-distancing (looking at an experience from a step back) reduced distress and rumination compared with immersed recounting (Kross and Ayduk 2017, review). | Moderate (lab) | Studied as a way of reflecting, not as a stored note |
| Needs: connection, choice, feeling capable | Basic psychological need theory, part of self-determination theory: relatedness, autonomy and competence (Ryan and Deci 2000; Vansteenkiste, Ryan and Soenens 2020). Need frustration predicts ill-being across many studies and cultures. | Moderate to strong for the theory | Measured with questionnaires, not inferred from diary text |
| Needs: safety, being understood, room to express feelings, ease and play, fairness | Core emotional needs in schema therapy (Young, Klosko and Weishaar 2003), reformulated by an international workgroup that added fairness and self-coherence (Arntz, Rijkeboer et al. 2021, *Cognitive Therapy and Research* 45:1007-1020). | Limited to moderate | Largely a clinical theory; the 2021 paper is a position paper |
| Being understood as a need | Invalidating responses raised negative affect, heart rate and skin conductance compared with validating ones (Shenk and Fruzzetti 2011, *J Soc Clin Psychol* 30:163-183). | Limited (one experiment) | Lab stressor, students |
| Rest as a need | Sleep loss raises negative mood and anxiety and weakens emotion reading and regulation (Ben Simon, Vallat, Barnes and Walker 2020, *Trends Cogn Sci* 24:435-450, review). | Moderate | Mostly experimental sleep deprivation |
| "How strong it read" as three words, not a number | Subjective distress is normally self-rated (SUDS, Wolpe 1969). A model cannot rate it, so the app only says how strongly she wrote, with her words, and shows her own mood point next to it. | Design judgment | The read can be wrong; the card says so |
| Picking needs or feelings from text at all | **No research found** on an app inferring unmet needs from diary text. | None found | Treat as experimental. Every pick shows her words so she can judge it |

Verified this session (2026-11-04): the Arntz 2021, Shenk and Fruzzetti 2011 and Ben Simon 2020 citations (journal, volume, pages). The others are standard references not re-fetched.

## Where the notes show
- Resting and let-go entries (`ReleaseNoteCard`).
- Listen, "Help me sort it": under the three-line sort, for that session (docs/13). Letting the session go keeps them.
- Export, "For a therapist" PDF: section "Notes on hard moments" (switch on by default), with a count of the needs that seemed missing most often and the feelings named most often, then each note by date. Notes from released entries appear here even though released entries are otherwise left out of that report; the entries themselves and their counts still are not.

## Where it lives
- `Packages/AiHeartCore/Sources/AiHeartCore/ReleaseNote.swift`: lists, prompts, parsing, checks, rule-based notes.
- `App/Sources/KeepOrReleaseViews.swift`: `ReleaseNoteWriter` (several short model calls, one question each, while the entry rests; before purge when the rest is "Gone at once") and `ReleaseNoteCard`.
- Stored as `Entry.releaseNoteJSON` (optional, encrypted attribute, in the backup).
- Tests: `ReleaseNoteTests.swift` (synthetic text only).

## Notes on kept entries too (owner, 2026-11-04)
Kept entries that are a real piece of writing (25+ words, 75+ Japanese or Chinese characters) or tell a hard story get the same notes right after saving. They show on the saved sheet ("See notes on this moment"), on the heavy sheet, and on the entry. Older entries offer "Write notes on this moment". When a model is available it is also asked whether a kept hard entry sounds hopeless or at the limit; yes keeps it and shows the fixed heavy card. A wrong yes only keeps an entry.

## History

### Version 1 (2026-11-04)
A let-go entry used to keep only sentences that matched a short list of cue words ("helped", "I need", "next time"), often one line or none. Version 1 kept short notes in a fixed layout (what happened, thought, felt, body, urge, strength, needs, what helped), with the model picking and code checking each quote.

### Owner, 2026-11-05: summary only for let-go entries
The notes for a let-go entry keep only the summary. Her sentences and quotes are dropped as soon as the entry is let go (current rule: table above).

### Version 3 (2026-11-05)
One summary line per part plus at most two of her own lines (current format: top of this doc).

## Version 2: chain analysis, one question per call (2026-11-04)
The owner found version-1 notes inaccurate: the model copied her words correctly but put them in the wrong boxes ("what helped" held a trigger, a need pointed at an unrelated sentence), and a keyword rule took "I need" lines as "what helped". Version 2:
- **Chain analysis** (dialectical behaviour therapy): each of her sentences gets one label: what set it off, a thought, a feeling, the body, what she did or felt pulled to do, what it gave her in the moment, what it cost, what she wants, what helped, or background. Sentences are copied whole; the model only labels them.
- **One short question per call** for the summary (in "you" voice), feelings (fixed list, now with pleasant ones too), and strength (none, mild, strong, very strong, with defined meanings and the sentence that shows it).
- **Needs: pick, then verify.** The model picks one missing and one met need with the sentence that shows it; a second, strict yes/no check of that sentence must agree, or the need is dropped.
- "What helped" in the rule fallback now takes only lines that say something helped.

Tested on Qwen3-VL 4B (the on-device model) on a Mac with synthetic entries: sentence labels were right in nearly all cases; strength stopped over-calling after the levels were defined; a single need-per-call question and per-need yes/no questions both gave wrong needs, while pick-then-verify kept only correct ones (and showed none when unsure). About 3 seconds per entry on a Mac.

Evidence: chain analysis is a core DBT component (Linehan 1993; Rizvi and Ritschel 2014, Cogn Behav Pract); strength Moderate as a clinical tool, none found for automated labelling of diary text.

## Honest affirmations (owner, 2026-11-04)
"Affirmations, but only honest ones." Generic positive self-statements ("I am a lovable person") made people with low self-esteem feel worse (Wood, Perunovic and Lee 2009, Psychological Science). Affirming one's own values (self-affirmation theory; Cohen and Sherman 2014 review, Annual Review of Psychology) and self-compassion (Neff; common humanity) help. So `HonestAffirmations` has fixed lines, each shown only when her labelled sentences back it, at most two, each with the reason it is true:
- what she wants, quoted (not when the "want" is avoidance, such as not wanting to think about something);
- what helped, quoted;
- the steps of a habit chain she caught (only for repeated patterns with something gained or lost, not one-off events, flashbacks or intrusive images);
- quick relief as how habits form (habits only);
- a self-conscious feeling as common (shame, guilt, disappointment);
- "This was hard, and you still put it into words" (strong and mostly unpleasant only; affect labeling).
Never traits ("you are strong"), promises ("it will be fine") or reassurance; every line passes the output checks.

History, 2026-11-05: the owner said the fixed lines "are still flat", so the language model now writes them (`HonestAffirmations.prompt`, `parseWritten`; stored in `ReleaseNote.affirmations`, dropped by the let-go summary). One extra call after the note is assembled, never for heavy, hopeless or self-harm entries. The model gets her numbered sentences, their parts, the feelings and needs, and writes one or two lines under 30 words that connect things she wrote, each naming the sentences it rests on, one approach from a fixed list (values, compassion, strengths, labelling; the app supplies the description, so no citation is invented) and one line on why it is true here. Format: `LINE: ... | SENTENCES: 2,5 | APPROACH: values | BASIS: ...`. A line is dropped unless: it cites valid sentences that are hers and do not mention self-harm or read hopeless; any quoted text is an exact substring of her entry; it has no trait ("you are strong", "a good person"), promise or prediction, dismissing reassurance ("don't worry", "not a big deal"), advice or order ("you should", "try to", "remember to", a sentence opening with a verb), diagnosis or label, "I"/"me" voice; and it passes `ListenRules.rejection` and `OutputValidator`. If no line passes, or the note is older, or the model is off, the fixed lines above are shown. The card says how they are made.

## Distress eval (2026-11-04)
`DistressEvalHarness` (test, off unless `AIHEART_EVAL_DIR` is set) writes every prompt the phone would send for a set of synthetic cases, a local runner answers them with the on-device model (Qwen3-VL 4B), and the harness runs the app's real decision, parsing, checks and affirmations on the answers. The cases are kept outside the repo. First run: 18 of 22 passed; all four failures were short, keyword-free entries (no point in waking up, wanting to disappear, a Tagalog entry, not eating as self-punishment) where the model said yes but was never asked, because its checks ran only on entries headed for release. Model checks now run on every written entry of three words or more: 22 of 22. Known trade-off: an intrusive, unwanted image of harming someone else also opens the safety page (a false alarm costs a calm page; a miss costs far more). Affirmation and need rules were tightened from the same run (no "hard day" on a good day, no habit language for one-off events, safety as the need when someone else is hurting her).


## Embarrassing, not heavy (owner, 2026-11-04)
"I'm OK with keeping heavy stuff. The thing I have issues with are embarrassing or shameful entries ... that's where you choose letting go, or scrub the thing of embarrassing details and focus on what's important." Heavy entries are kept (hopeless ones still show the heavy card). An entry is offered for letting go only when it reads as embarrassing or shameful: her own words (English, Japanese, Tagalog) or the model saying so; never automatic. The offer: hold to let go, keep it without the embarrassing parts, or keep it all. Scrubbing drops whole sentences (the model's marks, or her shame words without it), never rewords; she reviews the marks; notes are written again on the rest. The same check runs after saving anywhere: Now, Listen ("Keep it as an entry"), and the journal summary of a Talk it through, which is a short summary in her voice that she can edit before it is saved. Self-harm is never let go.

## Taking out embarrassing parts, in her own words (owner, 2026-11-04; changed 2026-11-05)
"Instead of scrubbing embarrassing details, rephrase or reframe it, but don't lie. Keep it honest." (2026-11-04). Changed 2026-11-05 ("change the features"): the model never writes a reframe or anything in her voice (CLAUDE.md rule 11), so the rewrite step is gone. The model (plus her own shame words) only points: it pre-selects the sentences that carry the embarrassing details. She can change the selection, and each removed sentence can be replaced by her own typed words. The review shows each sentence as kept as it is, removed, or replaced with her words, and nothing is saved until she taps the done button. Used for entries (the offer and the entry menu) and for Talk it through ("Remember it, without the embarrassing parts"). Heavy entries are never let go and self-harm entries never are; both rules are unchanged.

History: 2026-11-04 two-step pick then model rewrite; 2026-11-05 rewrite and its checks removed.
