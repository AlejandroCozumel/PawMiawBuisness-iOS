# PawMiaw Business — web provider workspace, visual spec for the iOS port

Source: `/Users/usuario1/code/pawmiaw-web` (React + Tailwind v4), read on 2026-11-04 at commit 33c5df56.
Every value below is read from the code, not from screenshots. 1rem = 16px = 16pt. "Phone" = < 640px (`max-sm`);
the provider top bar and sidebar switch at 768px (`md`). Colours are given as `token` light / dark.
Mixed colours (`color-mix(in srgb, A p%, B)`) are pre-computed to hex. "α" = the colour at that alpha.

---

## 0. Foundations

### 0.1 Theme switching
- Dark mode is a user choice stored in `localStorage.theme`; **default is light and it does not follow the system**
  (`src/routes/__root.tsx`). The root gets class `dark` + `data-theme="dark"`.
- `ProviderShell` sets `data-workspace="provider"` on `<html>` → `--canvas` becomes `--provider-canvas` (cool grey, not the family app's cream).
- The garden/organic radius switch is **off** (`--organic: 0`, `src/styles/organic-radius.css`): every corner below is even.

### 0.2 Fonts (`src/styles.css` lines 1–66)
| Role | Family | Weights loaded | Notes |
|---|---|---|---|
| Headings, titles, big numbers, time column, modal titles, empty-state titles | **Fredoka** (`font-heading`) | **600 only** | Every heading renders SemiBold even where CSS asks for 400. |
| Everything else | **Nunito Sans** (`font-sans`) | 400, 500, 600, 700, 800 | Body default 16px, line-height 1.5, `-webkit-font-smoothing: antialiased`. |

Tailwind sizes used: `text-xs` 12/16, `text-sm` 14/20, `text-base` 16/24, `text-lg` 18/28, `text-xl` 20/28, `text-2xl` 24/32, `text-3xl` 30/36.
Arbitrary sizes seen constantly: 0.6rem = 9.6, 0.62rem = 9.9, 0.66rem = 10.6, 0.68rem = 10.9, 0.7rem = 11.2, 0.72rem = 11.5, 0.8rem = 12.8, 0.8125rem = 13, 0.95rem = 15.2.
Weights: medium 500, semibold 600, bold 700, extrabold 800. `leading-tight` = 1.25, `leading-none` = 1.

**Micro-label (eyebrow) pattern** — appears everywhere (sidebar groups, table heads, strips, stat tiles, status chips):
uppercase, extrabold 800 (sometimes bold 700), 10–11.5pt, letter-spacing 0.10–0.16em, colour `--ink-soft`.
SwiftUI: `.font(Theme.text(11, weight: .heavy)).textCase(.uppercase).tracking(11 * 0.12)`. (tracking em → pt = size × em.)

### 0.3 Core colour tokens (`src/styles.css` :root lines 68–325, dark lines 327–503)
| Token | Light | Dark | Use |
|---|---|---|---|
| `--provider-canvas` (= `--canvas` in the workspace) | `#f5f7fb` | `#121214` | Page background behind cards, also behind modals |
| `--surface` | `#ffffff` | `#1c1c1e` | Cards, top bar, inputs, menus |
| `--surface-strong` | `#ffffff` | `#242428` | |
| `--surface-muted` | `#f5f8fb` | `#242428` | Tracks of segmented controls, muted chips, hover |
| `--border-soft` | `#dce4ed` | `#3a3a40` | Every 1px border and divider |
| `--border-strong` | `#bfccdc` | `#54545c` | Hover border |
| `--ink-strong` | `#10223b` (navy) | `#f2f2f7` | Primary text |
| `--ink-soft` | `#66758a` | `#aeaeb8` | Secondary text, labels, icons |
| `--brand-teal` (PAW Blue; name is historical) | `#006afc` | **`#9acefa`** | Actions, selection, links |
| `--brand-teal-strong` | `#0054ca` | `#c6e3fd` | Link hover, linked badge text |
| `--brand-teal-fixed` | `#006afc` | `#006afc` | Wordmark-type blue that never flips (avatars, BusinessMark) |
| `--on-brand-teal` / `--primary-foreground` | `#fffdf9` | **`#10223b`** | Text on a blue fill |
| `--brand-aqua` | `#9acefa` | `#9acefa` | |
| `--brand-lime` (MIAW Yellow) | `#fdb40e` | `#fdb40e` | |
| `--brand-mango` | `#fca51f` | `#fca51f` | Amber "needs someone", focus ring (`--ring`) |
| `--brand-coral` | `#d63c2f` | `#d63c2f` | Unread badge, required mark |
| `--destructive` | `#d63c2f` | **`#ff8a6f`** | Errors, late, red badges |
| `--brand-pink` | `#f5c2d9` | same | |
| `--brand-butter` | `#ffe07a` | same | Default modal accent |
| `--brand-lavender` | `#dccbff` | same | |
| `--brand-apricot` | `#ffc18f` | same | |
| `--brand-cocoa` | `#3d1f14` | same | |
| `--accent-card-ink` | `#10223b` | `#10223b` | Text/glyph on any bright pastel fill, both themes |
| `--selected-accent-ink` | `#fffdf9` | `#10223b` | Glyph on a saturated accent fill (module-header icon) |
| `--pet-face` / `--pet-face-ink` | `#f1e4d0` / `#3d1f14` | same | Pet with no photo |
| `--input` | `#e6edf2` | `#303036` | Dark input fill = `#303036` 30% over surface → `#222225` |
| `--muted-foreground` | = ink-soft | = ink-soft | Placeholders |

Status scale (`src/lib/provider-colors.ts`, tokens in styles.css):
| State | Fill light | Ink light | Fill dark | Ink dark |
|---|---|---|---|---|
| upcoming | `#9acefa` | `#10223b` | `#9acefa` | `#10223b` |
| waiting | `#fca51f` | `#10223b` | `#fca51f` | `#10223b` |
| active | `#006afc` | `#ffffff` | `#5b9dff` | `#10223b` |
| done | `#30a46c` | `#10223b` | `#4cc38a` | `#10223b` |
| problem | `#d63c2f` | `#ffffff` | `#ff7a6b` | `#10223b` |
| closed | `#66758a` | `#ffffff` | `#8b96a8` | `#10223b` |

Category hues (`--hue-*`, fill / ink-on-wash light / ink dark): sky `#5aa9f5` `#0d4f94` `#b0d4fa`; lavender `#c08ae8` `#5b2da6` `#e2ccf7`;
mint `#86cf8e` `#1b6630` `#bfe8c3`; peach `#ff9447` `#93400a` `#ffc18f`; butter `#ffd43b` `#6f5200` `#ffe07a`; teal `#35c3be` `#0c5f5c` `#a5e4e0`;
periwinkle `#8b93f7` `#343ca8` `#c9ccfc`; grey `#c9d2dd` `#3b4656` `#d5dce6`. Fills are the same in dark.
Triage: critical `#e5484d`/`#ff6369`, urgent `#f5a524`/`#ffb224`, stable `#30a46c`/`#4cc38a`.

Activity hues on Home (`ACTIVITY_HUE`): appointments sky, grooming lavender, stays periwinkle, hospital teal, home mint; "All" = `--brand-teal`.

### 0.4 Radii (`src/styles/radius.css`, `organic-radius.css`)
| Token | Value | Used for | SwiftUI |
|---|---|---|---|
| `--radius-card` (`rounded-card`) | **28** | every card, panel, module header, modal, menu of the account | `Theme.cardRadius` |
| `--radius-box` (`rounded-box`) | 16 | bordered box/row inside a card, dropdown, notice | `Theme.boxRadius` |
| `--radius-field` (`rounded-field`) | 16 | inputs, selects, textareas, switch cards | `Theme.fieldRadius` |
| `--radius-chip` | 14 | small tiles, menu items, grid blocks | `Theme.chipRadius` |
| `--radius-tick` | 6 | checkboxes, swatches | |
| `--radius-button` | 24 | every Button → a full capsule at 36/40/44/48 tall | `Capsule()` |
| `--radius` | 20 | toasts, the visit row's ⋯ menu | |
| `rounded-full` | 999 | pills, chips, avatars, icon buttons, segmented tracks, search fields | `Capsule()` / `Circle()` |
IconBadge "garden blobs" are forced to circles in the workspace (styles.css 1717–1730).

### 0.5 Shadows
| Token | Light | Dark | SwiftUI |
|---|---|---|---|
| `--shadow-card` | `0 18px 36px rgba(16,34,59,.08)` | `0 22px 44px rgba(0,0,0,.32)` | `.shadow(color: navy.opacity(0.08), radius: 18, y: 18)` (CSS blur 36 ≈ SwiftUI radius 18) |
| `--shadow-floating` | `0 24px 48px rgba(16,34,59,.14)` | `0 28px 56px rgba(0,0,0,.42)` | menus, popovers |
| `shadow-sm` (Tailwind) | `0 1px 3px rgba(0,0,0,.1), 0 1px 2px -1px rgba(0,0,0,.1)` | same | selected segment, icon badge |
| sidebar active | `0 10px 22px rgba(0,106,252,.14)` | none | |

### 0.6 Motion
- Cards enter with `.rise-in`: opacity 0→1, translateY 12→0, 700ms `cubic-bezier(.16,1,.3,1)`.
- Module header fold: height 340ms `cubic-bezier(.22,1,.36,1)`; content `.swap-in` 260ms fade + 4px lift.
- Modal open: opacity 0→1, scale .96→1, rotate −0.6°→0, 240ms spring `cubic-bezier(.34,1.56,.64,1)`; phone: translateY 32→0.
- Default control transitions 180ms ease.

### 0.7 Icons
lucide-react line icons, stroke 2, never filled. Sizes: 16 (`size-4`, the default in buttons and rows), 14 (`size-3.5`), 12 (`size-3`, inside chips),
18 (module header on phone), 20 (bell), 24 (module header ≥ 640), 28 (empty-state well).
SwiftUI: use the lucide SVGs as template images (or SF Symbols with `.fontWeight(.regular)` and outline variants only; never `.fill`).

---

## 1. Page frame (phone first)

Files: `src/components/app/provider-shell.tsx`, `src/components/app/page-shell.tsx`, `src/styles.css` 827–953.

### 1.1 Phone top bar (`ProviderMobileTopBar`, shown < 768)
One white bar, sticky at the top. **There is no bottom tab bar on the web provider side.** Navigation = the sidebar sheet (§7).
- Container: height **56**, padding-x **16**, item gap **12**, background `--surface` (`#ffffff` / `#1c1c1e`), bottom border 1px `--border-soft`, z-index 40, sticky.
- Left to right:
  1. **Sidebar toggle**: 28×28 circle, 1px `--border-soft` border, `--surface` fill, lucide `PanelLeft` 16, ink `--ink-strong`.
  2. **Wordmark** image `/pawmiaw-wordmark.svg` height **32** (≈163 wide; aspect 1519:298); "PAW" `#006afc`, "MIAW" `#fdb40e`, same in dark.
     On a sub-page this slot becomes a back link instead: `ChevronLeft` 16 + parent page name, 14 bold, `--brand-teal`.
  3. flexible spacer
  4. **Search**: 36×36 circle, 1px `--border-soft`, `--surface`, lucide `Search` 16, `--ink-strong`.
  5. **Bell**: 36×36 circle, 1px `--border-soft` (turns **`--brand-coral` `#d63c2f`** while anything is unread), `--surface`, lucide `Bell` **20**, `--ink-soft`.
     Count badge: min 20×20 capsule at top −6 / right −6, fill `#d63c2f`, text white 10.4pt (0.65rem) bold, 1.5px `--surface` ring; "9+" above 9.
  6. **Language pill**: 72×36 capsule, 1px `--border-soft`, `--surface`, **`--shadow-card`**, lucide `Languages` 14 in `--brand-teal` at x=10, "ES"/"EN" 12 bold tracking-wide `--ink-strong`, grey chevron 16 at right 14.4.
     (A global `select` rule forces 40 right padding, leaving ≈4pt for the code inside 72; check the live page — the code may show clipped.)
- Note: at 390 wide these items add up to ≈395pt in a 358pt row; on iOS keep the wordmark ≈ 26–28pt tall so the row fits.
- Optional second row (`MobileSwitcherRow`, only with several locations or businesses): border-top 1px, padding 16 / 6; a capsule switcher:
  1px border, `--surface`, padding 4 left / 12 right / 4 vertical, gap 8; BusinessMark 28 circle; name Fredoka 14; location 12 semibold `--ink-soft` with `MapPin` 12; `ChevronsUpDown` 16 at 70%.
- SwiftUI: custom `HStack` in a `safeAreaInset(edge: .top)`, not a `NavigationBar` title; `Divider` colour `borderSoft`.

### 1.2 Desktop / iPad top bar (`ProviderDesktopTopBar`, ≥ 768)
Height **52**, padding-x 20 (24 ≥ 1024), gap 12, `--surface`, bottom border. Sidebar toggle (28 circle) → wordmark height 24 →
1×20 vertical rule `--border-soft` → breadcrumb: 12 semibold, uppercase, tracking 0.12em, `--ink-soft`, "/" separators, current crumb `--ink-strong`, earlier crumbs link (hover blue).
Right: search **bar** (36 tall, 224 wide / 288 ≥ 1024, capsule, 1px border, `Search` 16 + "Buscar pacientes, clientes…" 14 `--ink-soft` + `⌘K` key cap 24 tall radius 16 `--canvas` fill 11.2 bold), language pill, bell.

### 1.3 Canvas and page padding
- Canvas `#f5f7fb` / `#121214` everywhere behind cards (including behind modals/sheets).
- `PageShell layout="contained"` = `.page-wrap.page-shell.page-shell-contained`:
  - width `min(1680, 100% − 32)` → **16 side gutter on phone**; `100% − 48` (24 gutter) from 1024.
  - padding top **32**, bottom **64**.
  - gap between top-level sections **32** (`gap: 2rem`).
- `PageSection` (`.page-section`): vertical stack, gap **22.4** (1.4rem) between its children.
- Home's board uses its own stack: gap **16** between the day switcher, the header, the agenda card, "Te necesita" and the "all clear" line.
- There is **no large page title**. The first thing on every module page is the module header card (§2).

### 1.4 Desktop/iPad layout
Sidebar docked at ≥ 768 (width 256, collapsible to 48 icon rail), content inset to its right. Home on ≥ 1280 (`xl`): agenda card and "Te necesita" side by side (aside 352 wide, top-aligned).

---

## 2. Module header card (`ProviderModuleHeader`, `src/components/app/provider-module-header.tsx`)
The page's title block: a card with an accent-tinted gradient, round accent icon, Fredoka title, one line of context, actions, and a grid of stat tiles.

Card: radius **28**, 1px `--border-soft`, `--surface`, `--shadow-card`, clip.

**Open state, top block**
- Padding phone 16 h / 12 v; ≥ 640: 24 h / 16 v (20 v when the card is ≥ 896 wide).
- Background: `linear-gradient(105deg, accent 13% → accent 4% at 45% → surface at 80%)`. Pre-mixed:
  | accent | 13% | 4% | (dark 13% / 4%) |
  |---|---|---|---|
  | `--brand-teal` | `#deecff` | `#f5f9ff` | `#2c333b` / `#212327` |
  | `--brand-aqua` | `#f2f9fe` | `#fbfdff` | `#2c333b` / `#212327` |
  | `--brand-lime` | `#fff5e0` | `#fffcf5` | `#39301c` / `#25221d` |
  | `--brand-mango` | `#fff3e2` | `#fffbf6` | `#392e1e` / `#25211e` |
  | `--brand-pink` | `#fef7fa` | `#fffdfd` | `#383236` / `#252325` |
  | `--brand-butter` | `#fffbee` | `#fffefa` | `#3a352a` / `#252422` |
  | `--triage-stable` (Finanzas) | `#e4f3ec` | `#f7fbf9` | `#22322c` / `#1e2322` |
  SwiftUI: `LinearGradient(stops: [.init(color: wash13, location: 0), .init(color: wash4, location: 0.45), .init(color: surface, location: 0.8)], startPoint: UnitPoint(x: 0, y: 0.37), endPoint: UnitPoint(x: 1, y: 0.63))`.
- Phone grid: `[icon] [title, flexible] [fold button]` on one row, gap 12; subtitle on its own line below.
  - Icon: circle **36** (56 at ≥ 640), fill = accent, 1px border (= `--brand-teal` whenever the accent is a `--brand-*` colour, else the accent itself), `shadow-sm`,
    glyph 18 (24 at ≥ 640) in `--selected-accent-ink` (`#fffdf9` light / `#10223b` dark).
  - Title: Fredoka 600, **20** (24 ≥ 640, 30 when card ≥ 896), leading 1.25, `--ink-strong`, truncates on phone.
  - Fold button: 36 circle, 1px `--border-soft`, `--surface`, `ChevronUp` 16 `--ink-soft` (rotates 180° folded).
  - Subtitle: **13** medium, `--ink-soft`, 1 line on phone (`line-clamp-1`), first letter capitalised; 14 on ≥ 640.
- Actions: on phone a horizontally scrolling row under the title (bleeds to the card edges, inner padding 16), gap 8.
  Every action is a button forced to **36 tall**, padding-x 14, 14pt (§9.1). ≥ 640: inline at the right of the title, wrapping.

**Stat tiles grid** (under a 1px top border)
- 1px hairlines between tiles (grid gap 1 on a `--border-soft` background).
- Columns: 2 on phone (≥ 4 stats; 3 stats → 3 columns "dense"; 5 stats → the 5th spans both), 4 or 5 in one row when the card is ≥ 672/896 wide.
- Tile: `--surface`, padding phone 12 h / 8 v (16/14 ≥ 640, 20/16 ≥ 896), top-aligned column.
  - Row: icon badge **20** circle (28 ≥ 640) fill = stat accent, glyph 12 (14) in `--accent-card-ink` navy (white/navy `--selected-accent-ink` when the accent is `--brand-teal`); 1px border as above; gap 6.
  - Label: **9.6pt** extrabold uppercase tracking 0.04em, 1 line, `--ink-soft` (≥ 640: 10.6pt, tracking 0.1em, 2 lines).
  - Value: Fredoka **18** leading 1 (24 ≥ 640), `--ink-strong`; `--destructive` when it needs attention. Margin-top 4 (8 ≥ 640).
  - Hint: 11.2pt (12 ≥ 640) `--ink-soft`, 1 line, margin-top 2.
  - Selected (filter on): tile bg `--surface-muted` 70% → `#f8fafc` / `#222225`, plus a **3pt bar** in the stat accent along the bottom edge.
  - Muted: text at 55% opacity.

**Folded state** (remembered per page): one row, padding 16/10, gradient `accent 10% → surface 35%`;
title row (icon 36 + Fredoka 20), stats become 32-tall capsule chips (1px border, padding-x 12, gap 6: 8 dot in accent, label 12 bold `--ink-soft`, value Fredoka 14;
active chip border `--brand-teal` + fill teal 10% `#e6f0ff` / `#292e34`), actions 36 tall, fold button.

`footer` slot (optional) sits under the stats inside the same card.

---

## 3. Section cards

### 3.1 Standard card (the default container on every page; ~110 uses)
`rounded-card border border-soft bg-surface shadow-card overflow-hidden`: radius **28**, 1px `#dce4ed` / `#3a3a40`, white / `#1c1c1e`, `--shadow-card`.
Inner structure: header row `padding 16 h / 12 v` + 1px bottom border; toolbars `padding 16/12` each with a bottom border; list rows with 1px dividers; a footer row with a top border.
`garden-card` = the same radius only. SwiftUI: `RoundedRectangle(cornerRadius: 28).fill(surface).overlay(RoundedRectangle(cornerRadius: 28).stroke(borderSoft, lineWidth: 1)).shadow(color: navy.opacity(0.08), radius: 18, y: 18)`.

Legacy `.play-panel` (2px border, same radius/shadow) is used once (`ProviderPageToolbar`, with `.mobile-flat-panel` → on phone no border, no radius, no shadow, transparent, padding 0).

### 3.2 "Te necesita" block (`Block` in `src/components/app/today/today-board.tsx` 1261–1287)
Used for **Por cobrar**, **Quedaron abiertas en días anteriores**, **Seguimientos pendientes**, Notas por firmar, Reservas por confirmar, Solicitudes por responder.
- Card: radius 28, padding **14**, `--shadow-card`.
  - Neutral: 1px `--border-soft`, `--surface`.
  - **Amber attention** (`attention`): **2px** border mango 70% α (`#fdc062` over white / `#b97c1f` over dark), fill mango 12% (`#fff4e4` / `#372c1e`), dividers mango 35% α (`#fee0b1` / `#6a4c1e`).
  - **Red attention** (`attention='red'`, e.g. Por cobrar with earlier days): 2px destructive 70% α (`#e2776d` / `#bb6957`), fill destructive 12% (`#fae8e6` / `#372928`), dividers 35% α (`#f1bbb6` / `#6b423a`), hint text bold `--destructive`.
- Header row (margin-bottom 4, space-between): left = disc **28** circle + title 14 **extrabold** `--ink-strong` (gap 8); right = count 14 extrabold tabular `--ink-strong`.
  - Disc fill = tone 20% (35% when attention); glyph 16 inherits `--ink-strong` (navy), not the tone.
    | tone | 20% | 35% |
    |---|---|---|
    | mango | `#feedd2` / `#49371e` | `#fee0b1` / `#6a4c1e` |
    | aqua | `#ebf5fe` / `#35404a` | `#dceefd` / `#485a6b` |
    | teal (Seguimientos) | `#cce1fe` / `#35404a` | `#a6cbfe` / `#485a6b` |
    | destructive | `#f7d8d5` / `#49322e` | `#f1bbb6` / `#6b423a` |
- Hint (optional): 12 `--ink-soft`, margin-bottom 4.
- Rows: 1px dividers; each row padding 6 v: title 14 **bold** `--ink-strong` (truncate), hint 12 `--ink-soft`, optional note 12 wrapping.
  Row buttons on the right: `Button size=compact variant=outline` → **40 tall** capsule, 2px blue border, 14 medium, icon 14 (e.g. "Sí vino", "Abrir", "Cobrar", "Firmar", "Responder").
  Follow-up rows instead: two **32** circle icon buttons (1px border, `Smartphone`/`MessageCircle` 14 in `--brand-teal`).
- Footer (margin-top 8): link "**Ver todo · 3 más**" 12 **bold** `--brand-teal` (underline on hover), or "3 más" 12 `--ink-soft`.
- Icons: Por cobrar `Receipt`, Quedaron abiertas `AlertTriangle`, Seguimientos `CalendarClock`, Notas `NotebookPen`, Reservas `Globe`, Solicitudes `MessageCircle`.

### 3.3 "Te necesita" link line (`LinkLine`, 1364–1377)
A one-line card linking to a page (Estancias, Hospital, Stock, Te deben, Domicilio tarde…).
Radius 28, 1px `--border-soft`, `--surface`, padding 14 h / 12 v, gap 12, `--shadow-card`; hover border `--brand-teal`.
Disc **32** circle: neutral `--surface-muted` fill + glyph 16 `--brand-teal`; attention: destructive 12% (`#fae8e6` / `#372928`) + glyph `--destructive`.
Title 14 bold `--ink-strong`; hint 12 `--ink-soft` (bold `--destructive` when attention). No chevron.

### 3.4 "Te necesita" column
`aside`, stack gap **12**; heading "Te necesita" Fredoka **18** `--ink-strong`, padding-x 4. Red items are moved to the top.
When nothing: one line "All clear" — `BadgeCheck` 16 `--brand-teal` + 14 semibold `--ink-soft`, padding-x 4.

### 3.5 Notices
- Inline notice (`Notice`, `inventory-bits.tsx`; same in Rx): radius 16, **1.5px** border state 55%/border-soft, fill state 10%, padding 12, gap 10, 14 `--ink-strong`, icon 16 top-aligned.
  | tone (state) | fill | border |
  |---|---|---|
  | danger (problem) | `#fbecea` / `#332526` | `#d98884` / `#a65d58` |
  | warn (waiting) | `#fff6e9` / `#322a1e` | `#eec17c` / `#a5752e` |
  | good (done) | `#eaf6f0` / `#212d29` | `#7dc1a6` / `#448569` |
  | info (upcoming) | `#f5fafe` / `#292e34` | `#b8d8f4` / `#6f8ba6` |
- Page banner (Home clock check): radius 16, 1px mango 45%/border (`#eac890`), fill mango 14% (`#fff2e0` / `#3b2f1e`), padding 16/12, `Clock` 16, bold first sentence 14.
- Modal note (client sheet): radius 16, 1px aqua 55%/border, fill aqua 16%, padding 16/12, 14 **semibold** leading-relaxed, `Info` 16 `--brand-teal`.
- Schedule "Familias pidiendo un cambio": radius 28 card, 1px pink 40% (`#e6d6e5`), fill pink 8% (`#fefafc`), padding 16, eyebrow 12 extrabold uppercase tracking .12em; inner rows radius 16 white `shadow-sm`, padding 12/8.
- Day-closure strip inside a card: full-width row, padding 16/8, 14 semibold, fill mango 12% `#fff4e4` or pink 12% `#fef8fa` or `--surface-muted`.

---

## 4. Home: the day board (`src/components/app/today/*`, `src/routes/provider.index.tsx`)

Order on a phone: (banners) → **day switcher row** → **"Hoy" module header** → **Agenda card** → **"Te necesita"** → all-clear line.

### 4.1 Day switcher ("‹ Hoy ›", `HomeDaySwitcher` in `home-day.tsx`)
Phone: its own row above the header, left-aligned. Capsule: 1px `--border-soft`, `--surface`, padding 4, gap 4 → **42 tall**.
- Arrows: 32 circles, `ChevronLeft/Right` 16 `--brand-teal`, hover `--surface-muted`.
- Middle, today: "Hoy" 14 **bold** `--ink-soft`, min-width 88, padding 12/4, centered.
- Middle, another day: capsule fill teal 12% (`#e0edff` / `#2b3138`), text 14 bold `--brand-teal` ("mar 5 nov"), tap returns to today.

### 4.2 "Hoy" header (module header with category tiles)
- Icon `CalendarClock`, accent `--brand-teal`. Title "Hoy" + " · martes, 4 de noviembre" in **Nunito 11pt (0.55em) semibold `--ink-soft`** on the same line.
- Actions (36 tall): "Sin cita" outline (`Zap`), "Nueva cita" solid (`CalendarPlus`). Day switcher is inline here only ≥ 640.
- Stats = one tile per activity when the business does more than visits (2 columns on phone, 3 rows for 6):
  Todos (`LayoutGrid`, `--brand-teal`), Citas (`CalendarClock`, sky `#5aa9f5`), Estética (`Scissors`, lavender `#c08ae8`), Estancias (`BedDouble`, periwinkle `#8b93f7`),
  Hospital (`Hospital`, teal `#35c3be`), Domicilio (`House`, mint `#86cf8e`). Tapping selects the activity (selected tile = muted bg + 3pt bottom bar).
  Hints: one line each ("2 tarde", "3 salen hoy"…); value red when late.
- Visits-only business: four filter tiles instead — Visitas de hoy (aqua), En espera (mango), Con el veterinario / En servicio (teal), Por cobrar (pink).

### 4.3 Agenda card
Standard card (§3.1). Children, top to bottom:
1. **Header row**: padding 16/12, bottom border, wrap, space-between.
   Left: "Agenda" Fredoka **18** `--ink-strong` (+ a "✕ Ver todo" capsule when filtered: fill `--surface-muted`, 12 bold `--ink-soft`, padding 10/2, `X` 12).
   Right (gap 6): **Todos | Mías** segmented + a ⋯ button (32 circle, `MoreHorizontal` 16 `--ink-soft`, hover `--surface-muted`).
   - Segmented: capsule track `--surface-muted` (`#f5f8fb` / `#242428`), **no border**, padding **2**; segments min-height 32, padding-x 14, 14 **bold**;
     selected = `--surface` fill + `shadow-sm` + `--ink-strong`; other = `--ink-soft`. Total 36 tall.
2. **Status tabs** (only when the header shows activities): row padding 16 h / 8 v, bottom border, gap 4, horizontal scroll, no scrollbar.
   Each tab: **32 tall** capsule, padding-x 12, gap 6, **12 bold**; label + count (tabular).
   - Selected ("Todo 0"): fill **`--ink-strong`** (navy `#10223b`; in dark `#f2f2f7`), text `--surface` (white; in dark `#1c1c1e`), count at 80% opacity.
   - Others: no fill, text `--ink-soft`, count `--ink-strong`; hover `--surface-muted`.
   Tabs: Todo · En espera · Con el veterinario (or "En servicio") · Por cobrar.
3. **Service filter** (only under Citas with several services): same row geometry, pills **28 tall**, padding-x 12, 12 bold; selected navy fill as above, others `--surface-muted` fill + `--ink-soft`.
4. **Section strips** (`HomeStrip`) — "AHORA 2", "POR COBRAR 1", "PRÓXIMAS 5", "ESTANCIAS 2 · Abrir estancias ›", "ESTÉTICA", "DOMICILIO", "HOSPITAL":
   - Full-width band, padding 16 h / 6 v (≈ 29 tall), fill `--surface-muted` 55% (`#fafbfd` / `#202024`; hover 85% `#f6f9fc`), bottom border between strips.
   - Content: **8 dot** in the section colour, label, count — all **11.2pt extrabold uppercase tracking 0.12em `--ink-soft`**, gap 8.
   - Optional link right after: "Abrir estancias" normal case, no tracking, `--brand-teal`, padding-x 8, `ChevronRight` 14.
   - `ChevronDown` 16 at the far right (rotates −90° when folded). The whole band folds/unfolds the section (remembered).
   - Dot colours: Ahora `--brand-teal`, Por cobrar `--brand-pink`, Próximas `--brand-aqua`, Estancias periwinkle, Estética lavender, Hospital `#35c3be`, Domicilio mint.
5. **Rows** (`VisitRow` in `visit-row.tsx`; `HubRow`, `GroomRow`, `HomeVisitRow` in `home-hub.tsx` share the geometry). Dividers 1px `--border-soft`.
   - **Left edge bar 3pt** full row height in the state colour; content starts 16 from the card edge (13 padding after the bar); right padding 12; vertical padding 12; gap 12 h / 10 v.
   - Edge colours (visits): upcoming `--brand-aqua`, waiting `--brand-mango`, in service `--brand-teal`, to pay `--brand-pink`, late/missed `--destructive`, done `--border-soft`.
     Stays: arriving aqua, in house teal, leaving pink, late `--destructive`, left `--ink-soft`. Hospital: admitted pink, waiting mango. Grooms: stage tone.
   - **Date/time column** 84 wide (5.25rem): time **Fredoka 15.2** tabular, leading 1.25, `--ink-strong` (a late stay shows "3 nov" instead);
     under it (margin 2) state 11.2 **bold** in the state colour ("En espera", "Por cobrar"…) — or the clock: "Espera 25 min" (mango, red ≥ 20 min), "Lleva 12 min" (teal), "15 min tarde" (red).
   - **Avatar 40** (§9.6 pet face) or a pet stack (overlap −10, 2pt surface ring).
   - Text block (flex 1): line 1 **16 bold** `--ink-strong` "Luna" + " · Consulta general" **regular `--ink-soft`** (truncate);
     line 2 (margin 2) **12.8** `--ink-soft` "Ana López · con Dra. Ruiz · Consultorio 1" + `BellOff` 14 at 60% when the family isn't on the app;
     optional arrival note 12 italic; chips row (margin-top 6, gap 6, wraps).
   - Chips (§9.3): "Debía llegar el 3 nov · no ha llegado" (danger, `AlertTriangle` 12), "Asignado a ti" (info, aqua 22% `#e9f4fe`), "Sin asignar" (info),
     "Alergia: …" (danger), "Nota por firmar" (warn), "En línea" (lavender 30% + `Globe` 12), bill chip with `CircleDollarSign` 12.
   - Action (visits): on phone a full-width line under the text, indented **96** (84 + 12): `Button outline` **36 tall**, padding-x 16, flex 1, icon 16 + label
     ("Registrar llegada", "Empezar", "Terminar", "Cobrar $500.00"); then a ⋯ 36 circle (`MoreHorizontal` 16 `--ink-soft`) pushed right. ≥ 640: inline at the right.
     Hub rows (stays/hospital) have no button: the whole row is tappable with a `ChevronRight` 16 `--ink-soft` at the end.
   - Hover/pressed: fill `--surface-muted` 45% (`#fafcfd` / `#202022`). Done/missed rows at 75% opacity.
6. **"Listo · 3"** fold row: top border, padding 16/10, 14 extrabold `--ink-strong` (+ " · Sin realizar: 1" bold `--ink-soft`), `ChevronDown` 16.
7. Empty: `ProviderEmptyState` inline (§9.9) "Nada agendado para hoy" with Sin cita / Nueva cita / "Abrir la agenda" link buttons.

---

## 5. Switchers, tabs, chips, date controls

### 5.1 View switcher Día / Semana / Lista (`Segmented`, `src/routes/provider.schedule.tsx` 723–742)
Capsule track: 1px `--border-soft`, fill `--surface-muted`, padding 4, gap 4 → **42 tall**.
Segments: padding 14 h / 6 v (32 tall), gap 6, **14 bold**, icon 16 (`Rows3` Día, `CalendarDays` Semana, `List` Lista).
Selected: **solid `--brand-teal`** fill, text/icon `--on-brand-teal` (`#fffdf9`; dark: pale `#9acefa` fill with navy text), `shadow-sm`. Others `--ink-soft`.
Same look: "Personal | Espacios", the agenda list's "Próximas | Pasadas | Todas" (grid of 3 equal).

### 5.2 Page tabs Clientes / Pacientes (`Segmented tabs`, `src/routes/provider.clients.tsx` 238–256)
Capsule track: 1px `--border-soft`, fill `--surface-muted`, padding 4, height **40**.
Segments: full height (32), padding-x **16**, gap 6, **14 bold**, icon 16 (`UsersRound`, `PawPrint`).
Selected: **`--surface` fill (raised white) + `shadow-sm` + `--ink-strong`**; others `--ink-soft`. (Species "Todos/Perros/Gatos/Otros" reuses it at 36.)
`CatalogSegmented` (Catálogo/Inventario): same idea, 40 tall, track `--surface-muted` 80% (`#f7f9fc`), padding 3, count bubble.

### 5.3 Filter chips — three looks
**A. Wash chip** (`FilterChip`, clients/patients and agenda list):
- **36 tall** capsule, **1.5pt** border, padding-x 12, gap 6, **14 bold**; optional 8 dot or 14 icon tinted `chip 70% + ink-strong`.
- Off: border `--border-soft`, fill `--surface`, text `--ink-soft`.
- On: fill chip 26%, border chip 75% mixed with `--ink-strong`, text `--ink-strong`.
  | chip | on fill | on border | icon |
  |---|---|---|---|
  | teal (Todos / Vistos en 30 días) | `#bdd8fe` / `#3d4a57` | `#0458cc` / `#b0d7f9` | `#0554c2` |
  | lime (Clientes activos, En PawMiaw) | `#feecc0` / `#56441a` | `#c29019` / `#fac448` | `#b6881c` |
  | lavender (Prospectos, No en PawMiaw, En línea) | `#f6f1ff` / `#4e4a58` | `#a9a1ce` / `#e2d5fd` | `#9f98c4` |
  | pink (Deben dinero, Pidieron cambio) | `#fceff5` / `#54474f` | `#bc9ab2` / `#f4cee0` | `#b092aa` |
  | mango (Vencen esta semana, Vacunas vencidas, Doble reserva) | `#fee8c5` / `#56401e` | `#c18426` / `#fab855` | `#b57e27` |
  | aqua (Todos, patients) | `#e5f2fe` / `#3d4a57` | `#78a3ca` / `#b0d7f9` | `#719ac1` |
  | ink-soft (Archivados) | `#d7dbe1` / `#424246` | `#506076` / `#bfbfc8` | `#4c5c72` |
- Chips sit in a horizontal `ScrollRow`: gap 8, edge fades 40 (left) / 48 (right) from `--surface`, 28 circle arrow buttons (1px border, `--surface`, shadow `0 2 8 rgba(0,0,0,.14)`).
  A 1×24 `--border-soft` rule separates the chips from a following select (36 capsule select, bold).

**B. Toned chip/tab** (`CatalogFilterChip accent`, Store tabs, Catalog/Pharmacy/Staff/Rooms/Finance): uses `TONE_FILLS`.
- 40 tall capsule, 1px border, padding-x 14 (8 left with icon), 14 bold. Icon in a **24 circle**.
- Off: `--surface` fill, `--border-soft` border, `--ink-soft` text, icon circle = tone 24% with glyph `TONE_FILLS` light deep shade (dark: tone 70% + ink).
- On: fill + border = **deep shade**, text **white**, icon circle white 20%; count bubble 20 tall: white fill with deep-shade text (off: deep fill, white text).
- `TONE_FILLS` (light / dark): page tab `--brand-teal` `#0054ca`/`#1f63ad`; sky `#0d4f94`/`#1f63ad`; teal `#0c5f5c`/`#127a76`; mint `#1b6630`/`#237a3a`;
  butter `#6f5200`/`#7d5d00`; peach `#93400a`/`#a34a10`; lavender `#5b2da6`/`#6b3dbb`; periwinkle `#343ca8`/`#4048bd`; grey `#3b4656`/`#4a5668`;
  status upcoming `#1b6fb3`/`#1a73c0`, waiting `#ad5700`/`#b85c00`, active `#0054ca`/`#1f63ad`, done `#1a7f4f`/`#218358`, problem `#c8372b`/`#cc4130`, closed `#4a5668`/`#525e70`, expired `#7a1f1f`/`#be3b53`.
- Store tabs (`store-tabs.tsx`): track = capsule **2px** `--border-soft`, `--surface`, padding 4, gap 2; tabs min 44×44, padding 10 left / 16 right, gap 8, 14 bold, icon circle 28 with 16 glyph;
  selected deep `#0054ca` + white; **on phone the unselected tabs show the icon only**.

**C. Plain wash chip** (`CatalogFilterChip` without accent): 40 tall, 1px border, on = border tone + tone 12% fill + `--ink-strong`, count bubble tone fill white text.

### 5.4 Date navigator (Schedule, "‹ Hoy ›")
Same capsule as §4.1 (1px border, `--surface`, padding 4, gap 4, 42 tall), arrows 32 circles `--brand-teal`, middle "Hoy" 14 bold —
`--ink-soft` when on today, `--brand-teal` (hover muted) when elsewhere. No middle fill.

### 5.5 Date field pill
`DatePickerField` trigger: **48 tall**, radius **16**, 1px `--border-soft`, `--surface`, padding-x 16, gap 12, value 14 `--ink-strong` (placeholder `--ink-soft`),
`CalendarDays` 16 `--ink-soft` at the right; hover border `--brand-teal`; invalid border `#d63c2f` + 3px coral 20% ring.
In the Schedule toolbar it is a **40-tall capsule**, width 176 (208 in week view, showing "3–9 nov").
Popover: radius 17.6, 1px border, padding 8, calendar cells 36.

---

## 6. Inputs and the provider modal

### 6.1 Text input (`src/components/ui/input.tsx`)
**48 tall**, radius **16**, 1px **`--border-soft`** (grey, not blue), fill `--surface` (dark `#222225`), padding 16 h / 12 v,
text **16 on phone** / 14 ≥ 768, `--ink-strong`; placeholder `--ink-soft`.
Focus: border **`--ring` = mango `#fca51f`** + 3pt ring mango 50% α. Invalid: border `--destructive` + 3pt ring destructive 20%.
Read-only: fill `--surface-muted`, text `--ink-soft`. Disabled 50% opacity.
SwiftUI: `TextField` in `.padding(.horizontal,16).frame(height:48).background(surface).overlay(RoundedRectangle(cornerRadius:16).stroke(focused ? mango : borderSoft, lineWidth: 1))` + an outer 3pt `mango.opacity(0.5)` stroke when focused.

### 6.2 Search field
`ProviderToolbarSearchField`: the input as a **capsule**, 48 tall (40 in card toolbars), left padding 44, `Search` 16 `--ink-soft` at x 16, vertically centred.
Agenda list search: 48 capsule, padding-left 36, icon at x 12. Placeholder e.g. "Cliente, mascota, correo o teléfono".

### 6.3 Select / menu trigger
- `NativeSelect`: 48 tall, radius 16, 1px `--border-soft`, `--surface`, padding 16 left / 40 right, 14 regular, `ChevronDown` 16 `--ink-soft` at right 16.
  Toolbar variant: **40 capsule, bold**; chip-row variant: 36 capsule, bold; pagination page size: 36 capsule.
- Plain `<select>` anywhere: chevron drawn at right 14.4 (16×16, stroke 2.25, `#66758a` / `#aeaeb8`), padding-right 40.
- `Select` (base-ui) trigger: 32 tall, radius 16, 1px `--input` border, padding 10 / 8, 14.

### 6.4 Textarea
Min height **112**, grows with content, radius 16, 1px `--border-soft`, padding 16/12, 16/14pt, same focus as inputs.

### 6.5 Labels
- Default (`Label`, 27 of 31 provider modals): **14 medium (500)**, leading 1, sentence case, `--ink-strong`; required mark "*" `--brand-coral`.
  Label → control spacing **8**; fields in a grid with gap **16** (2 columns ≥ 768). Field error: 12 medium `--brand-coral`, margin-top 8.
- Store/Inventory/Pharmacy modals (`FieldLabel`): **12 bold uppercase tracking 0.12em `--ink-soft`**, margin-bottom 6; "· opcional" normal case.
- Page toolbar field label: 11.5 bold uppercase tracking 0.16em `--ink-soft`.

### 6.6 Switch / toggle rows
- `Switch`: track **32×18.4** capsule, thumb 16 white; **on = emerald `#059669`** (dark `#10b981`), **off = pale red `#fecaca`** (dark `rgba(248,113,113,.4)`). Thumb slides 14.
- `SwitchCard`: full-width row, radius 16, 1px `--border-soft`, `--surface`, padding 12, gap 16; label semibold 16 `--ink-strong`, description 14 `--ink-soft`; switch at the right; hover `--surface-muted`.
- Modal yes/no row (`.provider-modal-toggle`): radius 16, **1.5px** `--border-soft`; checked = border aqua 70% (`#aed5f6`) + fill aqua 18% (`#edf6fe` / `#333c46`); butter/pink tones likewise.

### 6.7 Provider modal (`src/components/app/provider-modal/provider-modal.tsx` + `.css`)
One frame for every workspace form. **No close X** (outside tap, Escape, swipe down, or Cancel). Unsaved changes → "¿Descartar los cambios?" compact pink modal.

**Phone (< 768) = bottom sheet**
- Full width, max height **94% of the screen**, top corners **28**, no bottom border, 1.5px frame border = accent 55% mixed with border-soft, fill `--surface`,
  shadow `0 −20 60 −30 ink-strong 40%`. Backdrop: `--ink-strong` 28% α + blur 4 (dark: that is a **light** veil, `#f2f2f7` 28%).
- **Header** (also the drag handle): fill **accent 26%** over surface, bottom border **1.5px accent 45% + border-soft**, margin-bottom 20, padding-top 8.8.
  Grab handle: 41.6 × 4.8 capsule at top 8, centered, `--ink-strong` 22% α.
  Heading row padding **16**, gap 16, wraps; title row gap 13.6:
  - **Pebble**: circle **38.4** (44 desktop), fill accent 72%, rotated **−4°**, glyph 20.8 `--ink-strong` (counter-rotated +4°).
  - Title: Fredoka 600 **20** (23.2 desktop), leading 1.1, tracking −0.01em, `--ink-strong`.
  - Description: 13.1 (0.82rem), leading 1.4, colour ink-strong 72% (`#536072` / `#b6b6ba`), margin-top 4.8.
  - Steps (when multi-step): on their own full-width row below the title, left-aligned (§6.7 steps).
  - Badge (desktop only): white capsule 12 bold padding 12.8/6.4.
- **Body**: scrolls, padding 0 16 16.
- **Footer**: border-top 1.5px `--border-soft`, `--surface`, padding 14.4 h-16, bottom max(14.4, safe area); buttons **stacked, full width, primary on top** (column-reverse), gap 12.
- **Accent pre-mixes** (header 26% / header border / frame border / pebble 72% / desktop sticker 70%α):
  | accent | header | hdr border | frame | pebble | sticker |
  |---|---|---|---|---|---|
  | butter (default; client step) | `#fff7dc` / `#574f36` | `#ece2b9` / `#93855a` | `#efe2ae` / `#a69560` | `#ffe99f` / `#bfa960` | `#ffe9a2` |
  | pink (pet step, discard) | `#fceff5` / `#54474f` | `#e7d5e4` / `#8e7785` | `#ead1e2` / `#a18594` | `#f8d3e4` / `#b894a5` | `#f8d4e4` |
  | aqua (sheet frame default; teal is remapped to aqua) | `#e5f2fe` / `#3d4a57` | `#bedaf3` / `#657d94` | `#b8d8f4` / `#6f8ba6` | `#b6dcfb` / `#779cbc` | `#b8ddfc` |
  | mango | `#fee8c5` / `#56401e` | `#eac890` / `#916a31` | `#eec17c` / `#a5752e` | `#fdbe5e` / `#bd7f1f` | `#fdc062` |
  | lime | `#feecc0` / `#56441a` | `#ebce89` / `#92712a` | `#eeca72` / `#a57d24` | `#fec951` / `#be8912` | `#feca56` |
- **Sections** (`ProviderModalSection`): title Fredoka 600 **16.8**, gap 9.6, margin-bottom 14.4; icon chip **30.4** square with radius **12**, fill section colour 45%
  (sky/aqua `#d2e9fd`, butter `#fff1c3`, pink `#fae4ee`, neutral `#eff3f7`; dark `#556c81`/`#827447`/`#7e6772`/`#2a2a2d`), glyph 16 `--ink-strong`.
  Stacked sections are split by a **2pt dashed `--border-soft` line**, margin-top 4, padding-top 21.6. Two columns ≥ 768 with a dashed vertical line (24 + 24).
  `ProviderSheetSection` variant: heading Fredoka 16.8 leading-tight, hint 14 `--ink-soft` margin-top 4, stack gap 12, same dashed split.
- **Footer buttons** (`ProviderModalAction`): **44 tall**, padding-x 20, **14 semibold**, capsule.
  primary = solid `--brand-teal` + 2px `--brand-teal` border + `--on-brand-teal` text; secondary = outline (2px blue border, blue text, `--surface`);
  danger = 2px `--destructive` border, destructive 10% fill (`#fbecea`; dark 20% `#49322e`), destructive text. Desktop: Cancel left, actions right; 1px lift on hover.
- **Steps** (`ProviderModalSteps`): gap 18.4 between steps; dot **27.2** circle, `--surface` fill, inset 1.5px ink-strong 14% ring, "01" 10.9 extrabold `--ink-soft` (or a 14.4 icon);
  done dot = `--brand-teal` fill, white `Check` 16; current = same blue dot inside a **33.6-tall capsule** (padding 3.2 left / 13.6 right, `--surface`, 1.5px ink-strong 10% ring)
  with the step name 12.5 bold `--ink-strong`; connectors 10.4×2, ink-strong 18% (blue when done).

**Desktop/iPad**: centered card, widths compact 608 / medium 704 / form 800 / wide 1024 (max screen − 48), max height min(90%, 992), radius 28,
plus a **sticker shadow** `0 12 0 −5 accent 70%` (a solid coloured lip under the card) + `0 34 80 −34 ink-strong 40%`; header padding 18.4 × 24; body padding 0 24 24; footer padding 14.4 × 24, row.

SwiftUI: `.sheet` with `.presentationDetents([.large])`, `.presentationCornerRadius(28)`, `.presentationDragIndicator(.hidden)` (draw the handle yourself inside the tinted header), `.interactiveDismissDisabled(dirty)`.

---

## 7. Sidebar (iPad / desktop; also the phone's slide-in sheet)
File: `provider-shell.tsx` 184–680, `src/components/ui/sidebar.tsx`, `locations/workspace-switcher.tsx`.

- Width **256** docked (≥ 768), collapsible to a **48** icon rail; on phone a sheet from the left **288** wide over a black 10% + blur backdrop.
- Background `--provider-sidebar-bg` = aqua 10% (**`#f5fafe`**) / dark `#1c1c1e`; right border 1px `--border-soft`.
- Section borders `--provider-sidebar-border` = teal 14% + border-soft (`#bdd3ef` / `#3a3a40`).

**Header (business switcher)**: padding 12, bottom border. Row: radius 16, padding 8, gap 12, hover fill = control bg (`#eff7fe` / `#242428`).
BusinessMark **40** circle (logo on white with 2pt inset, or initials 12 extrabold white on `#006afc`); name **Fredoka 16** leading-tight `--ink-strong`;
location line 12 semibold `--ink-soft` (`#66758a`) with `MapPin`/`Layers` 12; `ChevronsUpDown` 16 at 70%.
Menu: width min(352, screen − 32), radius 28, 1px border, padding 8, `--shadow-floating`; rows radius 28, padding 8, gap 12, 36 circle thumbs; group labels 10.9 extrabold uppercase tracking .14em `--ink-soft`.

**Nav list**: panel padding 8 h / 12 v.
- Group label: height 32, padding-x 12, **10.9 extrabold uppercase tracking 0.16em**, `--ink-soft` (`#66758a`). Between groups a 1px separator inset 8, margin 8 v.
- Items: stack gap **4**; each **32 tall capsule**, padding-x 12, **2pt** transparent border, gap 8, icon **16**, label **14 regular** `#66758a`.
  - Hover: fill `#eff7fe` (aqua 16%), text `--ink-strong`.
  - **Selected**: fill **`#006afc`**, **2pt border `#b19e55`** (lime 70% + blue: a muted gold edge), text/icon **`#fffdf9` bold**, shadow `0 10 22 rgba(0,106,252,.14)`.
    Dark: fill `#4c5e6f` (teal 34% over `#242428`), border `#7fa0be`, text `--ink-strong`, no shadow.
  - Count badge: right-aligned, **20 tall** min-width 20 capsule, padding-x 6, fill `--destructive` (`#d63c2f` / `#ff8a6f`), **10.9 extrabold white**, "99+" cap.
    Collapsed rail: 16 badge on the icon's top-right with a 2pt sidebar-bg ring.
- **Order and icons (lucide)**, Spanish labels as shown:
  - **OPERACIÓN**: Inicio `Building2` · Agenda `CalendarDays` · Estancias `BedDouble` · Hospital `Hospital` · Estética `Scissors` · Paseos y clases `Dog` · Domicilio `House` ·
    Clientes y pacientes `UsersRound` · Pendientes de volver `BellRing` · Invitaciones `MailPlus` · Expedientes `FileText` · Olfato AI (custom `OlfatoVetIcon`, corgi in a vet coat)
  - **COBROS**: Tienda `ShoppingCart` · Inventario `Boxes` · Farmacia `Pill` · Catálogo `Package` · Cuentas `Receipt` · Finanzas `Coins`
  - **NEGOCIO**: Suscripción `CircleDollarSign` · Ajustes `Settings` · Equipo `ShieldCheck` · Disponibilidad `Clock3` · Espacios `DoorOpen` · Sedes `MapPin`
  - Items hide by business type/permission (Estancias only for boarding/daycare/sitter, Hospital only vet/emergency, Estética only groomer, Paseos only walker/trainer, etc.).
  - Badges on: Expedientes (to complete), Farmacia, Estancias (late), Hospital (doses), Estética (needs someone), Domicilio (late), Cuentas (por cobrar).
- **Footer (user row)**: padding 12, top border. Button full width, radius **16**, 1px control border (`#c2d5ef`), fill control bg (`#eff7fe`), padding 10 h / 8 v, gap 8;
  avatar **28** (photo, or initials 9.9 bold white on `#006afc`); first name 14 semibold. Hover = selected blue fill + white text.
  Menu: min-width 240, radius 28, padding 8: 40 avatar + name 14 semibold + email 12; items "Mis mascotas" `PawPrint`, theme, "Tu cuenta" `UserRound`, "Cerrar sesión" `LogOut` (red).
- Olfato AI page: the nav slides out (−24 + fade, 200ms) and the chat list slides into the same panel.

SwiftUI iPad: `NavigationSplitView` sidebar with `.listStyle(.plain)`, custom row view (capsule background), `scrollContentBackground(.hidden)` on `#f5fafe`.

---

## 8. Module pages: header accent and icon

Default accent (no `accent` prop) = **`--brand-teal`** (`#006afc`; dark `#9acefa`). Header icon ≠ sidebar icon on several pages (marked ◆).

| Page (sidebar label) | Header icon (lucide) | Header accent |
|---|---|---|
| Inicio ("Hoy · fecha") | `CalendarClock` ◆ | `--brand-teal` |
| Inicio, another day | `CalendarDays` (past/today) / `CalendarCheck2` (ahead) | butter (past) / lavender (ahead) |
| Agenda | `CalendarDays` | teal (default) |
| Visit page (`/appointments/:id`) | pet photo, fallback `PawPrint` | `--brand-aqua` |
| Estancias | `BedDouble` | teal (default) |
| Hospital | `BedDouble` ◆ | `--brand-pink` |
| Hospital patient | `PawPrint` | `--brand-pink` |
| Estética | `Scissors` | `--brand-pink` |
| Paseos y clases | `UsersRound` ◆ | `--brand-lime` |
| Domicilio | `House` | `--brand-aqua` |
| Clientes y pacientes | `UsersRound` | `--brand-lime` |
| Client page | `UsersRound` (or photo) | `--brand-lime` |
| Pet page | `PawPrint` (or photo) | `--brand-aqua` |
| Pendientes de volver | `BellRing` | teal (default) |
| Invitaciones | `MailPlus` | `--brand-aqua` |
| Expedientes | `FileText` | `--brand-aqua` |
| Record page | record-type icon | `--brand-aqua` |
| Olfato AI | no module header: a 56-tall chat bar (`OlfatoVetIcon` 28, Fredoka 18 title, 12 subtitle, "Nuevo chat" 40 button) | — |
| Tienda | `ShoppingCart` | teal (default) |
| Inventario | `Boxes` | teal (default) |
| Farmacia | `Pill` | teal (default) |
| Catálogo | `Package` | `--brand-mango` |
| Cuentas | `Receipt` | teal (default) |
| Finanzas | `Banknote` ◆ | `--triage-stable` (`#30a46c` / `#4cc38a`) |
| Suscripción | `CircleDollarSign` | the plan's accent (starter butter, business sky, clinic lavender), else teal |
| Ajustes | `Settings` | teal (default) |
| Notificaciones | `Bell` | `--brand-aqua` |
| Equipo | `UsersRound` ◆ | `--brand-pink` |
| Staff member | photo, fallback `UserRound` | role hue (owner butter, admin sky, vet mint, support peach, reception lavender) |
| Disponibilidad | `Clock3` | `--brand-aqua` |
| Espacios | `DoorOpen` | teal (default) |
| Sedes | `MapPin` | teal (default) |
| Por reubicar | `ArrowRightLeft` | `--brand-mango` |
| Tu cuenta | `UserRound` | `--brand-aqua` |

Icon fill = the accent itself (solid), glyph white (light) / navy (dark), 1px border `#006afc` for any `--brand-*` accent.

---

## 9. Recurring pieces

### 9.1 Button (`src/components/ui/button.tsx`) — known, summary
Capsule (radius 24). Text **14 medium (500)**, icon 16, gap 6, padding-x 16.
Heights: default **48**, compact **40** (toolbars, rows), module-header actions **36**, modal footer **44**, `sm` 28 (rare).
- default/primary: fill `--brand-teal`, text `--primary-foreground` → **light: blue `#006afc` + `#fffdf9`; dark: sky `#9acefa` + navy `#10223b`**. No border.
- outline: **2px** `--brand-teal` border, `--surface` fill (dark: `#222225`), `--brand-teal` text; hover teal 8% (`#ebf3ff`).
- destructive: 2px `--destructive` border, destructive 10% fill, destructive text.
- ghost: no border/fill, hover `--surface-muted`.
- Disabled 50% opacity; pressed moves down 1px; focus ring mango 50% 3px.

### 9.2 IconBadge (`icon-badge.tsx`) — known, summary
Circles: sm 40, md 44, lg 56; 1px border; `accent` tone = solid accent fill; `soft` tone = `--surface-muted` fill + `--border-soft` border.

### 9.3 Small chips (`Chip` in `visit-row.tsx`, `HubChip` in `home-hub.tsx`)
Capsule, padding 8 h / 2 v, **11.2 bold**, gap 4, icon 12, truncates.
| tone | fill | text |
|---|---|---|
| muted | `--surface-muted` `#f5f8fb` / `#242428` | `--ink-soft` |
| danger | destructive 12% `#fae8e6` / `#372928` | `--destructive` `#d63c2f` / `#ff8a6f` |
| warn | mango 25% `#fee8c7` / `#543e1e` | `--ink-strong` |
| good | lime 30% `#fee8b7` / `#604a19` | `--ink-strong` |
| info | aqua 22% `#e9f4fe` / `#38434e` | `--ink-strong` |
Variants: OnlineMark lavender 30% `#f4efff` + `Globe` 12; PendingMark 1.5pt **dashed** `--status-waiting` border, no fill; groom stage pill = stage tone 24% + 6 dot;
TriageBadge 1px triage-colour border, 22% fill (14% critical), 11.2 extrabold uppercase tracking .08em, `Siren` 12.

### 9.4 Status chip (`ProviderStatusChip`) — known, summary
Capsule, **2px** border, padding 12/4, **11.5 bold uppercase tracking 0.12em**. State: fill = border = status colour, text = status ink.
Brand tones lime/mango/aqua/pink: brand fill + **2px `#006afc` border** + navy text; teal: blue fill + lime border.

### 9.5 Tag chips on rows
- Client link badge (`ProviderClientLinkBadge`, xs): capsule, 1px, padding 8/2, **9.9pt uppercase tracking 0.12em**, gap 6, icon 12.
  "SOLO EN LA CLÍNICA": `Building2`, `--border-soft` border, **transparent** fill, **semibold** `--ink-soft`.
  "FAMILIA VINCULADA": `Link2`, border teal 55% (`#63a1f5` / `#6f8ba6`), fill teal 12% (`#e0edff` / `#2b3138`), bold `--brand-teal-strong` (`#0054ca` / `#c6e3fd`).
- Client status pill (only Prospecto/Archivado): 1px border tone 70% + border, fill tone 24%, 9.9 bold uppercase tracking .12em; lead = lavender (`#f7f3ff` fill, `#dcd2fa` border).
- Context badge (`.provider-context-badge`): min 36 tall, radius 14.4, 1px aqua 55%, fill aqua 12%, 12 semibold; icon square 26.4 radius 9.6, aqua 35%.
- Catalog `KindChip`/`Flag`: 20 tall capsule, 10.9 extrabold, 6 dot / 1px tone 45% border + tone 10% fill.

### 9.6 Avatars
- **Pet** (`PetAvatar`): circle sm 32 / **md 40** / lg 48 / xl 64; photo cropped, or **`#f1e4d0` fill with a `#3d1f14` lucide species glyph** (Dog, Cat, Bird, Rabbit, Fish, Turtle, Rat; else `PawPrint`), glyph = half the size. Same in dark.
- Pet stack: overlap −10, each ring 2pt `--surface`, fallback initial Fredoka on aqua 30% (`#e1f0fe`).
- **Client initials** (list rows): **40** circle, fill **lime 25% `#feecc3`** (dark `#54421a`), first **two letters** of the name, **14 bold Nunito** `--ink-strong`.
- Person (staff): circle with 2pt `--surface` border, solid fill aqua/lime/mango, initials Fredoka 11.5 bold navy.
- Account: 28 (bar/sidebar) / 40 (menu), initials white on `#006afc`.

### 9.7 List / table rows (clients, patients, agenda list)
**Clients list on the web phone is a horizontally scrolling table** (min width 896) inside the standard card — the first column is what a phone sees.
- Card toolbar (phone, stacked, padding 16/12, gap 12, bottom border): Clientes/Pacientes tabs (40) → search capsule (40, pl 44) → sort select (40 capsule bold).
  Then a filter row (padding 16/12, bottom border) of wash chips (§5.3 A), then (optional) "Vencen esta semana" strip (mango 12% fill, 14, link bold blue).
- Table head: fill `--surface-muted` 55% (`#fafbfd` / `#202024`), bottom border; cells padding 16 / 8, **10.6 extrabold uppercase tracking 0.12em `--ink-soft`**:
  CLIENTE · MASCOTAS · CONTACTO · ÚLTIMA VISITA · PRÓXIMA VISITA · DEBE · NOTAS.
- Row: cell padding 16 / 12, body 14, divider 1px; whole row tappable, pressed fill `--surface-muted`.
  - Client cell: initials avatar 40 (§9.6) + gap 12 + name **14 bold** `--ink-strong` (blue on hover) + under it (margin 2, gap 4) status pill and the link badge ("SOLO EN LA CLÍNICA").
  - Pets cell: wrap, gap 6, **pet chips**: capsule, 1px `--border-soft`, `--surface`, padding 2 left / 10 right / 2 v, gap 6, pet avatar **24** (glyph 14), name **12 bold** `--ink-strong`
    (search match: border `--brand-teal`, fill teal 12%).
  - Contact: phone 14 `--ink-strong` + two 28 circles (`Phone`, `MessageCircle` 14 `--ink-soft`).
  - Last visit "4 nov" `--ink-soft`; next visit bold `--ink-strong`; owes bold `--destructive`; "—" `--ink-soft` when empty; open chevron 32 circle (≥ 768).
- Patients row: pet avatar 40, name 14 bold + "Alergia" chip (destructive 12%, 10.6 extrabold, `AlertTriangle` 12) / "Vacuna vencida" (mango 30%) / "Archivada";
  meta 12 `--ink-soft` "Perro · Labrador · 3 años · Chip 123"; owner cell = client avatar + name + "🔗 PawMiaw" 12 bold blue.
- iOS mapping: a `List` row per client = HStack(avatar 40, VStack(name 14 bold, HStack(tags)), Spacer, chevron) + a wrapping row of pet chips under it; keep the table head's uppercase style for any section header.
- **Pagination footer**: top border, padding 16/12, space-between, wraps.
  Left: "**12 clientes**" 14 bold tabular `--ink-strong` + " · Página 1 de 2" 14 `--ink-soft`.
  Right (gap 8): page-size select **36 capsule** (10/25/50) + ‹ › **36 circles**, 1px `--border-soft`, chevron 16, disabled 40% opacity, hover border blue.
- Agenda list rows (`agenda-list.tsx`): grid `60 | 1fr`, padding 16/12, time Fredoka 15.2, pet avatar, name bold + "service · client" 12 `--ink-soft`; day headers = band `--surface-muted`, padding 16/8, 14 bold ("Hoy" in blue + " · 4 nov").

### 9.8 Dropdown menus
Web menus: radius 16 (or 20 on visit rows), 1px `--border-soft`, `--surface`, padding 6, `--shadow-floating`, min width 192–224;
items radius 14 (14.4 on visit rows), padding 10/8, **14 semibold**, gap 8, icon 16; destructive items `--destructive` after a 1px separator.
Item highlight = `--accent` = **mango `#fca51f` fill with cocoa `#3d1f14` text** (shadcn default, not overridden). On iOS use native `Menu`.

### 9.9 Empty state (`ProviderEmptyState`) — known, summary
Panel: radius 28, **2px dashed** `--border-soft`, `--surface`, padding 24 × 48 (phone 16 × 36), centered. Inline: no card, padding 24 × 36 (16 × 28).
Well **56** circle, accent 22% (aqua `#e9f4fe`, teal `#c7defe`, pink `#fdf2f7`, mango `#feebce`, lime `#ffeeca`), glyph 28 `--ink-strong`.
Title Fredoka **20** leading-tight, margin-top 12; body 14 `--ink-soft` max width 512, margin-top 4; actions margin-top 20 (16 phone), gap 8, capsules 40 (36 phone).

### 9.10 Toasts (sonner, `src/components/ui/sonner.tsx`)
Top-right (top, full width on phone), radius **20**, rich colours, icon 16:
success fill teal 14% `#dbeaff` / `#2e353d`, border `#80b1f3`, text `--brand-teal`, `CircleCheck`;
error destructive 14% `#f9e4e2` / `#3c2b29`, border `#d99898`, text `--destructive`, `OctagonX`;
info aqua 16% `#eff7fe`, border `#bcd9f3`, text `--brand-teal`, `Info`;
warning mango 16% `#fff1db`, border `#ecc486`, text `#ba8027`, `TriangleAlert`.

### 9.11 Skeletons
Fill border-soft 72% (`#e6ecf2` / `#323236`) with a moving highlight band (58% wide, tilted 8°, gradient clear → white 68% → aqua 38% → clear, 1.45s linear loop).
Shapes match what loads: header 144 tall radius 28, board 384 radius 28, rows 56 radius 16, grid slots 48 radius 14, chips radius 999. Full-page wait = paw loader (5 parts pressing in sequence).

### 9.12 Agenda grid (Día/Semana)
Inside a standard card, scroll area max 75% of the screen; **30-minute slots 64 tall** with 1px dividers, time gutter 72 wide, 11.2 semibold `--ink-soft` right-aligned.
Column header detail 11.2 semibold uppercase tracking .08em. Blocks: radius 14, 1px `--border-soft` + **4pt left border in the status colour**, fill status 12% for waiting/active/done
(`#fff4e4`, `#e0edff`, `#e6f4ed`) else `--surface`, `--shadow-card`, padding 8/6; title 14 bold, line 2 12 `--ink-soft` "10:00–10:30 · Consultorio";
requested (online) = 2pt **dashed** status border on white. Now line: 1px `--destructive` with an 8 dot at its left. Columns min 224 (day) / 144 (week).

### 9.13 Dividers
Solid 1px `--border-soft` between rows and sections of a card; **2pt dashed** `--border-soft` between sections inside modals; vertical 1×20/1×24 rules in bars and chip rows.
No dotted dividers in the provider workspace.

---

## 10. Dark mode quick reference (what changes besides the base tokens)
- Primary blue flips to pale sky `#9acefa` with navy `#10223b` text: buttons, view-switcher selection, step dots, links, header icon of teal pages.
- Navy-filled "Todo" tab becomes **white `#f2f2f7` with dark text**.
- Sidebar selected item: muted steel `#4c5e6f`, border `#7fa0be`, no shadow.
- Pastel fills (accents, status, hues, pet face) stay bright; text on them stays navy `#10223b`.
- Destructive becomes `#ff8a6f`; coral (bell, required mark) stays `#d63c2f`.
- Card shadow becomes `0 22 44 rgba(0,0,0,.32)`; modal backdrop is a light 28% veil.
