# VitalPath Mobile App — Changelog & Roadmap

All notable changes are documented here in reverse-chronological order.
Labels: `Feature` · `Fix` · `Refactor` · `Security` · `Build` · `Design`

---

## [Unreleased] — v1.7.0 · branch: `feature/ux-iteration-v2`

> In progress. Not yet tagged or pushed to GitHub.

### Fix — Sprint 1: UX Heuristic Fixes

- **Home screen rename** (`lib/screens/home_screen.dart`) — "Your Passbook" → "Today" (expanded header), "Passbook" → "Today" (collapsed title), "Today's Passbook" → "Today's Timeline" (sticky section header)
- **Notification bell wired** (`lib/screens/home_screen.dart`) — bell icon navigates to `NotificationSettingsScreen` via right-to-left slide route; haptic on tap
- **Summary strip hidden when empty** (`lib/screens/home_screen.dart`) — `_SummaryStrip` returns `SizedBox.shrink()` when `totalTodayCount == 0`; prevents a "0/0 Done" display before any medicines are added
- **Smart Timeline split empty state** (`lib/widgets/smart_timeline_widget.dart`) — replaced single `_EmptyTimelineState` with two context-aware states: `_NudgeEmptyState` (no prescriptions — shows "Go to My Medicines" CTA) and `_AllClearEmptyState` (all logged — green checkmark); `SmartTimelineSliverList` now accepts `VoidCallback? onNavigateToCare`
- **Care screen tabs** (`lib/screens/care_screen.dart`) — removed Activity sub-tab (naming collision with bottom-nav Activity screen); renamed Food → Nutrition; tabs are now `['Medicines', 'Nutrition']` with `TabController(length: 2)`
- **"Coming in Phase 2" removed** (`lib/screens/care_screen.dart`) — Nutrition coming-soon banner now shows "Coming Soon"
- **Profile debug ID removed** (`lib/main.dart`) — profile subtitle `debug-patient-001` replaced with "VitalPath Patient"
- **Section header renamed** (`lib/main.dart`) — `_SectionHeader('Clinical')` → `_SectionHeader('My Health')`
- **Care tab navigation wired** (`lib/main.dart`) — `HomeScreen` receives `onNavigateToCare: () => setState(() => _tab = 1)`; CTA button on empty timeline navigates directly to the Care tab
- **Locked card copy** (`lib/widgets/smart_timeline_widget.dart`) — "synced to your passbook" → "synced to your schedule"

### Feature — Onboarding Restart (Developer tool)

- **`OnboardingFlow.reset()`** (`lib/screens/onboarding/onboarding_flow.dart`) — new static method that removes the `onboarding_complete` SharedPreferences key, unblocking the onboarding gate on next `_AppRouter` evaluation
- **`_restartNotifier` + `VitalpathApp.restartFromSplash()`** (`lib/main.dart`) — top-level `ValueNotifier<int>` wraps the `MultiProvider`+`MaterialApp` subtree; incrementing it triggers a full rebuild from scratch (fresh providers, fresh `_AppRouter`, re-read of SharedPreferences); `restartFromSplash()` calls `OnboardingFlow.reset()` then increments the notifier atomically — no hot-restart needed
- **Profile → Developer → "Restart from Splash"** (`lib/main.dart`) — orange tile in the Developer section; tapping replays the complete flow: teal splash → Value Prop page → Google Sign-in + biometric → Name + Health Goal + Invite Doctor; returns to the normal app shell after completing onboarding

### Feature — Doctor Portal (testable preview)

- **`DoctorPortalScreen`** (`lib/screens/doctor_portal_screen.dart`) — new standalone portal screen with its own bottom navigation shell (4 tabs: Overview, Patients, Verify, Profile); slides up from the bottom (modal pattern) to signal a role switch, distinct from hierarchical right-slides
- **Overview tab** — summary stat cards (Patients · Pending · Verified), empty activity feed with "Link a Patient" CTA
- **Patients tab** — empty state with "Show Sync Code" button that reveals a mock `DR-847291` 6-digit code matching the patient-side doctor sync flow
- **Verify tab** — empty Verification Queue with Clinical Lock explanation banner; documents the doctor-side prescription verification flow for UI testing
- **Doctor Profile tab** — doctor identity card, portal preview info banner, "Back to Patient View" button that pops back to the patient app
- **Profile → Developer section** (`lib/main.dart`) — added "Switch to Doctor View" entry tile in a new "Developer" section; indigo icon (`#3D5AFE`) to visually distinguish it from patient-facing tiles; taps open `DoctorPortalScreen` via its modal route
- **`_ProfileTile` `iconColor` param** (`lib/main.dart`) — added optional `iconColor` parameter; tile icon and background both adapt to the custom colour (background uses 10% alpha of the icon colour)

### Feature — Active/Archived Split + Nutrition UX

- **Medicines tab shows active-only** (`lib/screens/care_screen.dart`, `lib/providers/prescription_provider.dart`) — `_MedicinesTab` now reads `provider.activePrescriptions` (prescriptions where today falls within `startDate..endDate` inclusive) instead of `allPrescriptions`; patients see only what they should be taking right now
- **Smart empty state for Medicines tab** (`lib/screens/care_screen.dart` — `_EmptyActiveMedicinesState`) — two states: "No Medicines Yet" (truly empty, prompts to add) vs "No Active Medicines" (has historical records, hints to check the Vault tab for full history)
- **Vault tab unchanged** — continues to show all prescriptions via `groupedPrescriptions`; serves as the full archive view
- **`activePrescriptions` getter added** (`lib/providers/prescription_provider.dart`) — date-only comparison (midnight) ensures prescriptions starting or ending today are included for the full day; `O(n)` filter, no cache needed
- **Nutrition tab proper empty state** (`lib/screens/care_screen.dart` — `_NutritionEmptyState`) — replaced flat "Coming Soon" banner with a centred empty state (restaurant icon, title, description) and an actionable "Add Entry" `FilledButton` (indigo `#3D5AFE`); tapping shows a "coming soon" snackbar with haptic feedback
- **Log Nutrition FAB** (`lib/screens/care_screen.dart` — `_LogNutritionFab`) — Nutrition tab (index 2) now shows an indigo FAB labelled "Log Nutrition" instead of no FAB; tapping fires the coming-soon snackbar; Add Medicine FAB retained for Medicines and Vault tabs
- **`withOpacity` → `withValues`** (`lib/screens/care_screen.dart`) — replaced deprecated `withOpacity(0.1)` call in `_VaultDoctorHeaderDelegate` with `withValues(alpha: 0.1)` to eliminate the analyzer deprecation warning

### Design — Sprint 4: Visual Language Unification

- **Design system tokens applied across Home, Care, and Profile** — imported `VitalPathTheme` into `home_screen.dart`, `care_screen.dart`, and `main.dart`; all three screens now reference the same design tokens rather than scattered hex literals
- **Primary text unified** — all `Color(0xFF1A1A2E)` replaced with `VitalPathTheme.deepCharcoal` (`#0F1923`) across all three screens; the shared dark-navy primary text colour is now defined in one place
- **Secondary text unified** — all `Color(0xFF9E9E9E)` replaced with `VitalPathTheme.softGrey` (`#6B7280`) across all three screens; secondary text is now more readable (Tailwind Gray-500) and consistent
- **Page backgrounds unified** — all `Color(0xFFF6F7FB)` replaced with `VitalPathTheme.lightSurface`; `MaterialApp.scaffoldBackgroundColor` now uses the same token
- **Profile section headers** — `_SectionHeader` now uses `VitalPathTheme.labelLarge` (12px, w700, 0.8 letter-spacing) — the design system label style — rather than hand-rolled typography
- **Profile tile shadow** — `_ProfileTile` box shadow replaced with `VitalPathTheme.cardShadow` (consistent `0x18` opacity, 16px blur, 4px Y offset)
- **Home summary progress pill** — `_ProgressPill` gains `VitalPathTheme.tealGlowShadow(intensity: 0.15)` — a subtle teal ambient glow distinguishing it from the stat pills
- **Care screen notification bell wired** — bell icon colour updated to `VitalPathTheme.softGrey`; tapping now navigates to `NotificationSettingsScreen` via the same right-to-left slide route used on the Home screen

### Refactor — Sprint 3: IA Restructure

- **Prescription Vault moved into Care screen** (`lib/screens/care_screen.dart`) — added "Vault" as a middle tab (`['Medicines', 'Vault', 'Nutrition']`, `TabController(length: 3)`); all medicine-related views now live under a single navigation item, eliminating the three-location data scatter
- **Vault tab: grouped-by-doctor view** (`lib/screens/care_screen.dart` — `_VaultTab`, `_VaultDoctorHeaderDelegate`) — prescriptions grouped by prescribing doctor with sticky `SliverPersistentHeader` section headers; latest-first sort order (driven by `PrescriptionProvider.groupedPrescriptions`); `AutomaticKeepAliveClientMixin` preserves scroll state on tab switches
- **FAB extended to Vault tab** (`lib/screens/care_screen.dart`) — "Add Medicine" FAB now appears on both Medicines (index 0) and Vault (index 1) tabs; hidden on Nutrition (index 2)
- **Prescription Vault removed from Profile** (`lib/main.dart`) — `_ProfileTile` entry and `prescription_vault_screen.dart` import removed from the Profile tab; the standalone `PrescriptionVaultScreen` file is retained but no longer surfaced via navigation

### Fix — Sprint 2: Auth & Security UX

- **Background grace period** (`lib/main.dart` — `_AuthGateWrapperState`) — added `_backgroundedAt` timestamp tracking; app now only re-challenges biometric auth if the user was backgrounded for > 2 minutes; brief notification/multitasking switches no longer trigger a lock
- **Emergency Info on lock screen** (`lib/main.dart` — `_LockScreen`, `_EmergencyInfoSheet`) — added "View Emergency Info" button visible on the lock screen at all times; tapping opens a read-only bottom sheet listing all current medications (name, dose, prescribing doctor, verified badge) — no authentication required; critical for first-responder scenarios
- **Dot attempt indicator** (`lib/main.dart` — `_LockScreen`) — replaced text-only "X attempts remaining" with a 3-dot visual indicator (red dots fill left-to-right per failed attempt); remaining attempts text shown below dots at reduced opacity

---

## [v1.6.0] — 2026-04-24 · branch: `feature/ux-iteration-v2`

### Feature
- **Home Dashboard — Bento-Grid Redesign** (`lib/screens/home_screen.dart`, `lib/widgets/smart_timeline_widget.dart`)
  - 5-tile Bento-Grid layout (Step Gauge, Next Dose, Next Meal, Next Appointment, Wellness Score) replacing the previous linear-scroll home screen
  - Step Gauge tile: custom `_GaugePainter` arc at 120fps with ElectricTeal → ClinicalTeal sweep gradient; `StreamBuilder<int>` drives live step count
  - Next Dose tile: 1-tap `_GlassLogButton` with glass ripple + `HapticService().doseLogged()`; electricTeal border pulses when dose is due now
  - Daily Wellness Score tile: composite formula (steps 40 pts + adherence 40 pts + base 20 pts); `_MiniArcPainter` at 120fps in VerifiedGold
  - Sticky "Day at a Glance" header uses `SliverPersistentHeader` + `BackdropFilter` blur so it stays glass-frosted while scrolling
  - `RepaintBoundary` isolation on every tile — no cross-tile repaint propagation

### Refactor
- **Smart Timeline** — full glassmorphic rebuild (`lib/widgets/smart_timeline_widget.dart`)
  - Routing by state: completed → 40% opacity, missed → 72%, dueNow → `_PulsingGlassCard` (AnimationController on electricTeal border)
  - `_CardWrapper` uses `GlassCard.dark` + 3 px left accent stripe per entry
  - Variable typography throughout: w700 active title / w400 faded completed; w800 dosage data / w400 label
  - `_QuickLogChip` with `InkWell` glass ripple; `splashColor: electricTeal.withValues(alpha: 0.3)`

### Feature
- **Care Screen — Glassmorphic Refactor** (`lib/screens/care_screen.dart`, `lib/widgets/prescription_card_widget.dart`)
  - Dark `deepCharcoal` background matching the Home Dashboard
  - Glass AppBar: `ClipRect + BackdropFilter(blur 20,20)` + `SafeArea` title row with notification bell
  - `TabBar`: electricTeal underline indicator on frosted dark surface; unselected labels at 50% opacity
  - `GlassCard.dark` prescription cards — compact layout: Name (**w800** white), Dosage (**w800** electricTeal), secondary meta in **w400** softGrey
  - Clinical Lock path (`isVerified == true`): glowing stethoscope icon (tealGlowShadow) + glass Info button → `ClinicalLockModal.explanation`; Edit/Delete completely removed from this path
  - Patient-managed path (`isVerified == false`): glass Edit + glass Delete icon buttons (InkWell ripple, delete via confirmation dialog)
  - 1-tap "Log Dose" chip (teal gradient + glass border) — `canQuickLog` driven; `HapticService().doseLogged()` + `SuccessToast` on success; `DuplicateLogModal` safety guard with force-override path
  - 40% `Opacity` faded state for medications already logged today (`isLoggedToday`)
  - Circular frosted-glass FAB with `electricGlowShadow(intensity: 0.75)` replacing the previous extended FAB
  - `Consumer2<PrescriptionProvider, DashboardProvider>` correlates prescriptions to today's timeline entries for live canQuickLog / isLoggedToday state — no domain logic duplicated in the UI
  - Dark-variant `ShimmerLoader` skeleton for loading state; dark `GlassCard` empty state; dark "Coming Soon" banners for Food and Activity tabs

---

## [v1.6.0] — 2026-04-24 · branch: `feature/ux-iteration-v2`

> Tag: `v1.6.0` · Commit: `e2ff82a`

### Design
- **VitalPath 2026 Design System** (`lib/theme/vitalpath_theme.dart`) — new file
  - Full colour palette: `deepCharcoal`, `electricTeal`, `clinicalTeal`, `verifiedGold`, `alertAmber`, `softGrey`, `errorRed`
  - Gradient tokens: `darkGradient`, `tealGradient`, `electricGradient`, `tealGlow` (radial)
  - Variable typography scale: `displayLarge` (w900) → `displayMedium` (w800) → `headlineLarge` (w800) → `bodyLarge` (w400); plus semantic tokens `ctaPrimary`, `verifiedData`, `patientData`, `bentoMetric`, `bentoLabel`
  - Shadow factories: `tealGlowShadow(intensity)` and `electricGlowShadow(intensity)` — parameterised for intensity scaling
  - Glass layer constants: `glassDarkSurface` (7% white), `glassLightSurface` (70% white), `glassAccentSurface` (18% teal)

- **GlassCard Widget** (`lib/widgets/glass_card.dart`) — new file
  - 3-layer glassmorphism: `ClipRRect` → `BackdropFilter(ImageFilter.blur)` → semi-transparent `Container`
  - Named constructors: `.dark()` (7% white, σ=20), `.light()` (70% white, σ=16), `.accent()` (18% teal, σ=20)
  - All constructors expose `borderColor`, `borderRadius`, `padding`, `boxShadow`, `borderWidth` overrides
  - `ShimmerLoader` widget included — sweep gradient skeleton animation (1200ms, `easeInOut`); dark and light variants

### Feature
- **Onboarding Flow Redesign** (`lib/screens/onboarding/onboarding_flow.dart`) — complete rewrite of 3-screen flow
  - Screen 1 "Welcome" — `_BentoGrid` illustration with staggered `Interval` animations (200ms offset between tiles); `ctaPrimary` (w900) headline
  - Screen 2 "Connect" — Google Sign-In button → success shimmer; biometric enrol path; verifiedGold icon on success
  - Screen 3 "Personalise" — 6-tile health goal `GridView` with variable typography (selected tile w800, unselected w400); `HapticFeedback.selectionClick()` on tile tap
  - `SharedPreferences` gate preserves `onboarding_complete` flag; `OnboardingFlow.isComplete()` / `.markComplete()` static API unchanged
  - All animations use `AnimationController` + `CurvedAnimation` + `Interval` — no `setState` inside animation callbacks

- **BundleCard Widget** (`lib/widgets/bundle_card_widget.dart`) — new file
  - Shown when 2+ medicines are `dueNow` and `canQuickLog` simultaneously
  - Pulsing AnimationController (0.3 → 1.0) drives electricTeal glow on teal gradient card
  - "Take All N Doses" button: loops `DashboardProvider.quickLog()`, silently skips `DuplicateLogException` per dose, shows consolidated `SnackBar` on completion

- **Glass Biometric Lock Screen** (`lib/main.dart` — `_LockScreen`) — redesigned
  - `BackdropFilter(blur 24,24)` overlay across the entire screen
  - `GlassCard.dark` container housing the biometric prompt and VitalPath branding
  - "Use Passcode" fallback renders automatically after 3 failed biometric attempts (`_failedAttempts` counter in `_AuthGateWrapperState`)

### Build
- `android/gradle.properties` — added `org.gradle.java.home` pointing to Android Studio JBR (Java 21)
- `pubspec.yaml` — version bumped to `1.6.0+4`

---

## [v1.5.0] — 2026-04-24 · branch: `main`

> Tag: `v1.5.0` · Commit: `2d25aeb`

### Security
- **Biometric Auth Gate** (`lib/main.dart`) — `local_auth` integration; device-credential fallback; `_AuthGateWrapper` StatefulWidget with lock/unlock lifecycle
- **AES-256-CBC Field Encryption** — `encrypt` + `flutter_secure_storage` for hardware-backed Keychain/Keystore key storage; applied to sensitive prescription fields
- **Privacy Settings Screen** (`lib/screens/privacy_settings_screen.dart`) — toggle UI for data sharing preferences, biometric toggle, export/delete account flows

### Feature
- **Firebase Connection** — `flutterfire configure` applied; `firebase_core`, `cloud_firestore`, `firebase_auth` activated in `pubspec.yaml`
  - `lib/firebase_options.dart` generated
  - `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist` added
- **Firestore Security Rules** (`firestore.rules`) — full rule set: per-user document isolation, `isVerified` write protection (doctor-only path), prescription field-level guards

### Fix
- **Prescription Vault QA hardening** (`lib/screens/prescription_vault_screen.dart`) — edge cases for empty vault, verified-record deletion guard surfaces `ClinicalLockModal` correctly
- **My Doctors screen** (`lib/screens/my_doctors_screen.dart`) — unsync safety confirmation dialog wired; race condition on simultaneous sync resolved

---

## [v1.4.1] — 2026-04-24

> Tag: `v1.4.1` · Commit: `0e5e0a4`

### Build
- Scaffolded full Android (`android/`) and iOS (`ios/`) native project directories
- `AndroidManifest.xml` — permissions: `INTERNET`, `USE_BIOMETRIC`, `USE_FINGERPRINT`, `VIBRATE`, `ACCESS_FINE_LOCATION` (future GPS)
- `android/app/build.gradle.kts` — `compileSdk 35`, `minSdk flutter.minSdkVersion`, `targetSdk 35`, Java 21 compatibility
- `README.md` — project overview and setup instructions
- Resolved all analyzer errors introduced by the native scaffold

---

## [v1.4.0] — 2026-04-24

> Tag: `v1.4.0` · Commit: `4d21cd7`

### Build
- `pubspec.yaml` — full dependency manifest: `provider`, `hive`, `hive_flutter`, `shared_preferences`, `uuid`, `intl`, `path_provider`, `connectivity_plus`, `image_picker`, `local_auth`, `flutter_secure_storage`, `encrypt`
- `lib/main.dart` — multi-provider `MultiProvider` tree: `PrescriptionProvider`, `AppointmentProvider`, `ChangeNotifierProxyProvider2` wiring `DashboardProvider`, `ActivityProvider`; `MaterialApp` with `VitalPath`-branded `ThemeData`
- `analysis_options.yaml` — `flutter_lints` ruleset applied; project compiles and runs for the first time

---

## [v1.3.0] — 2026-04-23

> Tag: `v1.3.0` · Commit: `8251207`

### Feature
- **Activity Screen** (`lib/screens/activity_screen.dart`) — step count display, goal ring progress, walk history list, today-vs-goal comparison
- **GPS Walk Tracking** (`lib/screens/walk_screen.dart`, `lib/services/gps_walk_service.dart`)
  - Live GPS position stream via `geolocator`; distance calculated using Haversine formula
  - Pause/resume/stop controls; elapsed time ticker
  - Walk session auto-saved to Hive on stop
- **ActivityProvider** (`lib/providers/activity_provider.dart`) — `ChangeNotifier` wrapping `GpsWalkService`; exposes step count, walk sessions, active walk state
- **GpsWalkSession Model** (`lib/models/gps_walk_session.dart`) — Hive-serialisable; stores `startTime`, `endTime`, `distanceMetres`, `steps`, `polyline`
- **CelebrationOverlay** (`lib/widgets/celebration_overlay.dart`) — confetti-style particle animation triggered on step-goal achievement; `AnimationController` particle system, `CustomPainter` rendering
- **HealthService** (`lib/services/health_service.dart`) — step count integration; `defaultStepGoal = 8000`

---

## [v1.2.0] — 2026-04-23

> Tag: `v1.2.0` · Commit: `ce4f652`

### Feature
- **My Doctors Screen** (`lib/screens/my_doctors_screen.dart`) — search bar with real-time filtering, synced doctor list, "Add Doctor" flow
- **Doctor Sync Hub Bottom Sheet** (`lib/widgets/sync_hub_bottom_sheet.dart`) — search-and-connect UI with shimmer loading, doctor card preview, unsync safety confirmation
- **DoctorProvider** (`lib/providers/doctor_provider.dart`) — `ChangeNotifier`; manages synced doctor list, sync/unsync operations with optimistic updates
- **DoctorModel** (`lib/models/doctor_model.dart`) — `name`, `specialty`, `hospitalName`, `licenceNumber`, `isVerified`, `syncedAt`
- **DoctorSyncService** (`lib/services/doctor_sync_service.dart`) — Firestore-backed sync; queries by licence number; handles already-synced guard
- **DoctorShimmerWidget** (`lib/widgets/doctor_shimmer_widget.dart`) — animated skeleton placeholder for doctor list loading state

### Fix
- **Firestore Security Rules** — added doctor-user linking rules; patient can read their synced doctor's public profile but not modify it

---

## [v1.1.0] — 2026-04-23

> Tag: `v1.1.0` · Commit: `1bc4626`

### Feature
- **Home Screen — Living Passbook** (`lib/screens/home_screen.dart`) — initial implementation; greeting header, step count card, today's medication timeline
- **Smart Timeline Widget** (`lib/widgets/smart_timeline_widget.dart`) — initial implementation; `TimelineEntry` list sorted by `scheduledAt`; state-based styling (upcoming / dueNow / completed / missed)
- **DashboardProvider** (`lib/providers/dashboard_provider.dart`) — cross-provider projection from `PrescriptionProvider` + `AppointmentProvider` into `List<TimelineEntry>`; `quickLog()` action with optimistic update, `DuplicateLogException` rethrow, rollback on error
- **TimelineEntry Model** (`lib/models/timeline_entry.dart`) — unified view-model for medicine, meal, appointment, activity events; `TimelineEntry.withComputedState()` factory; `canQuickLog` getter
- **HealthService** (`lib/services/health_service.dart`) — step count polling via platform channel; `defaultStepGoal`
- **StepGoalWidget** (`lib/widgets/step_goal_widget.dart`) — circular progress ring with animated fill; displays steps / goal

---

## [v1.0.0] — 2026-04-23

> Tag: `v1.0.0` · Commit: `9c8ebeb`

### Feature
- **Clinical Lock — Data Models** (`lib/models/prescription_model.dart`)
  - `PrescriptionModel` fields: `medicineName`, `dosage` (double), `unit` (DosageUnit enum), `instructions`, `startDate`, `endDate`, `isVerified`, `governanceLevel`, `doctorName`, `doctorId`
  - `GovernanceLevel` enum: `patientManaged`, `physicianVerified`
  - `DosageUnit` enum with `.label` getter (mg, mL, units, etc.)
  - `validateOrThrow()` guard — rejects invalid dosage ranges and empty names

- **Prescription UI** (`lib/widgets/prescription_card_widget.dart`, `lib/screens/prescription_vault_screen.dart`)
  - Prescription Vault screen: grouped by doctor (Latest-First Algorithm), `LinkedHashMap` preserving sort order
  - `PrescriptionCardWidget` — initial white-card design; left teal border for verified records; `_GovernanceActionButton` with disabled state for locked controls

- **Clinical Lock Modal** (`lib/widgets/clinical_lock_modal.dart`)
  - `.explanation` mode — patient-facing: explains why the record is locked; no destructive action possible
  - `.deleteConfirm` mode — doctor-facing: double-confirmation before deleting a verified record
  - `ClinicalLockModalMode` enum

- **Appointment Management** (`lib/providers/appointment_provider.dart`, `lib/screens/appointment_screen.dart`, `lib/widgets/request_appointment_bottom_sheet.dart`)
  - `AppointmentModel` with `AppointmentStatus` enum
  - Request, cancel, confirm flows with optimistic UI
  - Firestore persistence via injected save/delete callbacks

- **PrescriptionProvider** (`lib/providers/prescription_provider.dart`)
  - Latest-First grouping algorithm with `_dirty` cache flag
  - Optimistic CRUD with rollback on Firestore failure
  - Clinical Lock guard in `updatePrescription()` and `deletePrescription()` — throws `StateError` if patient attempts mutation of verified record

- **Core Services**
  - `MedicineLoggingService` — `logDose()` with 15-minute duplicate-log lockout; `DuplicateLogException` with `lastLoggedAt` and `lockoutEndsAt`
  - `DuplicateLogModal` — safety bottom sheet; live countdown timer; force-override path requiring deliberate second tap
  - `SuccessToast` — 1.5-second overlay toast (slide-in 200ms + fade-out 300ms); `IgnorePointer` so it never blocks interaction
  - `HapticService` — singleton; `medicineReminder()`, `goalSuccess()`, `doseLogged()`, `appointmentConfirmed()`, `criticalWarning()`; native CoreHaptics (iOS) / VibrationEffect (Android) via `MethodChannel`
  - `VerifiedBadgeWidget` — compact and full-size variants

- **Firestore Security Rules** (`firestore.rules`)
  - Per-user document isolation on all collections
  - `isVerified` field write-protection: only service accounts / doctor roles can set `true`

---

## Roadmap

> Items below represent planned milestones. Versions are indicative and subject to change.

---

### v1.7.0 — UI Polish & Navigation Restructure _(next release)_

- [ ] **Feature** — Tag and push the current `feature/ui-design-system` branch work (Bento-Grid + Care Screen refactor)
- [ ] **Refactor** — Tab navigation restructure: move "My Doctors" + "Prescription Vault" into the Care tab; rename Profile tab to Account
- [ ] **Feature** — Prescription detail view on card tap (secondary data: unit type, refill date, notes, full instruction text) — keeps the main card compact

---

### v1.8.0 — Notification & Reminder System

- [ ] **Feature** — Push notification infrastructure: `flutter_local_notifications` + `timezone` package activation
- [ ] **Feature** — Medicine reminder scheduler: fires `HapticService.medicineReminder()` pattern + local notification at each `DoseSchedule.scheduledTime`
- [ ] **Feature** — Appointment reminder: 24-hour and 1-hour push notifications for confirmed appointments
- [ ] **Feature** — Missed-dose alert: notification 30 minutes after a `dueNow` entry transitions to `missed` without logging

---

### v2.0.0 — Nutrition & Food Log (Care → Food Tab)

- [ ] **Feature** — `NutritionModel` and `NutritionProvider` — meal entries with macros (protein, carbs, fat, calories)
- [ ] **Feature** — Food Log screen: log meals manually; doctor-prescribed dietary protocols shown as governance cards (same `isVerified` pattern as medicines)
- [ ] **Feature** — Nutrition timeline entries wired into `DashboardProvider` — meal slots appear in the Smart Timeline alongside medicines
- [ ] **Feature** — Daily macro summary tile in the Bento-Grid (replaces "Next Meal" placeholder)

---

### v2.1.0 — HealthKit & Health Connect Integration

- [ ] **Feature** — Activate `health` package; add HealthKit entitlements in Xcode + Health Connect permissions in AndroidManifest
- [ ] **Feature** — Sync step count, heart rate, sleep duration from platform health APIs into `HealthService`
- [ ] **Feature** — Step Gauge tile driven by HealthKit/Health Connect data (replacing the current simulated stream)
- [ ] **Feature** — Weekly trends card: 7-day adherence + step history chart (custom `CustomPainter` bar chart)

---

### v2.2.0 — Caregiver Proxy View

- [ ] **Feature** — Caregiver role: a secondary user (family member, carer) can view — but not edit — a patient's medication schedule and adherence log
- [ ] **Feature** — Caregiver invite flow: QR code or deep-link; patient must approve access
- [ ] **Feature** — Caregiver home screen: read-only timeline view of the linked patient; alerts for missed doses
- [ ] **Security** — Firestore rules: caregiver document reads scoped to approved patient IDs only; no write access to any clinical data

---

### v2.3.0 — GPS Walk Maps & Route History

- [ ] **Feature** — Activate `geolocator` + `google_maps_flutter`; add API keys to `AndroidManifest.xml` and `AppDelegate.swift`
- [ ] **Feature** — Live map view during GPS walks: `GoogleMap` widget with real-time polyline drawn from `GpsWalkService` position stream
- [ ] **Feature** — Walk history detail screen: replay route on map, elevation profile (if available), distance / pace stats
- [ ] **Feature** — Doctor-prescribed walk targets: minimum distance / duration; governance card in Activity tab

---

### v2.4.0 — QR Prescription Scanner

- [ ] **Feature** — Activate `mobile_scanner` package; add camera permission
- [ ] **Feature** — Scan a QR code generated by a doctor's system to auto-populate `AddPrescriptionBottomSheet` fields
- [ ] **Feature** — Scanned prescriptions are created with `isVerified = true` and `governanceLevel = physicianVerified` — Clinical Lock applied immediately
- [ ] **Security** — QR payload signature verification: reject unsigned or tampered payloads

---

### v3.0.0 — Doctor Portal & Adherence Reporting

- [ ] **Feature** — Doctor-facing view (role-gated by Firestore Auth custom claims): patient roster, per-patient adherence graph, ability to push verified prescriptions
- [ ] **Feature** — Adherence report card: 30-day completion rate per medicine, missed-dose pattern heatmap
- [ ] **Feature** — In-app messaging: doctor → patient clinical notes (read-only for patient); governance-locked
- [ ] **Security** — Doctor role provisioning: admin Cloud Function sets `role: doctor` custom claim; all doctor-side writes go through server-side validation

---

### Production Milestone — App Store & Play Store Submission

- [ ] **Build** — Production signing: iOS distribution certificate + provisioning profile; Android release keystore
- [ ] **Build** — App Store Connect listing: screenshots, description, privacy policy URL, age rating
- [ ] **Build** — Google Play Console listing: store listing, content rating questionnaire, data safety form
- [ ] **Security** — Penetration testing pass: review Firestore rules, AES key handling, biometric bypass scenarios
- [ ] **Fix** — Accessibility audit: all interactive targets ≥ 48dp; `Semantics` labels on all icons; dynamic text scaling tested
- [ ] **Build** — CI/CD pipeline: GitHub Actions — flutter analyze → flutter test → build APK/IPA on every PR to `main`
