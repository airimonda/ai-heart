# 06 Privacy and safety

## Privacy
- Local storage with complete file protection, optional Face ID lock, hidden in the app switcher. Sync is only between her own devices through her own iCloud, with encrypted attributes (`docs/11`).
- No third-party SDKs. The model weights are the only large download. After that, the only network calls are the integrations she turns on.
- Photos are saved in the app sandbox, not the Camera Roll, with location metadata stripped.
- Lock-screen widgets are capture buttons only. Notification text is neutral.
- She can check network activity with the iOS App Privacy Report.

## Real deletion (release)
When an entry is purged after its rest period, delete: text, photo and thumbnails, audio, embeddings, full-text index entries, cached LLM summaries, and any export staging. Keep the numbers if "keep the numbers" is on. Verify with a test that searches the store and index for the purged content.

## Behavioral rules
- Nothing resurfaces by itself. No "on this day".
- Quiet topics: terms the LLM never raises or searches.
- Pause everything: no analysis, no suggestions, no prompts. Capture still works.
- Look-backs: weekly by default. No live dashboards. A clear end state.
- An optional limit on how often she can question the journal about herself, which she sets herself.
- The LLM does not offer reassurance, does not diagnose, and does not label states.
- The LLM never raises the user's past or other people unless she does.
- Unofficial access methods (such as signing in to a service inside a web view) are opt-in, off by default, labeled unofficial, and never store credentials.
- Listen (`docs/13`): no persona, no memory of sessions, no advice, no crisis response. Possible self-harm stops listening and opens her Safety page.

## Safety
- Entries that mention self-harm or suicide are never released. Keep them and open the Safety page she wrote.
- The **Safety page is static text written by her** (people, what helps, what does not, her clinician). It is not generated. Offer to add local crisis numbers for where she lives (where she lives may change), and let her decide.
- A small model should never be what responds in a crisis.
- Medical: the app never suggests a dose, a medication change, or a diagnosis. The Labs screens say dose changes are for her doctor, and give a short line to contact a doctor or emergency services for chest pain, fainting, or a very fast or irregular heartbeat.
- Mood and body changes can look alike (a physical change can resemble restlessness and short sleep, or low mood and fatigue). The app cannot tell which; it shows them together and flags coincidence with dose or lab changes.
- Expectation effects: outlook wording is always a lean. She can switch it off.
