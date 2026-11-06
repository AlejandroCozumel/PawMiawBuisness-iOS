# PawMiaw Business iOS — the design kit (match the web)

Every business screen and sheet must look like its web page (`/Users/usuario1/code/pawmiaw-web`, `src/routes/provider*.tsx`).
The exact web values are in `design/WEB-DESIGN-SPEC.md`. This file says which shared iOS piece draws each web piece.
**A screen never draws its own card, chip, button, header, tab, icon or empty state: it uses these.** One shared component per
control, one look: the same control in two places is one piece in `Design/`, never a per-module variant. If something is missing,
add it (or a case of an existing piece) to `Design/`, matching the web, and list it here. A module keeps only its *data* (a
function that maps its model onto a kit piece, e.g. `stockStateChip(row)`, `teamRoleChip(role)`, `recordsTypeChip(kind)`).

## The frame
- Phone: the shell draws the web's top bar (sidebar button, wordmark, bell) and the slide-in sidebar. **There is no tab bar.**
  A section's root screen has its system navigation bar hidden: **no `.toolbar` items on a root screen** (they would not show).
  Move every root toolbar action into the page's `ModuleHeader` actions (or a card's header).
- A screen pushed from another (a visit, a client, a record…): `.providerPage(title)` (inline system bar with the back button)
  and its own `ModuleHeader` (with `media:` for a pet/person photo) as the first thing on the page. Toolbar items are fine there.
- Page body: `PageScroll { … }` (canvas `#f5f7fb`, 16 gutter, 20 between sections). Never a `List`/`Form` with system styling
  for a page: the web draws cards on the canvas.

## The page header (every page)
`ModuleHeader(icon:title:subtitle:accent:media:titleAccessory:stats:actionsOnRow:storageKey:) { actions } footer: { … }`
- `icon`/`accent`: the web page's `ProviderModuleHeader` props. For sections use `ProviderSection.x.headerIcon` / `.headerAccent`.
- Folding (web rule of 2026-11-04): an iPhone starts **folded**, an iPad open. Once someone folds or opens a page's header the
  choice is remembered for that page and wins (`storageKey`, stored as a Bool; never set = the default). Read while drawing, so a
  phone never flashes open; only a tap animates. **Every page passes a stable `storageKey`** (its page: "clients", "stay"…).
- `titleAccessory: AnyView`: badges beside the title (a client's status and link badge, a record's Draft/Signed, a pet's
  Archived). Wraps under the title on a phone. Never put status pills among the actions.
- `stats`: `[ModuleStat("key", label:, value:, hint:, icon:, accent:, attention:, active:, muted:, action:)]` — the web's `stats`
  array one to one (labels, hints, icons, accents, attention, active, onClick).
- Actions: `PMButton`s (they become 36 pt inside the header). Same order and variants as the web.
- Reference: `Modules/Schedule/ScheduleScreen.swift` (`header`, `headerStats`) — the screen the owner approved.

## Cards
- `SectionCard(title, subtitle:, icon:, accent:) { trailing } content: { … }` — the standard card with a header row and a hairline;
  content runs edge to edge (draw rows with `RowDivider()` between them and 16 side padding).
- `Card(padding:tint:spacing:flat:)` — a plain card (radius 28, 1 pt border, the card shadow); `tint` = an attention card;
  `flat: true` = no shadow (a card inside a card, a list of signed rounds).
- Lists (`Design/Lists.swift`): `ListCard(style: .card | .panel | .box) { rows }` or `.listCard(style)` on a stack — rows run
  edge to edge (`.card` = the standard card; `.panel` = web `ListPanel`, 2 pt edge, no shadow; `.box` = a 16-corner 2 pt box of rows
  in a sheet). `CardToolbar(spacing:) { … }` (a card's 16/12 strip over a hairline), `ListFooter(count:detail:) { trailing }`
  ("12 ventas · $4,300"), `ListCount(shown:total:one:many:)` ("Mostrando 25 de 81", words already localized), `LoadMoreRow(hasMore:busy:load:)`
  (the next 20 when the last row shows), `DayBand(title:lead:highlighted:trailing:style:)` (`.agenda` "Hoy · 4 de nov",
  `.records`, `.bills` with its count, `.caps` uppercase), `RowList(items:) { row }` (rows between hairlines).
- `SettingsCard(icon:tone:title:hint:note:) { rules } footer: { SaveBar(…) }` + `SettingsRule(icon:tone:title:hint:) { control }` —
  a service's settings (Estética, Domicilio). `SaveBar(dirty:working:saveTitle:floating:onDiscard:onSave:)` — "Cambios sin guardar"
  on mango with Descartar / Guardar (`size: .small` buttons); `floating` = its own card (Hospital's settings).
- `NeedsCard(title:icon:count:hint:tone:attention:more:seeAll:) { NeedsRow(title:hint:first:) { trailing } … }` — Home's "Te necesita" blocks.
- `LinkLine(title:icon:hint:attention:)` — a one-line card that opens a page.
- `BoardStrip(title:count:dot:linkTitle:link:folded:)` — a board's section band ("ESTANCIAS 2 · Abrir estancias ›").
- `EdgeRow(edge:time:timeNote:timeNoteColor:showsChevron:dimmed:) { … }` — a row with the 3 pt state edge and the 84 pt time column.
- `NoticeCard(tone:title:message:icon:look:byline:actionTitle:action:)` or `NoticeCard(tone:title:icon:look:) { content }` — every
  notice. Tones `.info .warning .problem .success .lime` (an Rx "all good") `.custom(color)`. `icon: ""` = the tone's own, `nil` =
  none. Looks: `.inline` (§3.5, 1.5 pt edge at 55%, wash 10%; no title = icon + text on one row), `.banner` (page banner: 1 pt edge
  at 45%, wash 14%, bold first sentence, one primary action — the clock check, a legal note), `.page` (the hospital page's notice:
  card corners, 2 pt edge, a white 40 disc, title + byline).
- `Eyebrow(text, size:, color:, tracking:)` — a micro-label. `SectionHeading(title:count:hint:dot:style:bubble:showsZero:) { action }`
  — a part's heading (Fredoka 18, or a 14 extrabold `.label` with a state dot, a count bubble). `StitchedDivider(lineWidth:)` — the
  2 pt dashed modal rule, or 1 pt `border-dashed`. `ProgressBar(value:height:width:track:fill:label:)` — a filling bar.
- `ContextPills(client:linked:pets:) { extra }` — whose visit/record a sheet is about (web `ModalContextPills`).
- `AttachmentTile(fileName:sizeText:isImage:isPDF:fileExtension:caption:isOpening:action:) { thumbnail }` — a file as a square
  tile (`caption` = name under it, the record page; without = inside it, a chart's history).
- `EmptyState(systemImage:title:message:actionTitle:action:accent:panel:)` — the web's empty state (`panel: true` = dashed card).
- `LoadingState`, `ErrorState`, `NoAccessState`.

## Controls
- `PMButton(title, systemImage:, trailingIcon:, variant:, size:, fullWidth:, isWorking:, tint:)`. Variants `.primary .outline
  .destructive .ghost` (no edge/fill, ink-strong; `tint` for a red "Rechazar") `.link` (blue bold words, no inset — 12 at `.slim`).
  Sizes `.regular` 48, `.modal` 44, `.compact` 40, `.header` 36, `.slim` 32 (Home's links, web `h-8`), `.small` 28 (web `size="sm"`).
  Never repaint a button. A row's action = `.outline` `.compact`. A `NavigationLink`/`Menu` drawn as a button:
  `{ PMButtonContent(title:icon:variant:size:) }.buttonStyle(.pm(variant, size:))`.
- `IconCircleButton(systemImage:label:tint:size:bordered:)` — the round icon control (⋯, a row's +, a ghost icon with
  `bordered: false`). `IconCircleLabel(systemImage:size:tint:bordered:)` — the same look as a `Menu`'s label (every ⋯ menu).
- `Segmented(options: [.init(value, title, icon:, count:, badge:, attention:, tone:)], selection:, look: .solid | .raised, label:, fill:)` —
  `.solid` = Día/Semana/Lista (blue, 42); `.raised` = page tabs and switches beside a 40 search (Clientes/Pacientes, Todos/Mías, the
  Records views, the Catalog's switch): white raised, or an option's `tone` (deep shade, white ink, its icon on a chip). `count` = a
  quiet number (iPad only), `badge` = a bubble (red with `attention`, else mango). `fill` = phones share the width and drop plain
  icons. Never a system segmented `Picker`.
- `ToneTabs(tabs: [.init(value, title, icon:, tone:, count:)], selection:, look: .toned | .solid, height:, label:)` — a page's tab
  bar in a 2 pt white capsule. `.toned` (Tienda, Farmacia, Finanzas): the open tab filled with its tone's deep shade, icons on 28
  chips, swapping count bubbles. `.solid` (Estancias, Hospital, Estética, Paseos, Domicilio at `height: 44`): the open tab PAW
  Blue, a pink count. On a phone the closed tabs show their icon only.
- `ChipTone` (Theme): `.page`, `.hue(Hue)`, `.state(ProviderState)`, `.expired` (+ `.waiting`, `.sky`… shorthands): the web's
  `TONE_FILLS` — `color` (tint) and `fill` (the deep shade, light/dark). The one table of those shades.
- `ToneChip(title, icon:, tone:, count:, dot:, isOn:)` — a 40 toned filter (§5.3 B); `ToneChip(title, icon:, plain: color, dot:, count:,
  countInk:, isOn:)` — the plain one (§5.3 C). `ToneMenuLabel(title:icon:tone:isOn:)` — a toned chip as a `Menu` label.
  `ToneIcon`, `ToneCount` — their icon chip and count bubble. `ChipRule()` — the 1 × 24 rule between chip groups.
- `StatusTabs(options:selection:)` — the board's "Todo 0 · En espera 0" tabs (navy chosen).
- `FilterChip(title:count:isSelected:tone:dot:icon:solid:action:)`, `FilterBar` — the web's wash chips (pass the web chip's colour
  as `tone`, its dot as `dot`; the count is 12 extrabold grey). `solid: true` = the notification feed's filter (2 pt edge, solid blue).
  `FilterChip(title:face:removeLabel:onRemove:)` — a choice made elsewhere, always on, with a ✕ ("Luna · Carmen").
- `FilterMenuLabel(title:selected:)` as a `Menu` label — a 36 capsule select. `PillField(text:)` — a 40 capsule value with a chevron.
- `DayStepper(isToday:todayTitle:washesAway:previous:today:next:)`, `PillDatePicker(text:date:zone:)` — ‹ Hoy › and the date pill
  (`washesAway`: Home's middle on a blue wash away from today).
- `SearchField(prompt:text:height:)` — the capsule search (48; 40 inside a card toolbar).
- Forms: `FormField(label:key:hint:form:optional:caps:required:strongHint:)`, `PMTextField(…, caps:, required:, strongHint:, number: .large/.plain,
  suffix:, lines:)`, `FieldLabel(title, caps:, required:, optional:)` — `caps` is the Store/Inventory/Pharmacy modals' 12 bold uppercase
  label (§6.5); `number` a bold tabular quantity box. `MoneyField`, `MenuField`, `ToggleRow` (the web SwitchCard), `PMSwitchStyle`
  (`.toggleStyle(PMSwitchStyle())` for any other `Toggle`), `ChoiceCards(options:selection:)` (the modal's yes/no rows) and
  `ChoiceCards(tiles:selection:)` (side-by-side tiles with an icon: Hembra/Macho, kg/lb), `DayField`/`TimeField`/`DateTimeField`.
  Inputs are grey-bordered, 48 tall, mango focus ring.
- `Tick(on:mixed:invalid:style:)` — `.checkbox` (20, the web Checkbox), `.choice` (24, the location/service lists), `.radio` (20 round).

## Chips, people, icons
- `StatusChip(text:state:outlined:small:)` — a status (uppercase, solid, 2 pt edge); `StatusChip(text:brand:small:)` — a brand tone
  ("ARCHIVADO" on MIAW yellow with the PAW Blue edge).
- `Chip(text:tone:icon:pending:dot:count:percent:ink:iconInk:iconSize:weight:border:outlined:ring:size:)` — **every small pill**:
  tones `.muted .danger .warn .good .info .online` (§9.3) or `.custom(color)` at `percent` (24 unless told; 100 = solid). `dot` (6),
  `count`, `border` (1 pt edge at that % — 1.5 at `.large`/`.header`), `outlined` (grey outline, no fill), `ring` (triage: uppercase,
  tone ring). Sizes `.small` 11.2 (a row's chip), `.medium` 12 at 24 (a role, a status tag), `.large` 12.8 at 28 (a state pill),
  `.wide` 14 at 28, `.header` 14 at 36 (a state among header actions: the Store's register). `Chip(text, color:, percent:, icon:, dot:)`
  is the short form for a status/hue colour.
- `DisconnectedMark(at:by:withDetail:)` — "Se desconectó de PawMiaw el 6 nov" / "Desvinculado el 6 nov" (web `DisconnectedMark`):
  the amber pill a client carries after an unlink, with the money line under it where there is room. Nothing while linked.
- `TagChip(text:icon:linked:tone:size: .xs/.sm/.header)` — "SOLO EN LA CLÍNICA" / "FAMILIA VINCULADA"; with `tone` a client status
  pill ("PROSPECTO" lavender). `HueChip(text:hue:systemImage:)` — a category (Lucide via `Glyph`). `CountBadge(count:)`.
- `Avatar(name:imageURL:size:tint:)` (client initials on yellow 25%), `PetAvatar(name:species:photoURL:size:)` (warm face, cocoa glyph),
  `PetChip(name:species:photoURL:)`, `PetStack`, `AccountAvatar`, `BusinessMarkView`, `IconBadge(icon:accent:size:iconSize:ink:washPercent:)`.
- Icons: **`Glyph("lucide-name", size:)`** — the web's Lucide icon by its kebab name (`CalendarDays` → `"calendar-days"`,
  `AlertTriangle` → `"triangle-alert"`). SF names still work (mapped). **Never `Image(systemName:)` on a screen**; in a `Menu`/`Label`
  use `GlyphLabel(title, icon:)`. If a Lucide icon is missing from `Assets.xcassets/Lucide`, report its name (don't add assets).

## Colours, type, shape
- `Theme.*` tokens only: `canvas`, `surface`, `surfaceMuted`, `borderSoft`, `inkStrong`, `inkSoft`, `blue` (PAW Blue; flips in dark),
  `onBlue`, `destructive`, `mango`, `lime`, `aqua`, `pink`, `butter`, `lavender`, `apricot`, `petFace`; `ProviderState.x.color/.ink/.wash`;
  `Hue.x.color/.ink`. Washes: `Theme.wash(color, percent)` (= `color-mix(in srgb, c p%, surface)`), `Theme.mix(a, p, with: b)`.
- Type: `.brandHeading(size)` (Fredoka) for titles, numbers and times; `Theme.text(size, weight:)` (Nunito Sans) for the rest.
  Micro-labels: `Theme.text(11, weight: .heavy)` + `.uppercased()` + `.tracking(size * 0.12)`, `inkSoft`.
- Corners: `Theme.cardRadius` 28 (cards), `boxRadius` 16 (boxes, rows in a card, notices), `fieldRadius` 16, `chipRadius` 14, capsules for pills.
  **No raw corner numbers.** Shadow: `.cardShadow()` on cards only.

## Sheets (the web's drawers/modals)
`ProviderModal(title:subtitle:systemImage:accent:isDirty:form:primaryTitle:primaryVariant:isWorking:cancelTitle:steps:onBack:secondaryActions:primaryIcon:primaryDisabled:onPrimary:) { … }`
— the tinted header with the handle and the tilted pebble, the white body, stacked footer buttons, no ✕.
- `steps: ModalSteps(["The place", "Clock and hours"], icons:, current:)` or `ModalSteps(steps: [(title, icon)], current:)` — the web's
  `ProviderModalSteps`, on its own row under the title. Never in the body.
- `onBack:` — past the first step the footer's Cancel becomes "‹ Atrás". `secondaryActions: [ModalAction(title, icon:, variant:, tint:) { }]`
  — more footer buttons between the primary and Cancel ("Archivar", "Guardar borrador", "Copiar solo el enlace"). Never in the body.
- Accents (`ModalAccent`): `butter` (default), `aqua`, `pink`, `mango`, `lime`, `lavender`, `mint`, `coral`, `sky` (`--brand-sky`
  #eaf4ff), `grey` (`--ink-soft`: a death, an ending), `peach` (`--hue-peach`), `.hue(Hue)` (a room's kind, a role).
Inside: `ModalSection(title:subtitle:systemImage:tint:)` (dashed rule between parts). Small yes/no: `ConfirmSheet`. Every sheet a
business screen opens goes through these.

## Owner decisions, 2026-11-04 (also on the web)
- **Sheet footer:** two buttons share one row, half each (Cancel or Back left, the action right); three or more stack, the action on top. The bar runs to the sheet's bottom edge with 24 pt under it (`ProviderModal.footer`). Never build a footer by hand.
- **Forward button** on a stepped sheet is just `L("Continue")`; the last step keeps its own words.
- **Client and pet:** always `ClientPetPicker`. It folds to the chosen client (with "Cambiar") so the pets are in view; a tap on the client opens the list again.
- **Search rule** for every searched list: server search, 250 ms after typing (`.debounced`), from 2 characters (`ClientSearch.query`), 20 at a time with infinite scroll, the server's count.
- **Sheets opened as pages** (booking, a new record from another screen): `.environment(\.modalAsPage, true)` — the tinted header runs under the status bar and has no grab handle; `ProviderModal` hides the system bar itself.

## Added 2026-11-04 (gap fill)
- `OptionCards(options: [OptionCard(value, title:, description:, icon:, accent:, unavailableReason:)], selection:, invalid:)` — the web's
  `OptionCardGrid`: a choice of a TYPE/KIND/SERVICE drawn as cards with an icon badge, Fredoka title, a line under it; chosen = the
  card washed in its colour + PAW Blue edge + check on the corner. Use it wherever the web uses `OptionCardGrid` (service and service
  category, record type, room kind, catalog kind, invoice kind, group session kind, the type pickers). `ChoiceCards` stays for plain
  yes/no-style radio rows (the web's `.provider-modal-toggle`). `Hue.category(id)` / `Hue.categoryIcon(id)` give a business category's colour and icon.
- `ProviderModal(…, footerSummary: AnyView?, showsCancel: Bool, pebbleImageURL: String?, showsBody: Bool)` — a total or a status line
  over the footer buttons (web footer summaries), no Cancel where the web has none, a pet photo in the pebble, and a body-less question.
  Two buttons share a row even without Cancel. `ModalAccent.blue` added. A swipe down on a sheet with changes shows `DiscardChangesSheet`.
  A step change slides (web ProviderModalStage); never animate steps yourself.
- `ModalSection(…, required: true)` — the red * after a section title ("Why *").
- `required:` on `MenuField`, `MoneyField` (+ `caps:`), `DayField`, `DateTimeField`, `OptionalDateField`, `TimeField`.
- `ConfirmSheet(…, cancelTitle:, accent: (.pink default), icon: ("triangle-alert" default), confirmIcon:, confirmWord:, confirmHint:)` —
  the web's `ProviderConfirmSheet`: pink header with the triangle, the question under the title, the sheet's own Cancel words
  ("Keep it", "Not now"), a word to type before a dangerous action. A plain confirm fits itself (title + buttons only).
