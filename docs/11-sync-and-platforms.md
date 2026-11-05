# 11 Sync and platforms

## Goal
The same journal on iPhone, iPad and Mac (Watch through iPhone). This changes one earlier promise honestly: data is no longer only on one device. It lives on **her own devices and her own iCloud account**, encrypted, and nowhere else.

## Mechanism
SwiftData with CloudKit private database: `ModelConfiguration(..., cloudKitDatabase: .private("iCloud.<container>"))`. Needs the iCloud and CloudKit capability and the Remote Notifications background mode.

Constraints to design for from the first commit (found in current SwiftData and CloudKit guidance; verify):
- Every attribute optional or with a default. No unique constraints (enforce uniqueness in code). No `.deny` delete rule. Private database only. The CloudKit schema is deployed to production manually.
- Large payloads use `.externalStorage`.

## Encryption
SwiftData has `@Attribute(.allowsCloudEncryption)`. Per Apple's Core Data documentation for the same feature: use it only on **new** attributes, it cannot be applied to attributes already in the CloudKit schema or to relationships, and an attribute's encryption state **cannot change after the schema is promoted to production**. So decide the encrypted set before the first production deploy.

Encrypt every attribute that holds personal content: entry text, kept lines, words, About me, Quiet topics, lab and medication values, daily body values, workout notes. Leave only ids, timestamps and status unencrypted (these reveal activity patterns; accept or minimize). Verify that photo and audio payloads are covered. If not, encrypt the files yourself (AES-GCM, key in iCloud Keychain) before storing.

Recommend iCloud **Advanced Data Protection** to the owner for everything else. There is no public API to detect it, so show a note and a link to Settings.

## What syncs and what stays per device
| Syncs | Stays on one device |
|---|---|
| Entries with photos and voice notes | Raw HealthKit data |
| About me, Quiet topics, settings | Strava records (display only, 7-day cache, never synced) |
| Daily body summaries made on the iPhone | The language model weights |
| Workouts and Hevy sets | Embeddings and the search index (rebuilt per device) |
| Cycle, labs, dose changes, symptom checks, medication logs | Provider tokens, unless she opts to sync them through iCloud Keychain |
| Forecasts and their track record (the iPhone fits the model) | |

The iPhone and Watch are the **sensor hub**. As far as we know HealthKit is not available to third-party apps on Mac, and iPad support should be checked, so those devices show synced summaries and cannot fetch health data themselves. Model fitting runs on the iPhone; the other devices display results. The on-device language model runs on whichever device she is using (a Mac with MLX is a good fit).

## Release and purge across devices (the dangerous part)
- Entry state is monotonic: `kept` to `resting(restUntil)` to `released` (purged). "Bring it back" returns to `kept` only before the purge. Use `stateVersion` and `stateChangedAt`; the higher version wins.
- When a purge happens, write a `PurgeRecord` tombstone (entry id and time, no content). **A tombstone always beats a stale copy**, so a device that was offline cannot bring a let-go entry back.
- Every device runs the purge job when `restUntil` passes and whenever a tombstone arrives. Purge removes text, photo and thumbnails, audio, embeddings, search index entries, caches, and the CloudKit assets.
- "Gone at once" only takes effect on a device when that device syncs. Show a calm note if a device has not synced recently.
- Test with three simulators and at least two real devices, including offline edits and re-connection.

## Conflicts
Last writer wins per field by `updatedAt`, except entry state (above). If the text of one entry was edited on two devices before syncing, keep both: save the second as a conflict copy labeled "Edited on iPad and iPhone". Never silently drop writing.

Timestamps carry the timezone. A "day" is anchored to sleep, not midnight, on every device.

## Platform layouts
Follow the Apple design skill's navigation rules: the tab bar converts to a sidebar on iPad and Mac; the sidebar has at most two levels; layouts follow available space (size classes), not device names.
- **iPad:** sidebar, plus content. Now is two columns. Journal is a three-column split view (sidebar, entry list, entry). Insights is two columns of cards. Support Split View, Slide Over and Stage Manager sizes.
- **Mac (decided: a native macOS target, not Catalyst):** a resizable window; a toolbar with search and filter; every toolbar command also in the menu bar; standard shortcuts (Cmd-N new entry, Cmd-F search, Cmd-comma Settings, Cmd-1 to 3 for Now, Journal, Insights, Cmd-E export); a separate Settings window with panes General, Privacy, Connections, Export, Sync. Hover states and pointer hit regions. Drag photos into an entry. Camera capture through Continuity Camera or a file picker. Default text size is smaller on Mac (about 13 pt); do not reuse iPhone sizes.
- **Watch:** unchanged; it talks to the iPhone.
- The body figure uses pointer hover to show region names on Mac and iPad.

## Screens
`design/screens` now has the full set for every platform. Mockups use sample data.
- **iPad (1194 x 834):** Now, Journal (three columns), Month, Insights Today and Patterns, Your body, Your cycle, Labs, Mood outlook; form sheets for How it feels, Write or talk, Where do you feel it, Log a workout, Weekly body check and Resting entry; Listen; Settings split views for My rules, Connections, Export, Sync and Listen. Detail screens use the same cards in two columns.
- **Mac (native window):** Now, Journal and Month, an Entry window, Insights Patterns, Your body, Your cycle, Labs, Mood outlook; sheets for Where do you feel it and Log a workout; a Listen window; Settings panes for General, Privacy, Connections, Export, Sync and Listen; and the menu bar with every toolbar command and its shortcut.
- **Apple Watch:** Today, Now, Feeling, Where, Voice, Saved, After a lift, Widgets, Paused, plus Outlook, Cycle, Listen (continues on iPhone), Always-On Today, Journal glance and a face complications gallery.
- **Not drawn:** the Mac and iPad Release and Burning animation, dark mode, and the back of the body figure. The iPhone screens remain the reference for these.
