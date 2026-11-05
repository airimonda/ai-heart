# 15 Hard moments

How the app behaves when things are hard, and the research behind each choice. Strength labels follow `docs/12-evidence.md`. Sources were found by web search on 2026-11-02. Most were read as abstracts, summaries or news coverage, not full papers.

## The ask (owner, 2026-11-02)
- Base how the app handles hard moments on research.
- Guard against "AI psychosis": a chatbot that agrees, mirrors, or becomes a relationship.
- Suggestions are now allowed: grounding, reframing, body (somatic) exercises, physical activity.

This changes CLAUDE.md rule 11 ("never gives advice") in one place only. **The AI still never advises.** Suggestions come from a fixed list in code (`HardMoments.catalog`), each with its evidence label. The model never writes, picks, changes or adds to it.

## What was built
**Something to try** (Listen after-sheet, and the "This looks heavy" card):
1. "What is it like right now?" Four plain choices: Fast, Heavy, Stuck on a thought, Too much. She taps; the app never infers or names a state (rule 3).
2. Her own note from a steady day for that state comes first, then the early signs she wrote (for Fast and Heavy).
3. An optional 0 to 10 "how strong" rating.
4. At most three techniques, with "More" showing the rest. Nothing is hidden.
5. One literal step per screen. Back, Next, and Stop here are always there. "Why this is here" shows the evidence.
6. At the end, an optional "how strong now". Writing exercises are discarded unless she taps Keep.

**Reachable from anywhere, with taps only**: a "Hard right now? Something to try" row on Now (shown even while Pause everything is on), Siri and Shortcuts ("Something to try in AiHeart"), which can be put on the Action button or the lock screen, and the quiet check-in below. Listen is only one way in.

**When I go quiet** (My rules, on by default at the owner's request): if she has not logged, talked or typed for longer than her own usual gap, one notification: "A quiet few days. Nothing to catch up on. If it is hard, one tap is enough." Its buttons are Something to try, Who I can reach, and Busy, all good. Rules:
- The gap is her own: the 90th percentile of the gaps between her active days over 90 days, plus one day, held between 2 and 7 days (3 until there is enough history).
- Only her logs count (entries, Listen, things tried, doses, checks). Health, workouts and media do not: being on the move is not the same as being okay.
- At most one per quiet stretch, at her reminder time (or 19:00). It never repeats, never escalates, and never asks her to log. Off while Pause everything is on.
- Silence can mean busy. "Busy, all good" is one tap and does nothing else.

**Notes from a steady day** (My rules): what she wants to hear in each state, and the early signs she knows in herself. These are written by her and never generated.

**Her own evidence**: each try stores the technique, the state, and the before and after ratings. It never stores what she wrote. After 3 rated tries for a state, techniques that eased it by 1 point or more move up. Techniques that did not ease it move down. The card says "for you, N tries"; it is not proof.

**Listen validator**: it now also rejects agreement and special meaning, such as "you're right", "you're not crazy", "it's a sign", "only you can", "I am real" or "our connection". This applies even if she said those words herself. Echoing them back is agreement.

## Why each rule

### Against AI-linked delusions
| Rule | Evidence | Strength |
|---|---|---|
| The model never agrees, takes a side, or gives events special meaning | In 2,405 people, one sycophantic AI reply made people more sure they were right and less willing to repair a conflict. People also trusted and preferred the agreeable AI (Cheng et al., Science 2026). | Moderate |
| No persona, no relationship language, no claims of being alive | In chat logs of people in harmful delusional spirals, replies that endorsed delusions or showed romantic interest were followed by longer conversations (Moore et al. 2026). | Limited, consistent |
| No memory of past sessions, short context | Safeguards weaken over long multi-turn chats (Moore et al. 2026). The proposed mechanism is mirroring plus personalization plus sycophancy (Nature 2026 review; a hypothesis). | Limited |
| The suggestions are fixed, not generated | Follows from the rows above: a fixed list cannot drift toward agreeing. | Design judgment |
| Notes from a steady day | Advance statements and check-ins were proposed as safeguards (Eur Psychiatry 2026). Safety plans written in advance reduced suicidal behavior (RR 0.57, 6 studies, Nuij 2021). | Moderate for safety plans |
| One quiet check-in after silence, non-demanding | Brief non-demanding "caring contacts" after a period without contact reduced suicide attempts at 12 months (RR 0.57, small meta-analysis, Skopp et al.); the effect on deaths was inconclusive. Whether one-way messages work as well as two-way is not known. | Moderate for attempts |
| Sessions stay short; heavy use is watched | Heavier daily chatbot use went with more loneliness and emotional dependence (MIT and OpenAI 2025; correlational, preprint). | Limited |

### Universal precautions
| Rule | Evidence | Strength |
|---|---|---|
| Never ask her to recount what happened | Single-session debriefing soon after a hard event did not help and may harm some people (Cochrane, Rose et al.). | Moderate |
| She chooses every step; Stop is always visible; each card says why it is there | SAMHSA's six principles of safety, transparency, choice and collaboration, meant for everyone. | Framework |
| Pick a state instead of naming a feeling; at most three offers; one literal step per screen | Naming a feeling can be the hard part in a hard moment. Not tested for this use. | Design judgment |
| Less input (light, sound, words) | A common support for overload. No trials found. | Design judgment |

### By state
| State | What leads, and why | Strength |
|---|---|---|
| Fast | Protect tonight's sleep: sleep loss is a commonly reported trigger of mood swings (n = 3,140), and regular daily rhythms went with fewer swings in a trial (Frank 2005). Walking is never the first offer; hard workouts late at night are discouraged. | Moderate; exercise timing is design judgment |
| Heavy | Move a little: one exercise session lowers anxiety a little (g 0.16 to 0.50); regular activity lowers low mood (median -0.43, Singh 2023). Check the thought: core CBT, with five fixed questions she answers herself. Step back from it: distanced writing lowered distress across 48 studies. | Moderate |
| Stuck on a thought | Let the thought be a thought (defusion). In lab studies it did better than distraction and about as well as arguing with the thought; arguing and checking can become a loop, and suppression raises distress (Najmi 2009). "Check the thought" is not offered here. | Limited |
| Too much | Long breath out, grounding (5-4-3-2-1, little trial evidence), less input. | Moderate to limited |

### Body
| Technique | Evidence | Strength |
|---|---|---|
| Long breath out (cyclic sighing, 5 min) | Improved mood more than mindfulness in a one-month RCT with healthy adults (Balban 2023). | Moderate |
| Tense and let go (progressive muscle relaxation) | Lowered stress and anxiety in a 2024 review of 14 studies, with mixed quality. | Moderate |

## What stays the same
- The self-harm stop, the Safety page, crisis lines, and never releasing those entries (docs/06, docs/13).
- The AI never advises, labels, reassures, diagnoses, or responds to a crisis.
- Nothing here sends anything off the phone.

## Gaps
- No study tests any of this inside an app like this. Most of the evidence comes from healthy adults or lab tasks.
- Her own before and after numbers have no control group, and ratings tend to fall over time anyway. Review them with a clinician, not as proof.
- Review after a month of use, as in docs/13. If it feeds checking or dependence, change it.

## Sources
- Cheng M, et al. Sycophantic AI decreases prosocial intentions and promotes dependence. Science 2026. doi 10.1126/science.aec8352.
- Moore J, et al. Characterizing delusional spirals through human-LLM chat logs. arXiv 2603.16567 (2026).
- Delusions by design. Eur Psychiatry 2026. doi 10.1192/j.eurpsy.2026.10633.
- Characterising the spiral: potential mechanisms in AI-associated delusions. Nature (npj) 2026. News summary only.
- MIT Media Lab and OpenAI. Affective use of ChatGPT and emotional well-being (2025, preprint).
- Skopp NA, et al. Caring contacts for suicide prevention: systematic review and meta-analysis. Summary.
- Motto JA, Bostrom AG. A randomized controlled trial of postcrisis suicide prevention. Psychiatr Serv 2001.
- Nuij C, et al. Safety planning-type interventions: meta-analysis. Br J Psychiatry 2021. doi 10.1192/bjp.2021.50.
- Rose S, et al. Single-session debriefing. Cochrane review, plain-language summary.
- SAMHSA. Guidance for a trauma-informed approach (2014).
- Lewis KJS, et al. Br J Psychiatry 2017 (see docs/12).
- Frank E, et al. Arch Gen Psychiatry 2005. Abstract.
- Singh B, et al. Br J Sports Med 2023. doi 10.1136/bjsports-2022-106195.
- Ensari I, et al. Depress Anxiety 2015;32:624.
- Balban MY, et al. Cell Rep Med 2023.
- Progressive muscle relaxation in adults: systematic review (2024).
- Self-distancing meta-analysis (48 studies, 102 effects).
- Najmi S, Riemann BC, Wegner DM. Behav Res Ther 2009.
