# Original WaraWara Plaza crowd controller port

Status: native components extended in Mac Plaza 0.12. The complete crowd
behavior program has not been ported. This document distinguishes recovered
logic from the native host adaptations and remaining recreation.

## Verified source

US Wii U Menu, title `0005001010040100`, version 277. Existing local executable:
`Local Resources/Wii U Menu/Research/men.rpx`.

SHA-256:
`b67deb8fb36889fd5451b89a5b1ce06b31abe341960c3bf1df84e9df4bbe1474`.

The title metadata/content SHA-1 was verified before extracting this RPX. It is
ELF32 big-endian PowerPC with compressed sections. Relevant data relocations
were resolved statically. Ghidra with Espresso/Gekko paired-single definitions
and the original GQR0 context was used for control-flow recovery; default PPC
disassembly incorrectly treats paired-single instructions as AltiVec.

The executable, decompressed sections, decompiler projects/output and fixtures
remain in ignored local research folders. They are not bundled with the app or
source archive. The app neither imports nor interprets RPX code. All runtime
behavior below is Swift, using bundled renderer code and separately installed
local body/head resources.

## Active native routines

| Original address | Recovered behavior | Native implementation |
| --- | --- | --- |
| `02454a98`, `02454b34`, `0218a88c` | Seed expansion, xorshift128, high-product bounded draws | `OriginalLoungeRandom` |
| `021902d4` | Positional action mask parsing | `OriginalLounge.actionMask` |
| `02183104` | Animation/actor restriction flags | `OriginalLounge.restrictions` |
| `100f43f8` | 128 animation names, blend frames, outgoing limits and flags | `OriginalLoungeAnimations.swift` |
| `021931d0` | Main/entrance/exit clip lookup | `OriginalLoungeCatalog` |
| `02194214` | Interrupts, seated exits, transition stage and blend limits | `OriginalLounge.transition`, `OriginalLoungePlayback.request` |
| `02196a30` | Blend/stage/queue and loop-boundary change guards | `OriginalLounge.mayChangeAnimation` |
| `021947d4` (stage and social dispatch paths) | Exit→entrance→main advancement; social action→animation mapping | `OriginalLoungePlayback.finishStages`, `socialAnimation` |
| `02192abc`, `02192808` (playback math) | Frame/rate, linear blend advancement, wrapping/clamping | `OriginalLoungePlayback` |
| `02199fc8`, `0219a320`, `0219a0b8` | Baseline selection, rare action selection and follow-ups | `OriginalLounge.selectIdle` |
| `02198da0`, `02199308` (ordinary ambient paths) | Idle holding, intermediate/follow-up stages and baseline return | `OriginalLoungeIdle` |
| `02188b08…021894c4` (paired action selection and timer paths) | Talk/dance/RPS choices, complementary actions, role handoff, duration and rate | `OriginalLoungeSocial.swift` |
| `021843e8` (cooldown draw) | 900–1199-update social cooldown | `OriginalLounge.socialCooldown` |
| `0218e378`, `0218e458`, `021a5154` (eligible-pair branch) | Strict 18-unit mutual facing predicate, first eligible neighbor | `OriginalLounge.acceptsPartner`, native spatial query |
| `0218e60c…0218e768` | Sign/role and bow/talk opening draws | `OriginalLounge.startSocial` |
| `0218e7f4`, `0218e99c…0218ebac` | Side-by-side dance eligibility and orbit dance selector | `OriginalLounge.acceptsDance`, `startDance` |
| `021882b0…02188af8` (paired positioning) | Six-frame phase gap, 0.7/1 playback rate, 9/11-unit spacing, phase pulse, tangent heading | `OriginalLounge.pairedRate`, `dancePosition` |
| `021ad1e4…021ad5d4` | Ten accepted destinations, preferred-distance score, obstacle clearance relaxation, special-role ellipse | `OriginalLounge.destination` |
| `021a5660` (circle-overlap reduction) | Componentwise min/max overlap correction | `OriginalLounge.separation` |
| `02185250…02185578` | Ordinary walk speed, turn-dependent direction smoothing, movement ramp and acceleration cap | `OriginalLoungeMotion.walk` |
| `02184dbc…02184e44`, `02185c4c` (ordinary target prefix) | Foot-phase stop radius and target smoothing | `walkStopRadius`, `OriginalLoungeMotion.step` |
| `02186c64…02186dbc`, `02187574` (integration blocks) | Opposing-contact filter, perpendicular impulse, 0.92 damping, gait projection, speed recovery and correction memory | `OriginalLoungeCollision` |
| `0219220c`, `021922b0`, `02192374` | Direction masks, random start slot and cyclic six-slot neighbor search | `OriginalLoungeGroup.swift` |
| `0218e4ac`, `0217f42c…0217f4e0`, `0217ec38…0217edd4` | Wider mutual facing predicate, automatic fourth-root dance gate and idle facing-bias draws | `acceptsGroupFacing`, `automaticDanceGate`, `groupTurn` |
| `02186808…02186a08` | Heading wrap, capped proportional turn, delta and lean accumulators | `OriginalLoungeHeading` |
| `0218a8f8` (refresh draw), `02196e04` (walk rate clamp) | Destination refresh interval and distance-related walk rate | Native crowd adapter |

Action masks/restrictions are verified components, but the host has not yet
replaced every legacy eligibility check with these flags. Ordinary idle state
updates are ported for ambient characters. Family arrival/emotion and the complete reactive
controller branches are outside this implementation. The host now acquires reciprocal pairs through the recovered standing predicate and first eligible native neighbor; standing partner query order and locking are replaced by a native spatial index; automatic group events use the recovered node database. Eligibility has no extra blend/stage restriction. Opening interactions retain the source sign draw and bow/talk choice. Subsequent actions retain role handoff. Animation requests for the same ID no longer overwrite an ongoing paired phase rate; walk rate updates use the separate source rate-setter path.

Clip data stays in the installed `plaza-body.json`. The native catalog requires
all 128 descriptor names to resolve and preserves resource indices. The body
renderer evaluates the source curves for the exact incoming/outgoing samples
and linearly mixes local transforms using the native weight. The legacy fixed
crossfade and activity sequence chooser are bypassed for native crowd samples.

The recovered collision gait accumulator now contributes to ordinary walking, running and tired clip rates through the source clamps/multipliers.

## Host adaptations and outstanding port

- The native app supplies source-unit bounds, obstacle circles and a stable spatial neighbor order. The source destination search uses ten accepted samples and relaxes only the rejecting obstacle's squared clearance by 0.9. The host bounds pathological searches at 1024 attempts; up to four searches adapt results to the Mac control rectangles. Visibility graph routing and blocked-layout recovery remain native. Local saved actors map to the original 150 × 130 central ellipse roles; other actors use the source uniform rectangle. Host sin/pow replace original trig-table/pow calls for ellipse roles.
- Circle separation now feeds the recovered contact and impulse controller for all actors, including stationary ones. Opposition is tested before the per-axis sign-reversal filter. A movable dominant neighbor halves the correction; relative prior-tick displacement produces a perpendicular impulse of -0.05 times correction length. Impulses decay by 0.92 each update, even for actors whose source restrictions block pushes. Correction memory/gait use 0.1 gain; speed scale recovers toward 1 or drops toward 0.03 with the original urgency gain. Reciprocal pairs have the original movement-blocking restriction. A native spatial hash supplies overlap candidates and largest-penetration dominant contact, with host radius 8. Those query/radius/ordering choices, coherent snapshots replacing owner locks, and Mac rectangle rejection remain adapters. The standing collision reaction branch now selects source clips 81–84 with the source closing/lateral thresholds, rates and lateral blend duration. The source type-0 rate stays 1 because its gain register is zero. The source refresh draw is consumed even when restrictions reject a reaction. The native idle controller holds the selected reaction for at least 60 updates and clip completion before returning to its baseline. The original randomized surprise followups, +430 additive displacement, avoidance-angle accumulator and render linkage remain outstanding.
- Paired phase correction and orbit root positioning are active. Only main-stage frames participate in the gap/pulse; other stages contribute frame zero. The gap is truncated before integer remainder; a gap greater than six and less than half the main clip length sets rate 0.7, otherwise 1. Orbit actions 13/14 prefer eleven units, other actions 11…20 nine units. The phase pulse, square-root spacing correction, parity-dependent tangent, 0.1 gain and 1 cap are retained. Source SDK normalization and refined reciprocal-square-root estimates are adapted through host sqrt; small numerical differences are possible. Both actors read a coherent native tick snapshot rather than the menu's concurrent owner objects. Mac bounds/control collisions can reject a root move.
- Automatic group opportunities now run without user input. The dispatcher selects one actor with the original bounded draw and movement/restriction guard, tries a population-scaled forward facing opportunity, then uses the source fourth-root population gate for side-by-side dances. Each directional search draws one starting slot and cyclically scans the original six masks, preserving empty-slot draw behavior. Successful dances use the existing original selector, timers and root positioning. App gatherings use the recovered 397-node axial topology and immediate occupied neighbor slots, replacing proximity-sector occupancy. The source six-direction ray searches and strict assignment-cost swap chains are active in maintenance. Occupancy counts, list slots and occupied-to-vacant move primitives are retained; the source vacancy-fill admission/owner callback path is not active. Mac membership/admission chooses an available legal node near the existing actor, and one app database receives a maintenance opportunity per host tick. These are explicit host boundaries. Group geometry changes and source swaps only update destinations, never current positions. Greeting attempts are explicitly treated as rejected by the unported greeting controller; facing requests use a host heading target. General watch/message handlers are absent (the neighbor-search draw is retained). This is a port of the automatic dance opportunity path, not the complete global dispatcher or original database owner/admission program. Local app reactions remain a separate host event.
- Ordinary walking now uses the recovered state-1 speed/direction block rather than deriving travel from clip stride. The source distance ramp (0.15 to height-dependent 0.22–0.25), turning alignment/damping, 0.003 movement ramp, acceleration cap and 0.05 target smoothing are active. A gait-phase stop radius of 2–6 source units replaces the old fixed arrival tolerance. Original walk animation rate uses projected forward displacement divided by the host body stature, clamped by the existing source rate setter. Paths and bounds remain native. Starting an available walk is gated by the native playback stage; the full source animation-controller readiness branch has not been ported. The recovered state-0…6 worker now supplies walk/run/tired/fall/recovery/catch-breath transitions, cooldown decrement/reset, run fall/tired RNG gates, assigned/unassigned run speed ramps, tired/fall/breath damping and source animation IDs (including recovery animation 60). Run style uses the ordinary source constructor’s two rare draws; forced owner styles and special role 3 are explicit inputs to the port. Running and tired clip rates include collision gait. Forward-neighbor detours, gait-dependent minimum forward translation, head-look and blink remain outstanding. Entrance choreography is a separate native presentation path.
- Scalar heading math is ported and used for walking, local acknowledgements
  and ordinary paired facing. The host supplies bearings through macOS libm
  rather than the original Wii U atan/table routines. Walking currently uses
  the original caller's 0.2 gain / 0.4 cap; gait-dependent cap inputs remain
  outstanding. Ordinary pairs retain the source 45-degree threshold and
  0.01 gain / 1.5 cap. Original lean accumulators are verified but not yet
  connected to the renderer's root transform.
- The host supplies one random seed per boot (deterministic seeds for tests), local actor iteration order, density
  inputs and fixed 60 Hz controller ticks, with 30 Hz rendering. Original timer
  units are retained as updates/source frames. Exact console scheduler cadence
  has not been verified; a frame-perfect Wii U scene comparison is outstanding.
- Click acknowledgements and app-launch reactions are native host events. The
  complete original greeting acquisition/expiry path, family arrivals, feed
  message presentation and special character roles remain outstanding.
- No menu process, Wii U OS calls, account/network/feed services or Pretendo
  integration are required. The resource-free fallback remains usable.

Main original entry points for further recovery: actor worker `0218d738`, behavior
update `0218a8f8`, movement `02184b24`, heading `021867c8`, collision/neighbors
`02187574`/`021a3e18`, and social partner/alignment update `02187cc0`. Recovered
decompiler output alone is insufficient evidence of an exact port: jump tables,
paired-single math, external owner predicates and scheduler inputs must be
accounted for before activating further paths.

## Reproducible local verification

Generate the descriptor report and original-instruction fixtures from the
existing verified executable, without downloading or booting anything:

```sh
python3 scripts/recover-lounge.py \
  'Local Resources/Wii U Menu/Research/men.rpx' \
  --output .qa/original-lounge --oracle

PLAZA_ORIGINAL_LOGIC_QA="$PWD/.qa/original-lounge/original-routine-vectors.json" \
swift test --disable-sandbox --filter OriginalLounge
```

The script is a bounded, read-only-code PowerPC decision-routine test runner. It
rejects a different executable hash, unsupported instructions, unknown memory
accesses and exhausted instruction budgets. Only audited routine entry points
are exposed. It is development code, not an app dependency or full emulator.

Fixtures cover 65,536 transition cases, 7,168 restriction combinations, all
4,096 action masks, 2,400 idle selections, 12,000 social selections, 1,000 paired
timers/rates, 1,701 heading updates, five 100-draw random traces, plus 1,584 partner predicates, 1,000 social starts, 1,050 dance predicates, 1,000 dance starts, 400 destination searches and 4,000 paired phase/root cases. Swift outputs and final RNG state
are compared to the original instruction results, including rejected draws.

For isolated social decision blocks, the original prefix's live constants are
supplied explicitly. Timer tests provide synthetic clip lengths (40 loop / 12
one-shot frames) to the original runtime frame table and to the native catalog.
This checks timer behavior independently of body-asset extraction. The idle
selector's external database cooldown write is replaced by an explicit host
fixture after selection has completed. Audited paired-single save shuttles for
unused second lanes are omitted; primary lanes retain original saves/restores.
These are stated oracle boundaries, not claims of executing the entire actor. The spatial fixture runner decodes audited GQR0 paired-single arithmetic for root positioning. Destination fixtures provide native world extents/item circles and a host SDK point-to-segment adapter; they verify source candidate acceptance, retry draw order and score selection, not the original SDK geometry implementation. Side-by-side predicates and roots use host normalization; the reciprocal-square-root instruction uses host sqrt followed by the original refinement operations. Dance roots are checked within 0.000002 source units, heading inputs within 0.000001. The paired phase/start/predicate outputs and destination selections/RNG states match their original instruction fixtures.
Heading fixtures start after atan and stop before the table-based matrix
construction, supplying the original prefix's live bearing/gain/cap explicitly.

The native dance integration test reaches the separate source selector through an eligible local event and checks reciprocal partners plus smooth phase-weighted root travel without snapping. A regression test preserves ongoing phase rates across repeated animation requests. The native host test simulates 120 seconds with 60 characters, checks reciprocal
action/timer/leader ownership, bounds and finite samples, and compares identical
traces under 30/60 Hz delivery. Rendering tests use actual locally installed
FFL/Men2 resources to check clip/frame/blend delivery and repeated paused poses.
Provide `PLAZA_MENU_QA_RESOURCE` and `PLAZA_FFL_QA_RESOURCE` paths for these tests;
they do not fetch resources. A rendered crowd sample is saved under `.qa/`.

Parity for the listed decisions does not establish full-scene equivalence, all original neighbor/database behavior, the complete global group-event dispatcher, every original idle update branch, or console timing.

Mac Plaza 0.9 validation: 67 tests passed with local FFL/menu resources; after the structured frame-bridge optimization, all 20 native app/renderer tests passed again. The high-frequency bridge sends numeric pose arrays as WebKit structured arguments and coalesces pending snapshots. No pose quantization, network endpoint or new runtime dependency was added. Logs: `.qa/spatial-full-tests.log`, `.qa/spatial-bridge-tests.log`.

The normal 60-character app was checked locally for pause/resume and minimize/restore. Main app, content and GPU processes all reported zero CPU in the minimized samples. Brief visible/minimized metrics and their limits are recorded in LOCAL_FEATURES.md; no full-scene console equivalence is implied.

## 0.11 locomotion, collision and automatic event verification

The bounded offline runner adds 6,668 original-instruction cases: 567 ordinary
walk speed/direction updates, 132 foot-phase stops, 100 filtered contacts/impulses,
128 collision integrations, 1,800 slot searches, 721 direction masks, 420 wider
facing predicates, 1,600 dance gates and 1,200 idle turns. The existing source
fingerprint, unknown-instruction/memory failures and bounded execution remain.
Walk/contact floats use 0.000002 tolerance for host sqrt/SDK normalization;
collision integration uses 0.000001. Selection and final RNG words match.
The oracle starts inside the audited walk/contact/integration blocks with live
registers supplied explicitly. Collider queries/owner locks are outside those
fixtures. Direction masks provide host atan2; fourth-root gates provide a host
reciprocal-square-root estimate followed by the original refinement. These tests
verify the listed components, not the entire actor worker.

Four deterministic dense 60-actor crowds were simulated for 120 seconds each,
without click/cheer input. Contact impulses were exercised, positions stayed
bounded/finite, and partners stayed reciprocal. A separate known source-eligible
two-actor placement reaches automatic orbit dancing without click/cheer input;
random dense scenes are not required to dance within a fixed observation window.
30/60 Hz delivery produced identical final crowd states. The existing 120-second
ordinary integration trace still exercises the original bow/talk/RPS actions and
more than 20 source clips. Native renderer checks use the separately installed
original FFL and body resources. All runtime changes remain local Swift; no new
network service, executable interpreter or downloaded asset is involved.

A release controller-only benchmark with synthetic 40/12-frame clips and a
48-unit-wide, ten-icon host layout measured 0.046 / 0.155 / 0.201 ms mean per
update for 60 / 160 / 200 actors, respectively; p95 was 0.056 / 0.194 / 0.254 ms.
Each run covered 3,600 fixed ticks and checked finite/bounded final positions.
These are brief local simulation timings, excluding renderer, asset loading and
UI, not a battery or whole-app performance claim. Log: `.qa/motion-benchmark.log`.

Final isolated 0.11 verification: 106 tests executed, 105 passed and one optional
social screenshot test skipped, with zero failures
(`.qa/motion-snapshot-final-tests.log`).
Actual local FFL/body rendering, source instruction fixtures, automatic dance
reachability, dense contacts and fixed-tick integration checks are included.
The normal 160-Mii native plaza and wallpaper presentation were inspected;
pause/resume was verified and restored. The paused samples reported 0.7% main,
0.1% content and 0.0% GPU CPU in the final brief sample (`.qa/motion-paused.log`).
These observations are not a sustained energy benchmark. Native preview:
`.qa/Locomotion Port Plaza.png`.

## 0.12 group database, locomotion and continuity

The database port retains all 397 axial nodes (rings 0–11), the original six
neighbor offsets, source geometry arithmetic, occupancy list slots, adjacent
occupancy counts, same-direction searches through vacancies, occupied swaps,
and occupied-to-vacant moves. Cost-improving swap chains retain the original
cyclic random scan, strict Float cost comparison, continuation mask and special
actor stop. In particular, the original PPC shift drops the previous-direction
bit for slot zero; the native port preserves that behavior. App membership,
nearest legal initial admission, window rejection and maintenance cadence remain
Mac host inputs. Source vacancy-filling and full owner callbacks remain pending.

The full state-decision prefix and speed blocks of `02184b24` are exercised with
2,296 instruction fixtures, including threshold boundaries, assigned/unassigned
running, rare fall and tired entry, damping ages, completion-driven recovery and
300-update run cooldown. The host supplies animation readiness/completion,
ordinary role inputs and visibility routes. Original clips 0/3/4/5/6/7/1/60/2 are
selected by these states and run styles; no replacement animations were added.

Another 397 original ring-coordinate cases, 40 swap-cost predicates, 96 recursive
swap-chain traces and 140 standing-collision reaction cases compare outputs and
final RNG words to the original instructions: 2,969 new fixtures total. Swap
fixtures replace only the external owner callback's occupant exchange, whose
new destinations are not read by the search. Collision fixtures capture the
vtable type/rate at the animation-controller boundary. The source contact's
working direction (including its degenerate zero perpendicular) is handed to
the reaction branch and checked in the existing 100 contact fixtures. Source
locks, full owner state and console scheduling are outside this oracle.

Scene reconfiguration now reconciles stable UUIDs instead of constructing a new
simulation. Surviving and temporarily hidden actors retain positions, movement,
clock phases and compatible original playback; pair indices and entrance ranks
are remapped. Visitor UUIDs and cached identity-derived roles/home groups stay
stable across friend-list changes. The scene chooses one new seed at boot.
Ordinary configuration does not complete/replay the boot entrance or advance a
paused frame. Renderer configuration receives the correctly indexed preserved
poses before rebuilding rigs. Layout changes allow continuous outward movement
from newly overlapping controls instead of teleporting covered actors.

Core and native regression tests cover identity reorder/add/hide/restore,
appearance/population reconfiguration, original playback preservation, boot
continuity, source and fallback layout egress, reciprocal partners, fixed-tick
traces, automatic dancing from adjacent source nodes, and actual local FFL/body
rendering. The complete native suite passed 142 tests executed (141 passed, one
optional social screenshot skipped), before the final working-vector handoff
and stable-role follow-up; the final targeted pass passed all 40 crowd/renderer tests, followed by 16 passing focused fused-arithmetic/continuity checks.
Logs: `.qa/group-state-final-tests.log`,
`.qa/group-state-last-verification.log`, `.qa/group-state-final-arithmetic.log`, `.qa/group-state-oracle.log`.

An optimized controller-only sample over 3,600 updates measured mean/p95 times
of 0.054/0.065 ms for 60 actors, 0.178/0.213 ms for 160, and 0.234/0.284 ms for
200, using synthetic 40/12-frame clips and a ten-icon, 48-unit-wide layout.
This excludes rendering, loading, UI and network features. The benchmark
preceded the cached identity lookup and final working-vector handoff; neither
adds a search or new per-frame allocation. It is a brief local timing sample,
not a sustained whole-app energy measurement. Log:
`.qa/group-state-benchmark.log`.
