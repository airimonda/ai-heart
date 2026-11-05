# 10 Design review (against the Apple design skill)

Method: the `apple-design-skill` (dickwu) was read in full (`SKILL.md`). Its five lenses were applied to the mockups: accessibility, platform conventions, visual craft, interaction, and content. The individual HIG pages in that skill's `references/` folder could not be opened, so findings cite the skill's lens rules, not HIG page headings. Contrast figures are computed from the mockups' hex values.

## Summary
**Good, once the items below are implemented.** The design's thesis: a quiet place to put things down that quietly connects to the body. It will be remembered by the smooth anatomical figure with the pulse at the heart, and by the cycle-day tag that sits beside each journal day. The look (blush surfaces, deep rose actions, serif only for her own words) is a deliberate choice for this product, not the cream-and-terracotta default.

## Critical (fixed in the mockups)
- **Pink text on pink tint failed contrast.** `#B5446F` on `#FCE4ED` is 4.3:1 against the 4.5:1 needed for text under 18 pt. Fix: text on tints uses `#8F2C57` (6.5:1). Applied.

## Improvements
- **High: data marks are too pale.** Chart lines and dots in `#EE8DB3` are 2.3:1 on white, and the pale fills `#F6CADB` are 1.5:1. Fix: lines, dots and strokes use `#C24578` (about 4.7:1); pale pinks stay for fills and never carry meaning alone. Not yet applied in the mockups. Implement in code.
- **High: the Journal was decorative.** Tape, ruled lines and a tilted polaroid did not serve the job of looking back. Fix: redesigned as native list, entry screen and calendar, with large title, search and filter. Applied.
- **High: small tap targets.** Text links ("Change", "Why", "Undo", "Bring it back", "Details") are shorter than 44 pt in the mockups. Fix: every tappable text gets a 44 x 44 pt hit region.
- **High: Saved was a full screen.** Fix: a bottom sheet with a grabber, Undo, and Done (two variants: kept, let go). Applied.
- **Medium: back buttons said "Back".** Fix: chevron plus the parent's title. Applied.
- **Medium: the Journal had no search.** Fix: search field under the title (kept text only; respects Quiet topics). Applied.
- **Medium: fixed pixel type in the mockups.** Implement with Dynamic Type and test the largest accessibility sizes; cards must reflow, not clip.
- **Medium: dark mode not drawn.** Derive from the tokens with semantic colors.
- **Medium: one color means one thing.** Pink currently means brand, action, selection and "your data". Judgment: let pink mean "you", keep the deep rose for actions, and use lilac only for "usual range" and the fertile window. Document in code as semantic color names.
- **Medium: motion.** The let-go burn animation must be optional, brief, cancellable, never the only carrier of meaning, and replaced by a static card under Reduce Motion.
- **Medium: destructive actions.** "Gone at once" and Delete need a confirmation with Cancel. Everything else relies on Undo or the 7-day rest.
- **Low:** a Done button on modal screens uses the prominent style; the Watch screens need a check on Always-On display.

## Craft notes
- Typography: system face for controls, a serif only in her own words (the content layer). Good.
- Signature element: the figure with the pulse. Boldness is spent there and nowhere else.
- Removed accessories: tape, ruled lines, the "Nothing this day" filler. Blank days are absent from the list and plain in the calendar.
- The legend and counts on charts say something true (n, usual range, uncertainty), not decoration.

## What works
- Three tabs, single-word labels, filled icons. Tabs navigate; actions live in toolbars and sheets.
- One-tap capture on Now with a short path to saving.
- Calm copy: no apologies, no guilt, no alarms. Uncertainty is always shown.
- Nothing is conveyed by color alone (words, labels and numbers accompany every mark).
- Honest empty and early states ("Not yet", "[n] days").

## Platform notes
iOS 26 and watchOS. Use standard components for bars, sheets, lists, search and toggles. Liquid Glass belongs only to the system's floating layer (tab bar, toolbars); never put blur in content cards.
