# Windows parity plan — Mac 0.23.0 baseline

This is a local development port, not a release. A passing Mac-hosted Electron
test does not establish Windows runtime parity.

## Repository and architecture assessment

- Inspected `/Users/hosier/Desktop/Mii Plaza`, its ancestors, and Sources, Tests,
  Server and Windows for AGENTS.md; none were present.
- Original main is `ba34746`, 28 commits behind its locally cached origin/main.
  The latest locally available Mac release is `aa544c6` (0.23.0). Current Mac
  and backend sources match that release once untracked source files are included.
  The checkout has extensive user changes and existing release worktrees.
- Work is isolated in the task workspace's `mii-plaza-windows` clone, branch
  `codex/windows-mac-023-parity`. No source checkout writes, fetch, push, release,
  signing, account authorization or production configuration changes were made.
  The clone has no Git remote. The task-level SOURCE-SNAPSHOT.json records input hashes.
- Mac 0.23 retired public Windows distribution but left an extensive local
  Windows 0.4 foundation: Electron UI, C++ Windows/Discord bridge, and a Swift
  subprocess. Restore that foundation on this private branch rather than
  replacing it with an unrelated UI or rewriting the crowd engine.
- Keep `Sources/PlazaCore` authoritative for crowd/entrance/arrival/navigation,
  Mii data/codec, portable validation and published note models. Preparation
  copies those sources into the helper package. Reuse Mac FFL assets and artwork
  through the existing host adapter. Keep OS integration in the native bridge.
- `service-client.cjs` is the testable Windows HTTP transport. The Mac and Windows
  clients use the same backend, account identifiers and `/v1` endpoints. Shared
  Swift contract tests exercise actual Mac Codable models against Windows payloads.
  No server fork, Windows-only community or permission exception is required.

## Concrete acceptance checklist

`Implemented` means local port code and the named Mac-hosted tests are present.
`Inherited` means an existing platform adapter still needs Windows acceptance.
Every row still requires comparison on Windows; none is certified as runtime parity.

| Area | Actual Mac behavior / evidence | Windows status and acceptance work |
|---|---|---|
| Mii creation | CharacterEditor/MiiMakerView: eight categories, feature grids, upright thumbnails, feature adjustments, color, body, rotate/pose, undo/shuffle | Implemented shared feature catalog/artwork and Next → Profile → Save. `test:parity` and `test:library` cover feature editing, codec, flags, draft staging, secondary saves and explicit primary selection. Windows input/GPU/visual comparison remains. |
| Mii library/profile | Primary Mii, saved Miis, rename/edit/delete/import, arrival when saved; primary stays distinguishable | Implemented edits retain the editor; new/imported Miis stage until Save and arrive without replacing primary; Make Primary saves pending edits. `test:library` passes. Native Windows arrival/clipboard/file dialogs remain. |
| Rendering | FFLRenderer/Resources/FFL: same head features, head portraits, optional local FFLResHigh.dat and Men2.pack bodies/animations; fallback/safe mode | Shared Mac renderer/artwork. Fallback and read-only original FFL/body fixtures pass `test:parity`; full private resource-pack import passes `test:pack` when supplied. Unchanged Mac renderer regression also passes. Windows GPU/device-loss acceptance remains. |
| Plaza motion | PlazaCore Crowd/OriginalLounge: deterministic movement, entrance, greetings, center visits, endless population, stable identities across edits/resize | Actual shared Swift engine; 141 core tests (4 fixture skips), `test:runtime` and desktop checks. Stationary poses and independently advancing posts verified; reduced motion finishes entrances/arrivals and freezes crowd. Windows DPI/monitors/sleep remain. |
| Friend Mii visibility | PublicNoteIdentity: service owner/verified Discord identity selects latest published primary appearance; private birthday/creator removed | Implemented verified owner/Discord matching, conflict rejection and public-author visitors; published primary appearances reach both client contracts. Unit/contract/desktop fixtures pass. Real device acceptance remains. |
| App plaza | HomeScreenRotation, Steam shortcuts, app pins/paging/undo, previews, zoom/pan, game gatherings | Implemented Steam/bundle topic matching, latest note-topic gathering priority, app preview discussions, layout reset/undo, paging/zoom. `test:parity` plus planner tests. Windows installed-app discovery/launch/icons remain. |
| Speech/status | PlazaSpeechPost: overhead author-following cards; friend custom status/current or recent game/posts, quiet cadence, hover/focus/pause | Implemented actual Mac cadence/density and source-derived overhead placement, unread-first journal rotation, unique rendered authors, real recent Discord statuses/games, held clock on hover/focus/panels. `test:runtime` and planner tests; Windows edge/resize/accessibility comparison remains. |
| Discord linking | SocialController/Discord bridge: direct SDK PKCE or service OAuth; account verification, encrypted credentials, refresh, unlink, optional sharing | Inherited Windows official SDK + safeStorage/DPAPI. Synthetic sessions tested only; authorized real Windows/Mac accounts still required. |
| Auth and privacy | Server: bearer sessions; Discord-backed canonical names/IDs, block precedence, publisher grants, bounded payloads | Preserve unchanged. Local contract/backend tests exercise rejection, canonical identity, likes/replies and retraction. |
| Audiences | Models/NoteAudience: new Public, Friends Only, Private; legacy shared/drafts stay friends-only; private stays local | Implemented first slice. Wire audience preserved, old Windows `public` label migrated once to friends, UI has all three choices. |
| Cross-platform feed | SharedJournalNote, same /v1/notes(/threads,/owned): both platforms' Miis/posts/drawings/topics visible | Local Swift ↔ JS ↔ real HTTP backend test passes. Actual two-device Discord test remains. |
| Communities/feed | MiiverseCatalog/MiiverseView: all-post Activity Feed, My/Friends/Public, Plaza pinned, Steam ID/bundle topics, search/sort/likes | Implemented four-page rail, pinned Plaza, spotlight/cards, popularity/recent-use ranking, shuffle/name/search, Steam/bundle topics and canonical identities. `test:current`, `test:features` and catalog tests pass. Windows visual comparison remains. |
| Posts and drawings | Journal: text, described square ink, app/plaza topics, private author choice, public primary/Discord identity, export PNG | Implemented original composer/drawing with three audiences, local author selection and PNG export; shared edits retain local replies separately from service replies. `test:desktop`, `test:features`, portable tests and contracts cover local flows. Windows pen/input comparison remains. |
| Shared interactions | SharedNoteInteractions: one like per account, up to 50 replies, author editing/deletion and post-owner reply deletion | Existing local-first queue uses unchanged service permissions. Contracts and `test:desktop` cover likes/replies, edit preservation, owner restrictions, offline delivery/restart, privacy retraction and blocking. Real devices remain. |
| Retention/recovery | NoteRetention/LocalSocialState: seven days, edits cannot extend lifetime, queued idempotent retries, no first-login destructive replacement | Seven-day pruning and unchanged created dates, idempotent queued retries, first-login merge preservation. Unit/backend/desktop fixtures pass; `test:recovery` covers semantic corruption, preserved input and good backup. Native crash/restart remains. |
| Notifications | PlazaActivity: account cursor, unread bell, native alerts, privacy-safe presentation, click opens exact post | Implemented Notifications page, account-scoped cursor/read queue, unread badge, privacy-safe in-app toast, exact-post routing, native click handler and immediate cross-window logout. `test:notifications` passes with synthetic accounts. Native Windows alert permissions/click behavior remain. |
| Resizable Miiverse | MiiverseWindow: independent 1000×720 window, 720×540 minimum, restore/clamp bounds, reopen all-post feed, close/visibility manages music | Implemented independent 1000×720 content, 720×540 content minimum (native chrome accounted), per-display outer bounds restore/clamp, all-post reopen and continued background plaza. `test:window` passes on Mac; mixed DPI/monitor/native Windows chrome remains. |
| Theme music | PlazaAudio/MusicLibrary: per-role volumes, crossfades, previews/import/apply/cancel; main playhead continues, yields to other audio/fullscreen/capture | Implemented identical Mac role/file mapping and default volumes (plaza .12, other music .10, UI effects .18), per-role mixer/crossfade, held plaza playhead, preview/import/apply/cancel and alternate role; child-panel close restores visible parent music. Local tests pass. Windows audio/capture/coverage integration remains. |
| Alternate Miiverse theme | MiiverseAccountView/miiverseAlternateTheme: optional local imported audio, preview then apply; no public Nintendo recording bundle | Implemented optional imported audio, preference and User Menu preview/cancel/apply with existing track retained until apply. `test:current` passes, including restart and writing/child-panel transitions. Existing local Mac recordings are staged privately for all seven roles; source-only builds fall back to generated audio. No recording was downloaded or committed. |
| Primary birthday | MiiverseBirthdaySettings: primary-only local month/day, leap-aware validation, save/clear | Implemented primary-only User Menu month/day, valid month lengths (February 29 allowed), save/clear and secondary isolation. `test:current` and calendar tests pass. Birthday/creator are redacted by shared publishing. |
| Birthday effects | BirthdayCelebration: once/year persistent local receipt; primary only; six-second nonfocus click-through glitter, three-second still reduced motion; defer while unavailable | Implemented persistent once-year receipt, six-second nonfocus click-through glitter or three-second still reduced-motion greeting; availability/lock/sleep/covered/sheet/recovery/safe-mode gates. `test:current` verifies deferral, nonfocus still, receipt/restart; unit tests cover gating. Native Windows overlay/multimonitor proof remains. |
| Profile editing | Miiverse User Menu + SocialSettings: Discord public name/identity, primary appearance, local profile note/share toggles | Implemented User Menu with canonical Discord name, link/setup, Edit Your Mii, birthday and alternate theme; existing sharing controls retain backend identity rules. Local UI/contracts pass. Real Discord device authorization remains. |
| Saving | DocumentStorage/local social: serialized atomic writes, backups, unreadable-file preservation, account/origin isolation, safe/recovery mode | Atomic account/origin-isolated store and backup; semantic validation prevents corrupt JSON replacing a good backup. `test:recovery` preserves unreadable input, restores draft, blocks writes until recovery and exercises safe-mode transitions. Windows DPAPI/crash handling remains. |
| Import/export | Version 2 portable Plaza JSON, Foundation 2001 dates, Mii binary/JSON/PNG, Windows reconnects OS-specific shortcuts | Implemented v2 Foundation-date exchange for owned public/friends/private posts, audiences, drafts/authors/topics, local replies/read/appreciation and custom icons; excludes received posts/service replies, app paths/bookmarks. Portable unit/Swift contracts pass; UUID case coalesces source IDs. Windows dialogs remain. |
| Resource packs | PlazaResourcePack: private .plazapack validation, checksums/path bounds, preview/test-render then transaction/backups/rollback | Existing checked/path-bounded transaction/backup/rollback and preview/render validation; unit tests and optional `test:pack` use local licensed resources only. Native Windows decode/GPU acceptance remains. |
| Settings/accessibility | Nine categories; motion/posts/privacy/population, audio/effects, startup/wallpaper, sharing, recovery; larger text/reduced motion | Nine categories, effect volumes, motion/posts/privacy/population, alternate theme, larger text, reduced motion and compatible update badge. Local UI/focus/safe-mode tests pass. Windows keyboard/Narrator/high-DPI/system integration remains. |
| Accessible list | PlazaView/AppListView: all apps with Details/Open/Locate, friends and searchable journal; Ctrl/Command-L toggle; hidden crowd stationary; plaza music muted while companion tracks remain | Implemented local list view and shortcut. `test:list` covers full list beyond island pages, off-page details, search, note routing and music/motion transitions. Windows Narrator, keyboard and high-DPI acceptance remain. |
| Wallpaper/lifecycle | DesktopPlaza: passive desktop, interaction/companion panels, Return to Desktop, startup; pause hidden/locked/covered | Windows Explorer/tray implementation inherited. Windows shell, monitor, lock/sleep and capture tests are mandatory. |
| Update delivery | Mac Sparkle + compatible update badge; Windows existing signed manifest/checksum/installer worker | Unchanged pinned signature/checksum/installer worker; unit signed fixtures verify checks/download tamper rejection/restart, local UI test verifies badge states. Windows NSIS upgrade/relaunch requires installed Windows fixture. No feed/install/signing/release changes or live downloads. |
| Diagnostics | PlazaDiagnostics/BugReport: manual export, scrub personal paths, no account data/music/dumps, review before send | Existing scrubbed manual ZIP and unsent email draft. Local `test:features` confirms ZIP contains tester description and excludes draft content. Windows crash metadata/Explorer/email association remain. |

## Staged remaining work

1. **Local implementation and fixtures completed:** latest Mac preserved, Windows
   foundation restored, shared contracts/audience migration, independent Miiverse,
   current UI, birthday/theme, library/portable fidelity, speech/gathering and recovery.
   Evidence and exact test counts are recorded in the task workspace HANDOFF.md.
2. **Windows x64 build and acceptance — pending environment:** Windows 10/11,
   Visual C++/Windows SDK, Swift for Windows (existing workflow pins 6.4.1),
   official Discord Social SDK Windows headers/libraries/runtime. The existing
   local SDK directory (manifest 1.10.19337, x64 DLL) is already staged privately;
   its original archive was absent, so archive checksum verification remains.
   Build helper and C++ adapter; launch unpacked app; run all fixture suites,
   including native sections of `test:parity`. Fix any compiler/ABI/platform issues
   before comparing feature/behavior and visual results against Mac 0.23.
3. **Windows OS matrix — pending device:** installed-app/Steam discovery and
   launch, Explorer wallpaper/tray/startup, DPAPI, notifications, GPU/body rendering,
   DPI/text scaling/Narrator, multiple monitors, coverage/capture/audio, lock/sleep,
   recovery and 6-second/3-second birthday overlay. Mac-hosted tests do not prove
   these native paths. No Windows executable from this branch has been built yet.
4. **Authorized real two-device accounts — pending accounts/device:** link Mac
   and Windows to the same existing service, verify mutual primary Miis, public and
   Friends Only visibility, private exclusion, canonical Discord identities, shared
   text/drawings/Steam communities/replies/likes/activity and block/revoke behavior.
   Use dedicated authorized accounts; do not post to real users.
5. **Local installer/update acceptance — pending Windows:** create unsigned local
   NSIS/ZIP, verify clean install/uninstall and data-preserving upgrade/relaunch with
   local signed fixtures (`test:updates` requires its documented fixture inputs).
   Review source/notices/vendor redistribution completeness before any release.
6. **Release work remains outside scope:** no publishing, push, workflow dispatch,
   signing credential creation, paid services or production/security changes. The
   historical update feed/downloads are not proof of a current supported Windows
   release. Delivery must be reviewed separately when requested.

Build/run commands are in BUILDING.md. Remaining platform tests are pending due to
an unavailable Windows environment, not an approval denial.

## Requested testing release

The user subsequently requested a GitHub windows branch and a public website
download explicitly marked untested for friends. The 0.4.5 preview workflow now
separates branch contract checks from tag-triggered unsigned preview packaging.
Public downloads exclude local Nintendo audio and standalone vendor SDK inputs.
This authorizes the testing app release and site update; it does not establish
hands-on Windows parity or authorize a stable/automatic-update release.
