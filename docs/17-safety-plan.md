# 17 Safety plan

Her free-text "My safety page" is now a structured safety plan in the six steps of the Stanley-Brown Safety Planning Intervention. Strength labels follow `docs/12-evidence.md`.

## What was built
- **Six steps, each a short helper line and a text box she writes in:**
  1. My warning signs
  2. Things I can do on my own
  3. People and places that help me feel better
  4. People I can ask for help
  5. Professionals I can call (the fixed crisis lines show under this step when "Show crisis lines" is on)
  6. Making my space safer
- **Anything else** is the old safety page text, kept as a seventh box so nothing she wrote is lost.
- **Everything on the plan is written by her.** The titles and helper lines are fixed. Nothing is generated, picked or reworded by the model (CLAUDE.md rules 3 and 11).
- **Read view** hides steps she left empty, shows one calm line if all are empty, and turns phone numbers she wrote into tap-to-call links (simple pattern, 3 to 15 digits; nothing dials until she confirms in the Phone prompt).
- **Where it shows:** My rules (editor), the read view from a kept entry, Listen's "Who I can reach" sheet and its safety screen, and the optional "My safety plan" part of the therapist PDF.
- **One tap:** the App Shortcut "Open my safety plan" (Siri, Shortcuts, Spotlight, Action button). It opens the read view. It needs no new entitlement and no new target.
- **Code:** `SafetyPlan` in `Packages/AiHeartCore` (steps, sections, phone links, tested); `SafetyPlanViews.swift` in the app; fields `planSigns`, `planCoping`, `planPlaces`, `planHelpers`, `planPros`, `planSafeSpace` on `AppSettings`.

## Evidence
| Choice | Evidence | Label | Caveat |
|---|---|---|---|
| A written, step-by-step plan: warning signs, own coping, people and places for distraction, people to ask for help, professionals, making the space safer | Stanley and Brown 2012, *Cognitive and Behavioral Practice*, describe the Safety Planning Intervention. Stanley et al. 2018, *JAMA Psychiatry*, cohort study: people who made a plan with follow-up showed fewer suicidal behaviours than usual care. Nuij et al. 2021, *British Journal of Psychiatry*, meta-analysis of safety-planning-type interventions: risk ratio 0.57 for suicidal behaviour. | Moderate | Tested as a plan made with a clinician, usually with follow-up, not as an app screen filled in alone. The cohort was not randomised. The app does not claim the same effect. |

## Because of that caveat
The editor says it can help to fill the plan in with her therapist. The app never fills in, suggests or checks any step.

## People from Contacts (owner, 2026-11-04)
"I am allowing the app to read my emergency contacts." iOS gives apps no access to the Medical ID emergency contacts, so steps 3, 4 and 5 have "Add from Contacts": Apple's contact picker, where she chooses people and the app receives only those (no Contacts permission, no access to the rest of her contacts). Each becomes a line "Name: number" in her plan, tappable to call in the read view and in "Who I can reach". These lines stay on the phone and are never part of a model prompt.
