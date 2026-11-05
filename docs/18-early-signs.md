# 18. Early signs and sleep rhythm

## What was built

- **My signs** (My rules): a list of early-warning signs in her own words, one per line, written with her clinician. Add, edit, delete, reorder. If the list is empty and the older "Early signs" note in Notes from a steady day has text, one button splits it into list items (the note stays as it was). The app never writes, suggests or edits a sign.
- **A quiet check** (`EarlyWarning`, switch "Watch my sleep and energy", on by default). It looks only at what the app can see, each against her own previous 28 days, and needs at least 14 days of data:
  - sleep duration: at least 2 of the last 3 nights at least 1.5 h under her median;
  - sleep timing: the middle of sleep (from bed and wake time) at least 1.5 h earlier, or at least 1.5 h later, on at least 2 of the last 3 nights;
  - energy taps: her own arousal taps in the last 3 days (at least 3, model-guessed points excluded) averaging at least 0.4 above her 28-day mean.
- **The Now card** ("Some of your signs"): the plain descriptions of what was seen, her own list as a checklist she can tick for herself (ticks are not stored), "My safety plan", "Something to try", and "Not now". At most one card per stretch: not again until 7 days after the last one, and never while the switch is off or Pause everything is on. The wording describes, never labels, never advises.
- **Outlook features** (`OutlookBuilder`): "Sleep timing shifted" (how far the middle of last night's sleep is from her 28-day median, as a size) and "Sleep less regular" (spread of sleep length over the last 7 nights against her usual spread). Both are z-scored against her own history with a minimum spread, need at least 7 days of her own data, count only the unusual side, and appear in the drivers like the other features. The outlook keeps its minimum-sample gate and its comparison with naive guesses.
- **Training data**: mood points the on-device model guessed from her writing (`Entry.moodGuessed`) are left out of the outlook and patterns. They still show in charts. Energy taps used by the quiet check are also her own taps only.

## Evidence

Label strength: **Moderate**.

- Perry A, et al. Randomised controlled trial of teaching people with a mood condition to identify early symptoms and obtain treatment. BMJ 1999;318:149-153. Teaching people to identify early signs and to get help was followed by fewer relapses and a longer time to relapse.
- Morriss R, et al. Interventions for helping people recognise early signs of recurrence (mood conditions). Cochrane Database Syst Rev 2007. Review of early-warning-sign interventions.
- Lewis KS, et al. Sleep loss as a trigger of mood changes. Br J Psychiatry 2017;211(3):169-174. n = 3,140.
- Frank E, et al. Two-year outcomes for interpersonal and social rhythm therapy. Arch Gen Psychiatry 2005;62(9):996-1004. Regular daily rhythms.

Caveats:

- Self-report detects elevated mood poorly, so sleep is the main passive signal and the energy taps are a weaker one.
- The trials taught people to identify their own signs with support; they did not test an app notice. The notice is a prompt to check her own list, not a detection and not a prediction.
- No notice never means nothing is changing. Most of her signs (spending, talking, pulling away) the app cannot see.
- Sleep timing needs bed and wake times in the day data (the iPhone sleep schedule or the watch). Without them only the duration check runs.

## Rules kept

On device only. Describe, never prescribe. No state is named unless she wrote the word. No red, no streaks, no repeated prompts, no exclamation marks. Synthetic data only in tests.
