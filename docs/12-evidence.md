# 12 Evidence base

What research supports each design decision, how strong it is, and where it is weak or silent. Written for a reader who is a data scientist: effect sizes are given where found, and gaps are stated plainly.

**Read this first.** AiHeart is a self-tracking and journaling tool. It is not treatment and not a diagnostic device. Most of the evidence below comes from healthy or subclinical samples, short studies, or lab tasks. Where an owner's situation differs from these samples (for example a mood condition, another health condition, or cycle-related mood changes, which vary from person to person), the app should present patterns as hints and encourage sharing exports with her clinicians.

Strength labels: **Strong** (several meta-analyses or large samples), **Moderate** (one good meta-analysis or consistent studies), **Limited** (small, lab-based, or short), **Mixed**, **None found**. This session searched the open web; sources are listed at the end with what was and was not verified.

## Summary table
| Design decision | Evidence | Strength | Main caveat |
|---|---|---|---|
| Sleep is the first signal and goes into the outlook | Sleep loss is a commonly reported trigger of mood episodes (n = 3,140). Sleep change and variability may help flag upcoming episodes. | Moderate | Self-reported triggers; prediction studies are exploratory |
| Mood outlook from passive data, framed as a lean | Wearable and phone data predict depression severity with reported accuracies of 79 to 91 percent in a few longitudinal studies, higher with personalized models. For specific mood states, evidence linking passive measures to them is described as inconclusive. | Mixed | Short studies; accuracy figures lack naive baselines. This is why the app benchmarks itself and says "Not yet" |
| Cycle-adjusted baselines for HRV and similar signals | Cardiac vagal activity (HRV) falls from the follicular to the luteal phase (d = -0.39, 37 studies, 1,004 people). People differ widely in mood sensitivity to the cycle. | Moderate to strong for the HRV shift; limited for mood prediction | In a small study (n = 31) the usual luteal HRV drop was not linked to premenstrual mood change |
| Estimate ovulation and phase from wrist temperature | Apple's wrist-temperature algorithms gave retrospective ovulation estimates in about 80 percent of cycles with a clear signal, mean error about 1.2 to 1.7 days. Wrist skin temperature was more sensitive than oral basal temperature in another study but had more false positives. | Moderate | One main source is a preprint; estimates are retrospective; label phase as estimated |
| Suggested feeling words ("words that might fit") | Putting feelings into words lowered amygdala response in an fMRI study. Finer emotional differentiation is associated with better wellbeing and less maladaptive coping. | Limited to moderate | Lab and correlational. Offering words from physiology has not been tested; suggestions can anchor her |
| Body map plus sensation words (heavy, light, buzzing) | People colour consistent, separable body maps for different emotions, similar across West European and East Asian samples. Valence-related maps show lightness for positive and heaviness for negative emotions. | Moderate (lab) | Mostly induced emotions in healthy adults; clinical use not established |
| Mood pad (pleasant and stirred) | Two-dimensional valence and arousal models are widely used. The dimensional view is also debated. | Moderate | A mixed state (pleasant, racing, short sleep) is poorly captured by two axes; hence optional extra dimensions |
| No streaks, forgiving of gaps, one-tap capture | In a habit-formation study (n = 96), missing one opportunity did not materially affect habit formation, but very inconsistent people did not form habits. Time to automaticity ranged from 18 to 254 days (median 66). | Moderate for the "one miss does not matter" claim | Habits studied were simple behaviors, not journaling. Low friction matters because inconsistency hurts |
| Journal as a place to write | Expressive writing has a small average effect on distress (g about -0.12 in healthy and subclinical samples, 31 RCTs, N = 4,012). Results in clinical groups are mixed and some meta-analyses are null. | Limited | Rumination can turn self-focused writing against someone. Mitigated by pacing, no live dashboards, and easy ways to stop |
| "Let go" of hard entries | Physically discarding written thoughts reduced their influence on later judgments, and keeping them in a pocket increased it. Merely imagining discarding did not work. | Limited | Students, short-term, about body and diet attitudes, not distress. No clinical test |
| Resistance training and mood charts | Resistance training reduced depressive symptoms (mean effect 0.66, 33 RCTs, 1,877 people); blinded trials showed smaller effects. | Moderate | Her own charts are observational. People may lift on better days. Do not claim cause |
| Media signals (time, repeats, late nights) | Listening histories of 541 Last.fm users: higher depression risk was linked to more repetitive listening and to music tagged as sad. A 2025 conference abstract from a Spotify-plus-mood-sampling study (n = 171) reports that streaming data is a useful source of real-time mood information. | Limited | Cross-sectional or abstract-level; risk scores are not diagnoses; people choose music to regulate mood, so the direction can run either way |
| Late-night viewing and sleep | Binge viewing was linked to poorer sleep quality, more fatigue and more insomnia, fully mediated by pre-sleep arousal (n = 423, ages 18 to 25). | Limited | Survey of young adults; correlational |
| Self-monitoring with pacing | Electronic mood self-monitoring was valid against clinician scales for depression in 6 of 6 studies but only 2 of 7 for elevated mood. RCT evidence of benefit is scarce and possible harm (such as rumination) is unstudied. An RCT of two mood apps found no clinical difference. | Limited | Another reason to combine self-report with passive data and clinician review |
| LLM narrates numbers, static safety page, no labels or advice | Therapy chatbots built on LLMs showed stigma and missed suicidal cues in a 2025 study; the authors saw safer roles in supporting tasks such as diary-keeping. | Limited but consistent | The study tested chatbots as therapists, not on-device narrators |
| Automatic keep or release | No research found on an app deciding what a person should let go. | **None found** | The least evidence-based feature. Treat as experimental. Rest period, keep-the-numbers, unsure-means-keep and never-release-self-harm are precautions |
| Notes kept from a let-go entry (docs/16) | CBT five-part model for the reaction; needs from self-determination theory and schema therapy; affect labeling; self-distancing | Moderate for the frameworks; **none found** for inferring needs from diary text | Every feeling and need comes from a fixed list and shows her words; see docs/16 |

## Where the evidence is weak or against the design
1. **Mood forecasting.** Treat it as a hypothesis she tests on herself. Always benchmark against "same as yesterday" and a 7-day mean (already specified). Evidence for specific mood states from passive data is inconclusive.
2. **Self-monitoring can backfire for some people.** The systematic review lists it as a possible harm that has not been studied. The pacing rules, Pause, and one weekly look-back are precautions, not proven fixes.
3. **Expressive writing is not a reliable therapy** and may reinforce self-focus in depression. Keep the app a place to put things down, not a prompt to dwell.
4. **Automatic release has no evidence.** The closest finding needs the person to physically discard the written thought.
5. **Suggested words can bias reports.** No research was found on physiology-based word suggestions. Keep the set balanced, pre-select nothing, and measure acceptance rates.

## Design changes the evidence suggests (not yet in the mockups)
- **Add sleep timing and variability to the outlook features** (regularity of sleep and wake times, variation in duration), not only last night's duration.
- **Offer an optional physical "hold to let go" gesture** on release, because the discarding effect depended on a physical act. Auto-release alone may not give the ritual benefit.
- **Label the body balance** as patient-reported experience, next to labs. A symptom chart is not a stand-in for lab values.
- **Mark cycle phase as estimated** and allow manual correction. Show how the luteal baseline adjustment changed the reading.
- **Do not overclaim what self-report detects.** Self-report tracks low mood better than elevated mood. Use passive sleep data and a clinician for the rest.
- **Listen (docs/13)** has no direct research behind it. It rests on affect labeling and expressive disclosure, which have small effects, and on the 2025 finding that LLM therapy chatbots can mishandle crises. It is kept narrow and persona-free for that reason.
- **Self-experiments (later milestone).** Let her pre-register a small question ("do lifting days relate to my next-day mood?"), run it for a fixed period, and see the result with intervals. This keeps the app honest and fits how she works.
- **Optional validated scales, monthly, kept local,** only if she and her clinician want them. Check suitability and licensing first.

## Sources (what was retrieved)
Sleep and mood
- Plante DT, Winkelman JW. Am J Psychiatry 2008. Abstract read.
- Lewis KJS, et al. Sleep loss as a trigger of mood episodes. Br J Psychiatry 2017;211:169-174. n = 3,140; abstract and summary read.
- Can sleep parameters predict upcoming mood episodes? 2025, doi 10.1111/bdi.70054. Abstract and introduction read. Its introduction reports a systematic review of 11 RCTs finding that focusing on early warning signs helped; that review was not opened.

Passive sensing and self-monitoring
- Kutcher TP, et al. Digital markers for passive remote monitoring: systematic review. JMIR Mental Health 2026, doi 10.2196/94819. Abstract read.
- Amin R, et al. Use of mobile sensing data for longitudinal monitoring and prediction of depression severity: systematic review. J Med Internet Res 2025;27:e57418. Abstract read.
- Faurholt-Jepsen M, et al. Electronic self-monitoring of mood using IT platforms: a systematic review of the validity and evidence. BMC Psychiatry 2016;16:7. Abstract read.
- KIOS app randomized comparison. 2024;26(1):84-92. Abstract read.

Menstrual cycle
- Schmalenberger KM, et al. A systematic review and meta-analysis of within-person changes in cardiac vagal activity across the menstrual cycle (2019). Abstract read; the journal name was not shown, verify.
- Schmalenberger KM, et al. Associations of luteal phase changes in vagally mediated heart rate variability with premenstrual emotional changes. BMC Women's Health 2024;24:448. Full text read.
- Wang Y, et al. Performance of algorithms using wrist temperature for retrospective ovulation day estimate and next menses start day prediction. JMIR Preprints 2023 (50821). Preprint; check whether it was published.
- Zhu TY, et al. The accuracy of wrist skin temperature in detecting ovulation compared to basal body temperature. J Med Internet Res 2021;23(6):e20710.

Emotion, body, language
- Lieberman MD, et al. Putting feelings into words: affect labeling disrupts amygdala activity in response to affective stimuli. Psychol Sci 2007;18(5):421-428.
- Kashdan TB, Barrett LF, McKnight PE. Unpacking emotion differentiation. Curr Dir Psychol Sci 2015.
- Nummenmaa L, Glerean E, Hari R, Hietanen JK. Bodily maps of emotions. PNAS 2014;111(2):646-651.
- Hartmann et al. Happiness feels light and sadness feels heavy: introducing valence-related bodily sensation maps of emotions. Psychol Res 2022;87:59-83. The circumplex model (Russell 1980) was read as cited here, not directly.

Writing, discarding, rumination
- Briñol P, Gascó M, Petty RE, Horcajo J. Treating thoughts as material objects can increase or decrease their impact on evaluation. Psychol Sci 2013;24(1):41-47.
- Guo L. The delayed, durable effect of expressive writing on depression, anxiety and stress: a meta-analytic review. Br J Clin Psychol 2023;62(1):272-297. Read through a summary.
- Frattaroli J. Experimental disclosure and its moderators: a meta-analysis. Psychol Bull 2006;132(6):823-865. Read through secondary sources, which also list null meta-analyses (for example Reinhold 2018).
- Nolen-Hoeksema S, Wisco BE, Lyubomirsky S. Rethinking rumination. Perspect Psychol Sci 2008. From background knowledge; not retrieved in this session.

Media
- Surana A, et al. Static and dynamic measures of active music listening as indicators of depression risk (Last.fm, n = 541). arXiv 2009.13685; Interspeech. Abstract read.
- Jones M, Di Cara N, Davis O, Haworth C. Mood Music: combining Spotify data with ecological momentary assessment to explore mental health. Int J Popul Data Sci 2025;10(5). Conference abstract read.
- A two-week experience-sampling study of mood management through music streaming (144 listeners, 6,864 surveys). Abstract read.
- Exelmans L, Van den Bulck J. Binge viewing, sleep, and the role of pre-sleep arousal. J Clin Sleep Med 2017;13(8):1001-1008.

Training, habits, LLMs
- Gordon BR, et al. Association of efficacy of resistance exercise training with depressive symptoms. JAMA Psychiatry 2018;75(6):566-576.
- Lally P, van Jaarsveld CHM, Potts HWW, Wardle J. How are habits formed: modelling habit formation in the real world. Eur J Soc Psychol 2010;40:998-1009.
- Moore J, et al. Expressing stigma and inappropriate responses prevents LLMs from safely replacing mental health providers (2025). Read through news coverage and summaries; the paper itself was not opened.

Not retrieved: the common finding that resting heart rate rises in the luteal phase. It is from general knowledge and should be verified. No direct evidence was searched for photo-first capture, trauma-informed resurfacing rules, or the effect of suggested words on reporting; these are design judgments.
