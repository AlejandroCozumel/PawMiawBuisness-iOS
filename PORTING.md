# PawMiaw Negocios (PawMiaw Business) — porting table

Native iOS (SwiftUI) app for PawMiaw's business users: the web's business
workspace (`/provider` in `~/code/pawmiaw-web`) ported screen by screen,
against the same backend (`~/code/paw-miaw-backend`, everything under `/api`).

**Web baseline:** `pawmiaw-web@33c5df56` (2026-11-04, online booking v1).
**Backend baseline:** `paw-miaw-backend@7b00a17`.

Status: ⬜ not started · 🟡 partial (works, more of the web to port; see the note) · ✅ ported

---

## How to port (read before touching a file)

### Where things are
| Folder | What |
|---|---|
| `PawMiawNegocios/Core` | `API` (Bearer-signed requests, `APIError`, `Page<T>`, `JSONValue`), `SessionStore`, `L()/LF()/LP()`, `Money`, `DateText`, `NameText` |
| `PawMiawNegocios/Workspace` | `Workspace` (the business, the place, permissions, `moneyLevel`, `offers(...)`, `locationId`, `timeZone`, `currency`), `Permission`, `MoneyLevel`, `WorkspaceRole`, `BusinessCategory` |
| `PawMiawNegocios/Design` | `Theme`, `ProviderState` (the six status colours) and `Hue`, `PMButton`/`.pm(...)`, `Card`, `PageScroll`, `PageSection`, `ListRow`, `FactRow`, `StatusChip`, `HueChip`, `CountBadge`, `FilterChip`/`FilterBar`, `ToneChip`, `Segmented`, `ToneTabs`, `Chip`, `TagChip`, `Tick`, `LoadingState`, `EmptyState`, `ErrorState`, `NoAccessState`, `NoticeCard`, `ListCard` + the list pieces, `Avatar`, `PetAvatar`, `RequireLocation`, `SearchField`, `Pager` + `PagedContent` + `PagerFooter`, `Loader` + `LoadedContent`, `Toast`, `FormState` + `FormScroll` + `FormField` + `PMTextField` + `MoneyField` + `ToggleRow` + `ChoiceCards` + `MenuField`, `ProviderModal` + `ModalSteps` + `ModalAction` + `ModalSection`, `ConfirmSheet` (the full list with signatures: `design/IOS-DESIGN-KIT.md`) |
| `PawMiawNegocios/App` | the app, the shell (tabs on a phone, the sidebar on an iPad), `ProviderSection` (the sidebar's rules), `ProviderRoute` + `RouteView`, `Badges` |
| `PawMiawNegocios/Auth` | sign-in, password reset, business chooser, "no business yet" |
| `PawMiawNegocios/Modules/<Module>` | one folder per part of the workspace |
| `PawMiawNegocios/{es,en}.lproj/<Module>.strings` | each module's words (Spanish first; the key is the English sentence; a module's files read its table first) |
| `scripts/strings-map.py` | regenerates `Core/StringTables.swift` (file → table) after adding a module file |

### Rules every screen follows (the owner's standing conventions)
- **One shared component per control.** Use the pieces in `Design/`. Never draw a second
  look-alike card, chip, button or empty state on a screen.
- **One button.** `PMButton` / `.buttonStyle(.pm(...))`: variants `.primary`, `.outline`,
  `.destructive`; sizes `.regular` (48 pt) and `.compact` (40 pt). Never repaint a button's
  height, corners or colour. Small round icon controls (`IconCircleButton`) are not buttons.
- **Every sheet is a `ProviderModal`** (accent header with its icon, no ✕, Cancel + one
  primary action, "¿Descartar los cambios?" when dirty). Plain yes/no and "with a reason"
  confirmations are `ConfirmSheet`.
- **Invalid forms** mark every invalid field, show one toast and scroll to the FIRST invalid
  field: `FormState.check([...])` in field order; server refusals go through
  `form.apply(error, known:)`.
- **Lists load 20 at a time with infinite scroll** (`Pager` + `PagedContent`). **Counts come
  from the server's totals**, never from what is loaded. Summaries (Home) show a capped number
  with "Ver todo".
- **Money access levels** (backend `docs/money-access-levels.md`): `workspace.moneyLevel`
  (`.charging` = the bill in front of you, `.frontDesk` = who owes, today's cash, Cortes, the
  last 7 days, the bills list, `.finances` = period totals, reports, margins, costs, history).
  The server enforces; the app only hides what a level can't read.
- **Permissions**: `workspace.can(.appointmentsCreate)` etc. hide what a role can't do.
- **Locations**: location-scoped pages (Home, Agenda, Stays, Rooms, Availability, the
  register) wrap their content in `RequireLocation { }` and send `workspace.locationId`;
  business-wide lists (Finance, Invoices, Clients, Records) send `workspace.listLocationFilter`
  as `locationId` when it is not nil.
- **Every size**: phone and iPad (regular width). Use `PageScroll` (readable column) and
  `LazyVGrid(columns: [GridItem(.adaptive(minimum: 300))])` where the web shows columns.
- **Status colours** come from `ProviderState` (`.appointment(status)`, `.stay`, `.hospital`,
  `.groom`, `.invoice`, `.slot`, `.vaccine`, `.confirmation`); categories from `Hue`.
- **Words**: every sentence through `L("English sentence")`; formatted ones `LF("%@ at %@", a, b)`;
  plurals `LP(n, "%d visit", "%d visits")`. Add the Spanish to your module's
  `es.lproj/<Module>.strings` (`"English" = "Español";`), copying the web's Spanish
  (`src/lib/*-copy.ts`, `NAV_SPANISH`, the paraglide messages) word for word where it exists.
- **Reload** with `.reloadsOnScope { await load() }` (runs on appear, when the business or the
  place changes, and after `announceDataChanged()`). Call `announceDataChanged()` after a save
  other screens show.
- **Navigation**: push with `NavigationLink(value: ProviderRoute.client(id))` etc. Never push
  another module's private view.
- **Names**: a module's top-level types are `private`/`fileprivate` or start with the module's
  prefix (`Sched…`, `Clients…`), so modules never collide. No `extension` on shared types
  unless `private`/`fileprivate`.
- **Out of scope** (left for the owner): push notifications, RevenueCat, env files and
  secrets. In-app purchase of the business plan is not offered (the backend answers 503 for
  Apple/Google provider purchases): plans are bought on the web through Stripe; the app reads
  the plan state and opens the web.

### Build (never boot a simulator)
```bash
./build.sh            # xcodebuild build … -destination 'generic/platform=iOS Simulator'
```

---

## Route → Swift file → status

| Web route | iOS screen (file) | Status | Note |
|---|---|---|---|
| (sign-in, business choice) | `Auth/SignInView.swift`, `Auth/WorkspaceChooserView.swift` | ✅ | Email + password, password reset by email. Apple/Google sign-in left for the owner (client ids). A business is created on the web. |
| `provider.tsx` (shell, sidebar, switcher) | `App/AppShell.swift`, `App/Sections.swift`, `App/Badges.swift` | ✅ | Tabs on a phone, the sidebar on an iPad; the sidebar's permission, category and money rules; its numbers. Hand-off routes between modules: `.bookVisit`, `.storeCheckout`, `.schedule(filter)`, `.newRecord`, `.olfatoPetChat`. |
| `provider.index.tsx` | `Modules/Home/` | ✅ | Every row's visit steps (Agenda's sheets), grooms, groups, home visits, emergency arrivals, requests, region form, setup checklist sheets, member welcome. Paused-plan notice and first-run setup wizard open the web. |
| `provider.schedule.tsx` (+ `provider.agenda.tsx`) | `Modules/Schedule/ScheduleScreen.swift`, `SchedAgendaViews.swift` | ✅ | Day by person/room, week, list; filter by day/person/room; group sessions; online requests. No drag (edit sheet moves visits). |
| (booking hand-off) | `Modules/Schedule/SchedBookVisitScreen.swift`, `SchedBookingSheet.swift`, `SchedBookingExtras.swift` | ✅ | Prefilled booking, follow-up tied after booking, repeating series, groom request, client-home address, walk-in triage. |
| `provider.appointments.tsx` | `Modules/Schedule/AppointmentsListScreen.swift` | ✅ | |
| `provider.appointments.$appointmentId.tsx` | `Modules/Schedule/AppointmentDetailScreen.swift` and `Sched*` cards | ✅ | Missing only: the e-sign "Evidence" sheet, the home-visit address card, confirming the groom request at check-in, "keep as usual style" offer here. |
| `provider.clients.tsx` / `provider.patients.tsx` | `Modules/Clients/ClientsListScreen.swift` | ✅ | Incl. possible matches and combining. |
| `provider.clients.$clientId.tsx` | `Modules/Clients/ClientDetailScreen.swift`, `ClientsLinking`, `ClientsMovePet`, `ClientsVault`, `ClientsAudit` | ✅ | Account through Money's account screen. |
| `provider.clients.$clientId.pets.$petId.tsx` + patient chart | `Modules/Clients/PatientChartScreen.swift`, `ClientsChartBrief`, `ClientsChartExtras` | ✅ | Opening by pet id alone looks the client up (no backend route returns one pet). |
| `provider.invitations.tsx` | `Modules/Clients/InvitationsScreen.swift` | ✅ | |
| `provider.due.tsx` | `Modules/Clients/DueScreen.swift` | ✅ | Books on the due day; `BookingPrefill` can't carry a service label/category. |
| `provider.records.tsx` | `Modules/Records/RecordsScreen.swift` | ✅ | |
| `provider.records.$recordId.tsx` (+ record sheet, new-record hand-off) | `Modules/Records/RecordDetailScreen.swift`, `RecordsRecordSheet.swift`, `RecordsNewRecordScreen.swift` | ✅ | Not ported: dropping files from another app (iPad). |
| `provider.stays.tsx` | `Modules/Stays/` | ✅ | Consents, incidents, deposit, every home-stay action. |
| `provider.hospital.tsx` | `Modules/Hospital/HospitalScreen.swift` | ✅ | |
| `provider.hospital.$hospitalizationId.tsx` | `Modules/Hospital/HospitalDetailScreen.swift` and tabs | ✅ | |
| `provider.grooming.tsx` | `Modules/Services/GroomingScreen.swift`, `GroomingTabs.swift`, `SvcGroomRequest.swift` | ✅ | |
| `provider.home-visits.tsx` | `Modules/Services/HomeVisitsScreen.swift`, `SvcOutbox`, `SvcLocation` | ✅ | Offline outbox and saved day; location stamps and walk routes while the app is open (no background location). |
| `provider.groups.tsx` | `Modules/Services/GroupsScreen.swift`, `GroupsSession.swift` | ✅ | |
| `provider.store.tsx` (+ store hand-off) | `Modules/Money/StoreScreen.swift`, `CashStoreCheckout.swift`, `CashCounter.swift` | ✅ | Prefilled counter (prescription hand-over, bill with products), camera scan, quick edit. |
| `provider.invoices.tsx` | `Modules/Money/InvoicesScreen.swift`, `InvoiceDetailScreen.swift` | ✅ | |
| `provider.finance.tsx` | `Modules/Money/FinanceScreen.swift`, `CashFinanceExports.swift` | ✅ | CSV exports by money level. |
| `provider.billing.tsx` | `Modules/Money/BillingScreen.swift` | ✅ | Plan state only; managing the plan opens the web (no in-app purchase). |
| `provider.catalog.tsx` | `Modules/Money/CatalogScreen.swift`, `CashCatalog*.swift` | ✅ | "Receive stock" opens Inventory, not the item. |
| `provider.inventory.tsx` | `Modules/Stock/StockInventory.swift` and sheets | ✅ | |
| `provider.pharmacy.tsx` | `Modules/Stock/StockPharmacy*.swift`, `StockPrescription*.swift` | ✅ | |
| `provider.rooms.tsx` | `Modules/Places/PlacesRooms.swift` | ✅ | |
| `provider.locations.tsx` | `Modules/Places/PlacesLocations.swift`, `PlacesSwitcher.swift` | ✅ | `PlacesSwitcherMenu` is the one place/business switcher: the shell's header and every page toolbar (`LocationMenu`). |
| `provider.relocate.tsx` | `Modules/Places/PlacesRelocate.swift` | ✅ | |
| `provider.staff.tsx` | `Modules/Team/StaffScreen.swift` | ✅ | |
| `provider.staff.$memberId.tsx` | `Modules/Team/StaffMemberScreen.swift` and `TeamMember*` | ✅ | |
| `provider.settings.tsx` | `Modules/Team/SettingsScreen.swift`, `TeamConsentTemplates`, `TeamOlfatoSettings` | ✅ | |
| `provider.settings.notifications.tsx` | `Modules/Team/NotificationSettingsScreen.swift` | ✅ | |
| `provider.availability.tsx` | `Modules/Team/AvailabilityScreen.swift` | ✅ | On iPad, leaving from the sidebar doesn't ask about unsaved changes. |
| `provider.account.security.tsx` | `Modules/Team/AccountSecurityScreen.swift`, `TeamAccountDeletion.swift` | 🟡 | Apple re-authorization links to the web (no Sign in with Apple in this app yet). |
| `provider.notifications.tsx` | `Modules/Inbox/InboxNotifications.swift`, `InboxNotificationWork.swift` | ✅ | Rows open their work (prefilled booking/record, bill, visit). |
| `provider.olfato.tsx` / `.index` / `.$chatId` (+ pet chat) | `Modules/Inbox/InboxOlfato*.swift` | ✅ | |

One shared component per control (the owner's rule), merged 2026-11-04 after the parallel ports:
`Design/` holds every control used by more than one screen — `FlowLayout`, `FilterChip` /
`FilterMenuLabel` / `FilterBar`, `PillPicker`, `PetStack`,
`DocumentButton` (server PDF/CSV + Quick Look), `ShareSheet`, `PhotoField` + `PhotoDraft`,
`DayField` / `TimeField` / `DateTimeField` / `OptionalDateField`, `SignaturePad`,
`SignatureCapture` ("Mi firma", typed signatures, e-sign terms), `ConsentsCard` (+ sign, view,
evidence), `IncidentsCard`, `DepositSheet`, `AuditHistoryCard`, `OlfatoNotice`, `CountryPicker`,
`ClientPetPicker`, `BarcodeScanner`, `WalkRouteView`, `ContactLinks` / `ContactButtons` /
`PhoneLink`. `Core/` has `API.multipart`, `API.download`, `APIError.body` (the whole refusal),
`ImageUpload`, `Barcode` (scan rules) and `VisitLocation` (arrival stamps). Before building a
control in a module, look there first.

Second merge, 2026-11-04 (after the restyle to the web workspace): the local copies the ten module
ports had built were folded into `Design/`, one piece per control, matched to the web — `ChipTone`
(the `TONE_FILLS` table) with `ToneTabs`, `ToneChip`, `ToneMenuLabel`, `ToneIcon`, `ToneCount`;
`Segmented` with counts, badges, tones and `fill`; `Chip` in any tone and size (every row pill and
status tag), `StatusChip(brand:)`, `TagChip(tone:size:)`, `FilterChip(solid:)` / `(face:onRemove:)`;
`PMButton` `.ghost` / `.link`, sizes `.slim` 32 and `.small` 28, `PMButtonContent`; `IconCircleLabel`
(every ⋯ menu); `ModalSteps`, `ModalAction`, and `ProviderModal(steps:onBack:secondaryActions:)` (steps
in the header, Back and Archive/Save draft in the footer, never in the body); `ModalAccent` `.grey`,
`.peach`, `.hue`; `Tick`; `FieldLabel` and `caps`/`number` on `FormField`/`PMTextField`; `ListCard` /
`.listCard()`, `CardToolbar`, `ListFooter`, `ListCount`, `LoadMoreRow`, `DayBand`, `RowList`;
`NoticeCard` looks (`.inline`, `.banner`, `.page`, custom content); `Eyebrow`, `SectionHeading`,
`StitchedDivider(lineWidth:)`, `ProgressBar`; `ContextPills`, `AttachmentTile`, `ChoiceCards(tiles:)`;
`SettingsCard` + `SettingsRule` + `SaveBar`; `Card(flat:)`; `ModuleHeader(titleAccessory:)` and its
fold rule (an iPhone starts folded, an iPad open, the person's choice remembered per `storageKey`).
`StatTile`/`StatGrid` were removed (unused). A module now keeps only functions that map its data onto
a kit piece (`stockStateChip`, `teamRoleChip`, `recordsTypeChip`, `clientsStatusTag`, `homeDayStepper`,
`schedDayBand`).

Still per module on purpose: the charge choice of a visit (`SchedChargeChoice`) and a stay's bill
(`StaysBillChoice`) mirror two different web flows; `TeamConfirmSheet` (a confirmation with custom
content); Team's `TeamSaveSection` / `TeamPanel` (the web's `SaveSection` / `SettingsPanel` /
`MemberPanel`, drawn only on Team's pages, framed by `.listCard()`); Services' `SvcHandlingChips`,
`SvcChoiceChip`, `SvcAskedBox`, `SvcLoadError`, `SvcMessagePreview` (web pieces only Services draws); data models that only mirror an endpoint (e.g. Money's `CashStoreSettings` and Team's
`TeamStoreSettings`, the member models of Schedule/Services/Stays/Hospital), which could be merged
later without changing any screen.

Words: each module file reads its own `<Module>.strings` first (`Core/StringTables.swift`,
generated by `python3 scripts/strings-map.py` — run it after adding or renaming a module file).

Not ported on purpose: `provider-confirmations.*` and `providers.tsx` are public/family pages,
not the business workspace.
