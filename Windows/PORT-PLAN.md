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

`Inherited` means code exists and needs current Windows verification. `Partial`
means work remains. No row is certified as 1:1 Windows runtime parity yet.

| Area | Actual Mac behavior / evidence | Windows status and acceptance work |
|---|---|---|
| Mii creation | CharacterEditor/MiiMakerView: eight categories, feature grids, upright thumbnails, feature adjustments, color, body, rotate/pose, undo/shuffle | Inherited. Same feature catalog/artwork; run all categories and verify corrected upright feature thumbnails against Mac 0.23. |
| Mii library/profile | Primary Mii, saved Miis, rename/edit/delete/import, arrival when saved; primary stays distinguishable | Inherited. Verify selecting primary, multi-Mii saving and library/arrival behavior on Windows. |
| Rendering | FFLRenderer/Resources/FFL: same head features, head portraits, optional local FFLResHigh.dat and Men2.pack bodies/animations; fallback/safe mode | Inherited shared adapter. Local fallback tested; imported-resource rendering and Windows GPU/lost-device tests remain. |
| Plaza motion | PlazaCore Crowd/OriginalLounge: deterministic movement, entrance, greetings, center visits, endless population, stable identities across edits/resize | Shared Swift foundation. Test on Windows at multiple DPIs, monitors, population sizes and sleep/resume. |
| Friend Mii visibility | PublicNoteIdentity: service owner/verified Discord identity selects latest published primary appearance; private birthday/creator removed | First slice applies latest shared primary appearance using verified owner/Discord links; conflict/ambiguity cases are unit tested. Native device/visibility acceptance remains. |
| App plaza | HomeScreenRotation, Steam shortcuts, app pins/paging/undo, previews, zoom/pan, game gatherings | Inherited. Windows installed apps/Steam replace native .app launchers. Note-topic gatherings and exact spatial/speech parity remain to audit. |
| Speech/status | PlazaSpeechPost: overhead author-following cards; friend custom status/current or recent game/posts, quiet cadence, hover/focus/pause | Partial. Shared cadence/anchors exist; compare status priority, temporary assigned friends, author selection and edge/resize behavior. |
| Discord linking | SocialController/Discord bridge: direct SDK PKCE or service OAuth; account verification, encrypted credentials, refresh, unlink, optional sharing | Inherited Windows official SDK + safeStorage/DPAPI. Synthetic sessions tested only; authorized real Windows/Mac accounts still required. |
| Auth and privacy | Server: bearer sessions; Discord-backed canonical names/IDs, block precedence, publisher grants, bounded payloads | Preserve unchanged. Local contract/backend tests exercise rejection, canonical identity, likes/replies and retraction. |
| Audiences | Models/NoteAudience: new Public, Friends Only, Private; legacy shared/drafts stay friends-only; private stays local | Implemented first slice. Wire audience preserved, old Windows `public` label migrated once to friends, UI has all three choices. |
| Cross-platform feed | SharedJournalNote, same /v1/notes(/threads,/owned): both platforms' Miis/posts/drawings/topics visible | Local Swift ↔ JS ↔ real HTTP backend test passes. Actual two-device Discord test remains. |
| Communities/feed | MiiverseCatalog/MiiverseView: all-post Activity Feed, My/Friends/Public, Plaza pinned, Steam ID/bundle topics, search/sort/likes | Partial. Windows indexes/filtering exist; unrelated public authors excluded from Friends. Mac navigation rail, community cards, popularity/recent-use ranking/shuffle remain. |
| Posts and drawings | Journal: text, described square ink, app/plaza topics, private author choice, public primary/Discord identity, export PNG | Inherited plus audience fixes. Verify composer/drawing on Windows and draft transitions for each audience. |
| Shared interactions | SharedNoteInteractions: one like per account, up to 50 replies, author editing/deletion and post-owner reply deletion | Inherited local-first queue. Contracts test permissions and identity. UI regression and real devices remain. |
| Retention/recovery | NoteRetention/LocalSocialState: seven days, edits cannot extend lifetime, queued idempotent retries, no first-login destructive replacement | Inherited; unit/backend contracts cover this. Windows restart/offline/deletion undo acceptance remains. |
| Notifications | PlazaActivity: account cursor, unread bell, native alerts, privacy-safe presentation, click opens exact post | Inherited. Verify Windows notification click/read state, quiet first history and badge. Mac Miiverse Notifications page remains. |
| Resizable Miiverse | MiiverseWindow: independent 1000×720 window, 720×540 minimum, restore/clamp bounds, reopen all-post feed, close/visibility manages music | Implemented foundation. Independent window everywhere, bounds persist locally, main plaza continues. Test minimize/restore, reopen, mixed panels, multiple monitors and native Windows chrome. |
| Theme music | PlazaAudio/MusicLibrary: per-role volumes, crossfades, previews/import/apply/cancel; main playhead continues, yields to other audio/fullscreen/capture | Inherited six roles plus separate UI effects. Windows audio focus/capture/coverage tests remain. |
| Alternate Miiverse theme | MiiverseAccountView/miiverseAlternateTheme: optional local imported audio, preview then apply; no public Nintendo recording bundle | Missing. Add role/preference and User Menu controls; do not download/bundle recordings automatically. |
| Primary birthday | MiiverseBirthdaySettings: primary-only local month/day, leap-aware validation, save/clear | Partial. Maker month/day storage exists; primary User Menu controls and calendar-valid input remain. |
| Birthday effects | BirthdayCelebration: once/year persistent local receipt; primary only; six-second nonfocus click-through glitter, three-second still reduced motion; defer while unavailable | Missing. Implement Windows overlay, local receipt, visibility/lock/fullscreen gating and calendar/secondary-Mii tests; never include birthday in network payloads. |
| Profile editing | Miiverse User Menu + SocialSettings: Discord public name/identity, primary appearance, local profile note/share toggles | Inherited settings. Canonical account identity preserved; current Miiverse User Menu presentation remains. |
| Saving | DocumentStorage/local social: serialized atomic writes, backups, unreadable-file preservation, account/origin isolation, safe/recovery mode | Inherited Windows atomic store. Verify backups/recovery/crash handling and import errors on Windows. |
| Import/export | Version 2 portable Plaza JSON, Foundation 2001 dates, Mii binary/JSON/PNG, Windows reconnects OS-specific shortcuts | Inherited; audience-bearing drafts fixed. Audit Mac shared-note/local-note portability: current Windows export only includes private notes and import localizes notes; this is an identified parity gap. |
| Resource packs | PlazaResourcePack: private .plazapack validation, checksums/path bounds, preview/test-render then transaction/backups/rollback | Inherited with unit tests. Private local licensed fixture required for full rendering/audio test. |
| Settings/accessibility | Nine categories; motion/posts/privacy/population, audio/effects, startup/wallpaper, sharing, recovery; larger text/reduced motion | Inherited. Test keyboard, focus, high DPI, screen reader labels, clipping and system reduced motion on Windows. |
| Wallpaper/lifecycle | DesktopPlaza: passive desktop, interaction/companion panels, Return to Desktop, startup; pause hidden/locked/covered | Windows Explorer/tray implementation inherited. Windows shell, monitor, lock/sleep and capture tests are mandatory. |
| Update delivery | Mac Sparkle + compatible update badge; Windows existing signed manifest/checksum/installer worker | Preserve signature rules. No feed/install/signing changes or downloads performed. Current Windows release service may be retired; test with local signed fixtures and review delivery separately. |
| Diagnostics | PlazaDiagnostics/BugReport: manual export, scrub personal paths, no account data/music/dumps, review before send | Inherited local ZIP/email draft. No reports sent. Validate Windows crash metadata and exported archive. |

## Staged remaining work

1. **This milestone:** preserve latest Mac, recover Windows foundation, wire-audience
   compatibility/migration, local transport, real cross-language protocol tests,
   independent Miiverse window and reproducible local instructions.
2. **Current-Mac UI/domain parity:** four-page Miiverse navigation, ranked communities,
   latest published Mii identity, note-topic gatherings/speech, primary birthdays/effect,
   alternate theme, update badge, portable post/draft fidelity. Keep a checked item
   tied to tests/screenshots rather than assuming the older Windows release matches.
3. **Native Windows validation:** compile Swift helper/C++ bridge on Windows x64,
   installed/portable launch, Discord SDK/DPAPI, GPU/head/body rendering, Explorer,
   tray, DPI/monitors, lock/sleep, audio/capture, notifications and accessibility.
   Run local fixture suites before authorized real two-device tests.
4. **Release review later:** unsigned local installer smoke test, upgrade/data
   migration, rollback, license/source completeness and update fixtures. Publishing,
   production changes, credential creation and signing require a separate request.

Build/run commands and evidence are in BUILDING.md and the task workspace HANDOFF.md.
