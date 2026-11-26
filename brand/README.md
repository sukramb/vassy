# Vassy brand

Everything the app, the website and the social images share. `tokens.json` holds the
values; this page says how they are used.

## Mark

Three bars that narrow from top to bottom: a queue shrinking to the one answer that is
yours. Together they draw a V. The top two bars are the same colour at reduced
opacity, the bottom bar is always the accent.

| File                    | Use                                                        |
| ----------------------- | ---------------------------------------------------------- |
| `logo/mark.svg`         | On light backgrounds                                       |
| `logo/mark-on-ink.svg`  | On dark backgrounds                                        |
| `logo/mark-mono.svg`    | One colour, takes `currentColor` (menus, toolbars)         |
| `logo/icon.svg`         | Mark on the ink tile; the favicon                          |

- Keep clear space of one bar height around the mark.
- Do not recolour single bars, rotate the mark or change the bar widths.
- Below 20 px use `icon.svg` or `mark-mono.svg`; the opacity steps need the contrast.

## Wordmark

"Vassy" set in Instrument Serif, regular, letter-spacing −0.02em, in ink or paper.
In a lockup the mark sits to the left, as tall as the cap height plus a little, with a
gap of about a fifth of the mark's width.

## Colour

| Token            | Value     | Use                                                  |
| ---------------- | --------- | ---------------------------------------------------- |
| `paper`          | `#F3EFE6` | Page background                                      |
| `paper-2`        | `#EAE5D9` | Alternate sections, footer                           |
| `ink`            | `#17150F` | Text, primary buttons, icon tile                     |
| `ink-2`          | `#57524A` | Body text on paper                                   |
| `ink-3`          | `#8C867A` | Labels, meta text                                    |
| `accent`         | `#B4460B` | Emphasis on light: italic headline words, links      |
| `accent-on-ink`  | `#FDBA74` | The same accent on dark surfaces and in the mark     |
| `accent-soft`    | `#F6D9BF` | Tinted cards                                         |
| `good`           | `#15803D` | Recommendations, done states                         |
| `task`           | `#1D4ED8` | "Your task" badges, focus rings                      |
| `night`          | `#12110D` | Dark sections, terminal blocks                       |

One accent per view. `good` and `task` are status colours, not decoration. The three
`project-*` colours only tag demo projects.

## Type

| Role    | Face             | Notes                                              |
| ------- | ---------------- | -------------------------------------------------- |
| Display | Instrument Serif | Headlines; italic in the accent colour for emphasis |
| Text    | Geist            | Body and buttons                                   |
| Mono    | Geist Mono       | Kickers, code, meta lines                          |
| UI      | SF Pro (system)  | Anything that shows the app's own interface        |

All three web fonts are under the SIL Open Font License and are served from
`site/fonts`.

## Surfaces

The app panel is shown as frosted glass: a translucent white gradient with a
30 px backdrop blur, a light border and soft coloured light behind it (orange, pink,
teal). Everything else is flat paper or ink.

## Generated files

`scripts/brand.sh` renders these from the sources in this folder:

| Output                        | Source         |
| ----------------------------- | -------------- |
| `site/og.png` (1200×630)      | `og.html`      |
| `site/icon-512.png`, `site/apple-touch-icon.png` | `icon.html` |
| `Resources/AppIcon.icns`      | `appicon.html` |

The website also has three colour variants for comparison, reachable with
`?theme=neon`, `?theme=ember` and `?theme=frost`. The standard look described here is
the one without a parameter.
