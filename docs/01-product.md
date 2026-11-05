# 01 Product

## One sentence
A gentle place to put things down (a photo, a word, a few sentences), that quietly connects them to what her body is doing, and shows her patterns about herself without telling her what to do.

## Principles
- **Easy to start.** One screen, one tap to save. Nothing is required.
- **Photo first.** When she cannot say it, she takes a photo or taps a word.
- **Descriptive.** "What is happening", never "what you should do".
- **Quiet.** Pull, not push. One weekly look-back that has an end ("That is this week.").
- **Private.** Everything on the device.
- **Lovely to look back on.** The Journal is the heart of the app.

## Structure (see design/screens/01)
Three tabs: **Now**, **Journal**, **Insights**. A gear on Now opens settings.

### Now (02)
Greeting strip (cycle day and outlook, tap opens Insights > Today), one capture box ("Anything to put down?") with photo, voice and where-I-feel-it buttons, and five suggested words. One tap on a word saves immediately. Save after typing. After saving, show the Saved result (22).

### Suggested words
Computed from today's body signals against her own cycle-adjusted baselines. Offer a balanced set (include opposites), pre-select nothing, always allow "My own". Choosing a word places the mood point on the pleasant and stirred pad (10) automatically; she can drag it.

### Where do you feel it (08)
Smooth anatomical figure with tappable regions and sensation chips (tight, heavy, buzzing, numb, warm, cold, hollow, light, or her own word). The figure is in `design/body-figure.svg`; regions and glow are in `design/source/BodyMap.dc.html`.

### Journal (03, 12, 13, 14 and the entry screen)
Native-feeling and calm. A large "Journal" title with a filter button and a search field (search kept text only; respect Quiet topics). A segmented control switches Entries and Month.
- **Entries:** grouped by month. Each day has a left column (day number, weekday, "Day 22" cycle tag) and its entry cards. A photo entry is a card with the photo on top, then a caption, time, her word, a tiny mood pad and a tiny body glow. A voice or word-only entry is a compact row. Resting and let-go entries show only the lines she kept, with a "Resting" or "Let go, numbers kept" label and "Bring it back" while resting. A quiet day-summary line (sleep, workouts, media) sits above each day's entries. Days with no entry are simply absent.
- **Entry screen:** back chevron to Journal, the date as the title, a More menu (share or export this entry, change keep or let go, delete). Full-width photo with the caption, her word, mood pad and body regions, her writing in a serif, a grouped list "How your body was" with small charts (sleep, resting HR, HRV, cycle day, training), and the Kept status.
- **Month:** a calendar. Photo days show a thumbnail, feeling-only days show a dot, the selected day is ringed, and a thin bar under each day shows the cycle phase. The selected day's entries sit below.
- Her words use a serif face. Everything else uses the system face.

### Automatic keep or release (22, 23, 13)
See `docs/03` and `docs/06`. The user chose to let the app decide. Always rest first, always allow undo.

### Insights (21 Today, 04 Patterns)
Today: vitals against her cycle-adjusted usual, activity (steps, burned calories, workouts by type), cycle ring, and the mood outlook card. Patterns: mood by cycle phase, sleep against next-day mood, lifting days and mood, training and recovery, and a forest plot of what lines up with mood.
Sub-screens: Your body (05), Your cycle (11), Labs with the Weekly body check-in, Rate this workout (17; replaces Log a workout, see docs/08 M5), Mood outlook (18).

### Mood outlook (18)
An on-device model forecasts the expected mood point for the next three days with uncertainty. The on-device LLM writes "AiHeart's read" and answers questions about it. It reports its own track record against a naive baseline and says "Not yet" until it beats it.

### Labs
Lab results (any common marker, by hand or read from a report screenshot on the phone) grouped by report date, with the lab's own ranges. A weekly body check-in (lower side and higher side) plus Watch signals form a balance chart with dose changes and labs marked. Never advises on dose. Dose changes are for her doctor.

### Settings (06, 23, 19, 20)
My rules (look-back pace, resurfacing off, pause everything, quiet topics, safety page, Mood outlook, Connections, Export), How it decides, Connections, Export.

### Apple Watch (24 to 32)
Capture only, plus a Today glance and a post-lift effort prompt. No analysis on the wrist. A Paused state mirrors "Pause everything".

## Platforms (see docs/11, screens iPad and Mac)
- **iPhone:** the three-tab layout.
- **iPad:** the tab bar becomes a sidebar. Now is two columns (capture on the left, Today on the right). Journal is three columns (sidebar, list, entry). Insights is two columns of cards.
- **Mac:** native window with toolbar (search, filter), a sidebar, and the same three-column Journal. Settings opens in its own Settings window with panes General, Privacy, Connections, Export, Sync.
- **Sync (screen on iPhone, iPad, Mac):** one switch, the device list, what syncs and what does not, and the encryption note.

## Language
English, with Japanese entries supported (she writes in more than one language). Support IME input, store timestamps with timezone, and define a "day" around her sleep, not midnight. Provide one-tap life-event markers (move, travel) that reset baselines and flag charts.
