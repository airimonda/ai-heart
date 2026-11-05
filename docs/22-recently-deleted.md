# 22 Recently deleted

Owner, 2026-11-04: "I wish I can retrieve deleted entries at will."

- Deleting an entry (entry menu, long-press, resting or let-go entry screens) moves it to **Recently deleted** for 30 days. The whole entry is moved into `DeletedEntry` (its fields as JSON, its photo, thumbnail and voice note as stored data) and the entry itself is removed, so nothing else in the app can see it: not the journal, charts, patterns, outlook, notes, Talk it through retrieval, exports or any model prompt.
- **Journal → filter menu → Recently deleted** lists them with the date written, the first line and the days left. **Restore** puts the entry back exactly as it was (same id, text, media, notes, status). **Delete for good** removes it for good.
- After 30 days it is removed for good on the next launch. Removing for good writes a tombstone (CLAUDE.md #9), so no synced copy can come back. Moving to Recently deleted writes none, so restoring works.
- Recently deleted is in the encrypted backup, so a restore keeps the 30-day window.
- Let-go entries (owner, 2026-11-05): a resting entry that is deleted waits at most until the earlier of the end of its rest and 30 days. Whichever comes first wins, so deleting never extends a rest period (CLAUDE.md #7). Entries about self-harm are never let go. A let-go entry keeps only a summary (`docs/16`). Undo on the saved sheet puts her words back in the writing box.
