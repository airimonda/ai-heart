# 07 Design

The mockups in `design/screens` are drawn at 390 pt wide (iPhone) and 208 x 248 pt (Watch, 46 mm). Source HTML is in `design/source`. Follow Apple's HIG: 44 pt minimum targets, system fonts, Dynamic Type, light and dark, meaningful VoiceOver labels. The mockups use fixed px for layout only.

## Look
Soft, uncrowded, pink. Brand deferential: the wordmark appears once, on Now. One signature element: the smooth anatomical figure with a pulse at the heart.

## Tokens (`design/tokens.json`)
- Surface `#FDF8F9`, cards `#FFFFFF`, lines `#F1E6EB`, segmented control `#F7EDF1`
- Ink `#2A1F25`, muted text `#6B5A63`
- Primary action `#B5446F` (white text, 5.2:1). Text on pink tints uses `#8F2C57` (6.5:1), never `#B5446F` (4.3:1)
- Data marks (lines, dots, strokes) use `#C24578` (about 4.7:1 on white); the pale pinks are for fills only
- Pink for data `#EE8DB3`, tints `#FCE4ED` and `#F6CADB`
- Lilac for "your usual range" and the fertile window `#EEE3F4` and `#D9CCF0`
- Flame (release) accents `#FDE8DF`, `#F4A27F`. No red anywhere.
- Watch: black background, pink `#F59BBE`, tile `#2A1C23`, muted `#C9B3BF`
- Type: system font (SF) for the interface. A serif (New York, `ui-serif`) for journal dates and entry text. Rounded 20 to 28 pt corners.

Dark mode is not drawn. Derive it: dark plum surfaces, lighter pink (`#F59BBE`) for actions with black text, same lilac band at low opacity.

## Components
Segmented control, chips, cards, list rows with dividers, toggles, pad (2D mood), body figure with glow regions, sparkline with usual-range band, cycle ring, forest plot, scatter, bars with whiskers, photo entry card, compact entry row, bottom sheet with grabber, calendar grid with cycle-phase bars, waveform, burnt-paper card (let-go animation only).

## Charts
Use Swift Charts. Always show the usual-range band, uncertainty, and n. Sample data in the mockups is illustrative only.

## The figure
`design/body-figure.svg` is a smooth female silhouette (own drawing, proportions from a reference outline the owner supplied). Regions to hit-test: head, throat, chest, stomach, pelvis, arms, legs. Selected regions get a soft pink glow. A small pulse ring marks the heart. The back view is **not designed yet**.

## Copy tone
Calm, plain, kind, never cute, never clinical. Short sentences. Placeholders in the mockups look like `[6h 10m]`.
