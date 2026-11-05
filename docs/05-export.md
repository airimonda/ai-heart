# 05 Export (screen 20)

She can export whenever she wants. Nothing is exported automatically and nothing is uploaded: the result goes to the share sheet or Files and goes only where she sends it.

## Options
- **Journal:** a ZIP with one Markdown file per month, photos beside them, optional voice notes, and `entries.json`. Opens in any editor.
- **Data:** CSV per table (`daily_summary`, `entries`, `mood_points`, `workouts`, `hevy_sets`, `cycle`, `medication`, `lab_results`, `dose_changes`, `body_checks`, `forecasts`) plus `schema.json`. Units in the header.
- **For my doctor:** a 1 to 2 page PDF: sleep, resting HR, HRV, a dose and lab timeline, the body balance chart, cycle summary, and a mood range. No journal text unless she includes it.
- **Everything, encrypted:** a `.aiheart` file (AES-GCM, key derived from a passphrase she chooses). Restores the whole app on a new phone.

## Filters
Date range (all time, this year, 3 months, custom). Toggles: photos, voice notes, body and workout data, Strava activities (off by default).

## Rules
- Released entries are never included. Resting entries are included only as their kept lines.
- Include the mood point and body map for every entry so charts can be rebuilt.
- Strip location metadata from photos.
- Keep an export log (date, type, range) on the device. Never the contents.
- Provide an import for the `.aiheart` file.
