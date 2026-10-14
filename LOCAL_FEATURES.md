# Local design acceptance — 0.9

This records implemented local functionality and the remaining production validation against **Mac Plaza Production Design Document.docx**, including the subsequent request for a 3D Mii-style maker.

| Design area | Local build status |
| --- | --- |
| Native Mac app, menu bar, offline operation | Implemented; optimized Apple silicon app, macOS 15+ |
| Launcher, native picking, bundle identity and reconnection | Implemented; prior native launch checks accepted for Brave, Discord and Resolve |
| Perimeter islands, twelve per page, arrange/drop/reorder/undo/reset | Implemented; reset and undo verified through the native UI |
| Real icons and custom shortcut images | Implemented; native image import verified; portable icon persistence tested |
| 20–200 characters, six movement states, gathering and separation | Implemented in true 3D; deterministic 80-character simulation tested for 60 simulated seconds |
| 3D character selection and readable profile/posts | Implemented; mouse hit testing and keyboard profile command verified |
| Maker categories, facial transforms, colours, height/build, presets/shuffle/undo/reset | Implemented with local FFL head/face rendering after resource import; validated with original Wii U FFLResHigh.dat in 0.6 |
| Twelve saved characters, primary character and directional previews | Implemented; 360-degree turning, named pose controls and PNG portraits |
| Wii U/3DS Mii import/export | Implemented for unencrypted 96-byte store data; CRC and feature ranges tested; physical console acceptance unverified |
| Local text, author/topic, drawing and accessible description | Implemented; ink/eraser raster export and persistence tested |
| Local replies and appreciation | Implemented; native reply save verified |
| Note drafts | Implemented; composer close/reopen verified and serialization tested |
| Three bubbles, drawings, unread preference, cycling pause and collision avoidance | Implemented; geometry tested across three viewport sizes and 0/8/12 app layouts |
| Eight-second dwell and staggered replacement | Implemented as three independent slots, replaced every 2.7 seconds in turn; interaction holds cycling |
| Motion/post pause, Reduce Motion, private presentation, larger text | Implemented; native list remains available |
| Original sound, muted initially | Implemented; locally synthesized 16-second WAV loop validated; follows scene suspension |
| Atomic writes, previous snapshot, schema migration, import validation | Implemented using capped JSON snapshots instead of proposed SQLite; migration and failure paths tested |
| Interrupted-session recovery | Implemented; safe mode disables 3D, custom icons, music and bubbles |
| Window restoration and display clamping | Implemented; multiple physical displays/Spaces still need validation |
| Login item | Implemented with SMAppService; physical login and approval paths not exercised |
| Wake behavior | Manual menu-bar presentation; automatic foreground eligibility remains unvalidated |
| Distribution | Local ad-hoc signing; Developer ID/notarization/update pipeline remain release work |
| Connected features | Excluded as requested; no account, Pretendo or remote feed |

## Visual fidelity

Version 0.6 uses the actual FFL decompilation and Wii U head shader, plus the original menu body meshes, atlas and animation curves described below. The eleven-tab maker remains native SwiftUI. Versions 0.8–0.9 add recovered native animation, ordinary idle, destination search, partner eligibility/selection, paired timing and dance positioning routines. The full original crowd AI port remains incomplete; native-world geometry, routes and event dispatch are adaptations. See ORIGINAL_CROWD_PORT.md.

No Nintendo resource archive is bundled. The compatible Miitomo resource used in 0.4 is retained locally, while original Wii U FFL and Men2.pack resources retrieved from Nintendo’s public system update have now passed local rendering/data tests. GX2 support is compiled in and tested with generated textures and the real original archives. Native imports validate rendered Miis before atomically replacing resources. QR/photo creation and physical console interchange remain outside this local implementation.

## Validation boundaries

Automated checks cover local data behavior and deterministic simulation, not a full production acceptance run. Native UI tests used `--demo` data. No claim is made of an hour-long leak test, five-minute frame-time percentile run, physical sleep/battery benchmark, exhaustive VoiceOver pass or target M1 Air testing. Those checks require the corresponding hardware and user environment. The prototype’s local feature implementation is usable now; these remaining items affect production readiness.

## Performance observations

Final build observations are recorded below after measuring the optimized application with 60 characters on this Mac. Process CPU percentages can exceed 100% across multiple cores, and process memory includes graphics allocations. Short samples are not target-hardware benchmarks.

On 11 October 2026, the optimized 0.2 build on this Mac (macOS 26.6.2) with 60 characters in a 1280 × 860 logical-point window and nine demo islands showed **17.0–21.0% process CPU** and **401–404 MB process memory** in three two-second visible-window samples after the initial sample. With the window minimized, the corresponding samples showed **0.0% CPU**, **284–313 MB memory**, and fewer active threads. The minimized window was left untouched during sampling; querying its UI reactivates it in the automation environment. Raw observations are in `.qa/performance-visible.log` and `.qa/performance-minimized.log`.

Shared materials, merged stationary geometry, 256-pixel face masks and a reused portrait renderer reduced graphics overhead from the first 3D revision. These brief observations demonstrate lifecycle suspension; they do not establish ten-minute idle averages, target frame-time percentiles or battery life.

The ordinary 0.1 plaza was also opened in 0.2 and cleanly saved as schema version 2. Its three saved characters, eight bound app shortcuts and empty journal were retained. The final maker check confirmed the migrated character appears with the revised 3D proportions.

## 0.3 appearance and movement refinement

- Replaced modulo-based hair reuse with 132 explicit, stored-ID-indexed silhouette descriptions. Corrected bald ID 30 and short side-swept ID 5. Added actual maker display ordering, shaped blunt/jagged/parted fringes, rounded bobs, long backs, sculpted spikes, ponytails, twin tails, buns and receding variants. Geometry remains an original approximation of the Nintendo library.
- Rebuilt eyes around sixty descriptors for white/iris placement, upper and lower lids, slants, lashes, dots, half-lids and squints. Brows, lips and nose contours now use distinct shapes. A smaller shaded 3D wedge replaces the previous generic bulb nose. Twelve head profiles distinguish rounded, oval and square jaws.
- Added neutral, happy, surprised and speaking face states. Nearby social partners greet briefly, face each other, alternate speaking gestures and listening nods, and vary their mouth expression. These are decorative local behaviors.
- Maker grids and the saved-character library use cached headshots from the same 3D rig as the plaza. A yielding, cancellable thumbnail task lets the native UI process input while previews fill in. Native checks covered a bob’s front/side/back appearance and matching mirrored grid/live previews.
- Walking now accelerates, slows on arrival and turns at a bounded rate. Gait phase advances with distance travelled; shorter strides, knee flexion, smaller bobbing and smoothly blended joints reduce the previous marching/foot-sliding effect. Characters use obstacle routes instead of repeatedly selecting a blocked straight-line destination.
- Resting visitors have varied orientations and can form reciprocal, time-limited social pairs. They maintain separation and occasionally move to another app group. Successful app launching cues at most six nearby characters to celebrate briefly.
- Tests now total 28. Added checks for all 132 display-order IDs, corrected bald/short/twin-tail mappings, expression changes, reciprocal partners facing each other, no movement jumps during a 120-second simulation, acceleration, and bounded/expiring app reactions. Existing persistence, Mii codec, drawing, collision and rendering checks remain passing.

The local implementation contains no extracted Nintendo assets or copied SVG art. The supplied creator repository’s public feature silhouettes were used as a visual reference, and its stored-ID display ordering was cross-checked as format data. A temporary isolated reference page was served only over loopback and is not part of the app.

The 0.3 palette pass also corrects Wii U stored-color slots (including gray hair at ID 4 and blue eyes at ID 4) and favorite outfit colors. Newly created avatars start with a conventional short-haired Mii face; existing saved numeric settings are retained. Facial masks are now explicitly rasterized to 256 × 256 before animation, with tested bitmap dimensions and actual byte-cost cache accounting. Large exported portraits are not retained in the small-preview cache.

Final 0.3 short samples on this Mac, with 60 characters and eight ordinary app islands in the same 1280 × 860 logical-point window, showed **17.2–22.3% process CPU** and **365 MB process memory** while visible. Minimized samples showed **0.0% CPU** and **222–255 MB memory**. Logs are `.qa/appearance-visible.log` and `.qa/appearance-minimized.log`. Fixed bitmap face masks avoid the extra lazy raster representations observed in the earlier appearance build. These are brief local observations, not target-hardware or battery acceptance measurements. The final release compiled without warnings; the app signature, ZIP integrity and SHA-256 verification passed.

## 0.4 local FFL integration

- Actual FFL CPU model building and face-mask composition, original resource meshes/textures and upstream Wii U FFLShaderMaterial. Bundled dependencies only; no HTTP renderer or runtime download. Native controls, launcher and journal remain unchanged.
- Source-built WASM with Wii U GX2 texture deswizzling enabled. Generated R8/RG8/RGBA8 textures test the real tiler and converter. Dynamic execution is disabled. Full dependency sources and build script are included.
- Resource import validates FFL initialization and a rendered test Mii. Header/size checks and a corrupt-resource runtime test confirm existing data survives bad replacements. Imported resource files are stored separately and excluded from plaza exports.
- Maker/live preview, original hairstyle grids, saved-character portraits and directional PNG export use the same FFL pipeline. Imported Mii positions remain intact; new defaults and an explicit Console Face Layout command avoid overlap from older generic midpoint values.
- One coalesced frame at a time, 30 fps native simulation, shared geometry and expression textures, GPU-instanced body parts, independent per-instance expression materials, 256-pixel plaza masks, bounded portrait caching and release of the thumbnail renderer after three idle seconds. Existing pause/occlusion/sleep controls remain.
- 33 regression tests pass with the local Miitomo resource, including a 60-character scene, body draw-call budget and independent blinking. They include FFL front/back/wave differences, visible output, an appearance gallery, offline CSP, long nickname rendering, resource rejection and all prior local features. The packaged renderer compiles without warnings. Original Wii U resource visual QA remains pending.

The three original stock characters had midpoint values for every feature position. The native maker Console Face Layout command was applied to those stock characters and saved, keeping their original style IDs. The previous local snapshot is retained in `.qa/Before FFL Layout.json`; it is excluded from source packaging.

Final 0.4 samples with the active FFL renderer, 60 characters and eight ordinary islands in a 1280 × 860 logical-point window: the main app used **5.0–7.0% CPU / 106 MB**, WebKit content **18.1–24.3% / 242–243 MB**, and WebKit GPU **7.2–9.6% / 173 MB** in three two-second samples after the initial sample. These are separate process measurements; shared memory must not be treated as independently owned allocations. After minimization all three sampled processes reported **0.0% CPU**. Logs: `.qa/ffl-visible.log` and `.qa/ffl-minimized.log`. This is a short lifecycle check, not a sustained battery/frame-time benchmark. The optimized app signature, ZIP integrity and bundled runtime/source parity were checked.


## 0.5 body, gait and interaction refinement

- Original rounded shirt geometry, narrower waist/hem, smaller hands/shoes, a smaller fixed-size FFL head above a height-dependent neck, longer legs, elbows, wrists, knees and counter-rotating ankles. The existing actual FFL head pipeline remains intact. Bodies and animations are authored locally, not original Nintendo body meshes or animation clips. Reference: Nintendo’s Wii U gallery, “Meanwhile on WaraWara Plaza” (https://www.nintendo.com/en-gb/Wii-U/Gallery/Gallery-667261.html).
- A distance-driven 0.48-unit walk cycle with 60% planted stance and a smooth raised swing. Two-link inverse kinematics, level stance soles, and a reachable pelvis height remove the old sine-wave marching and reduce foot sliding. Stature scales stride distance; viewport aspect scales depth travel. A separate gesture clock prevents idle animations from advancing footfalls. Expressive upper-body joints ease; planted leg angles use their exact contact solution. Acceleration, deceleration and obstacle routes remain.
- Conversations last 6–10 seconds, with a brief reciprocal greeting and 2.3-second speaking turns. Speaking uses bent elbows and small head motions; listening uses relaxed arms and nods. Resting visitors retain their arrived orientation and make small glances. Pairing uses closer neighbours. Selecting an unpaired visitor cues a short viewer acknowledgement. Launch reactions stagger neighbouring visitors and expire.
- The resource-free SceneKit fallback uses matching body proportions, articulated joints and the same motion equations. The active WebGL path keeps GPU instancing, shared head resources, native 30 fps snapshots, one frame in flight and no browser animation timer. All models, animation and social state stay on this Mac.
- 38 tests pass, including actual FFL ankle target checks across three statures and two builds, reciprocal speaker/listener roles and stationary conversations, distance/height/aspect gait phase, acknowledgement expiry, and all prior offline/resource/storage/launcher tests. A standalone Node check exercises 3,456 planted contacts, IK reconstruction, three statures and six poses against the shipping WebGL solver. The generated walking GIF, contact sheet and conversation view are in `.qa/`. Straight, steady stance cancellation is tested mathematically; this does not claim zero sliding during collisions, turns, starts or stops, nor frame-perfect equivalence to Nintendo’s original clips.

The optimized 0.5 FFL build with 60 characters/eight ordinary islands in a 1280 × 860 logical-point window used **5.0–6.7% CPU / 101 MB** in the main app, **18.5–22.9% / 242 MB** in WebKit content and **5.6–6.7% / 177 MB** in WebKit GPU across three two-second visible samples after the initial sample. All three reported **0.0% CPU** in the corresponding minimized samples; GPU memory fell to 25 MB. Logs are `.qa/motion-visible.log` and `.qa/motion-minimized.log`. These are brief process samples, not a sustained battery or frame-percentile benchmark; shared memory is not independently owned per process. Native UI checks covered revised bodies in the maker, FFL head picking into a visitor profile, pause/resume, and return to the animated plaza without editing saved characters.


## 0.6 original WaraWara Plaza assets

- Added a bundled local SARC/Yaz0/BFRES 3.0.0.1 reader for `Men2.pack`. It reads only `MiiBodyMiddle.szs` and `MiiAnim.szs`; no Wii U firmware or downloaded executable is run. Import validates headers, sizes, pointers, dictionary counts, mesh indices, bone palettes, finite values, key ordering and required clips, renders both genders, and only then atomically replaces the local resource. Existing resources survive a failed import. No Node/Python/Windows tool is required by the application.
- The active body path uses the original normal male/female meshes, original rigid skinning palette, original UVs/vertex lighting attributes, and the original BC3 body atlas. Native ninTexUtils handles its GX2 tiling and BC3 conversion. FFL lighting uses the atlas alpha as a cloth/pants mask. This is an adaptation of the body material rather than an emulation of the complete menu shader pipeline.
- All 172 original skeletal clips are retained as source base transforms, frames, quantization scales/offsets and cubic/linear coefficients. Playback directly evaluates these coefficients. Walking, varied idle, conversation, greeting and reaction states use original clips; no locally authored gait/limb poses are applied to the original bodies. Original poses blend at state changes and during starts/stops. Head attachment follows the original animated `head` bone; height/build scaling follows the bone-axis description. The crowd's destinations, collision avoidance and behavior timing remain Mac Plaza code.
- The public Nintendo system-menu resource content was obtained for title `0005001010040100` version 277, and original Wii U FFL resources for `0005001b10056000` version 1. Every content H0/H1/H2/H3 link and the metadata digest were checked. The original Men2.pack SHA-256 is `7f30b65316438c57bee65110fe5b7240036033bb415d4e0dbf6d8f04ee6c15ca`; original FFLResHigh.dat SHA-256 is `75381dec8c73f6cad5e74ecd6c850f202223fd6fc57ddaa02475c7f62027e7ed`. Originals/provenance stay in ignored Local Resources, and converted body data stays in Application Support. Neither is shipped in app/source archives or portable exports. No runtime download exists.
- 41 native/core tests pass with the actual original Wii U FFL resource and Men2.pack, including original body import, geometry counts, original clip selection, 60-body rendering, renderer replacement lifecycle and malformed archive rejection. The standalone parser test verifies 115,273 exact source key values across all 172 clips, both original meshes, and generated archive/curve edge cases. Original male/female, wave/walk and an original walking GIF are saved in `.qa/`. This verifies source data and local playback, not frame-for-frame equivalence to the entire Wii U menu state machine.

Native 0.6 checks activated the original Wii U heads and menu bodies in the ordinary local app, selected a visitor by clicking the original body, verified maker previews and pause/resume, and reimported Men2.pack without restarting. Outgoing renderer teardown is guarded by ownership so it cannot clear the replacement's frame callbacks or stop its timer.

With 60 characters/eight ordinary islands in a 1280 × 860 logical-point window, three two-second visible samples after the initial sample reported **5.8–7.7% CPU / 156 MB** for the main app, **15.3–20.0% / 239 MB** for WebKit content, and **6.1–8.5% / 153–154 MB** for WebKit GPU. Corresponding minimized samples reported **0.0% CPU** for all three; GPU memory fell to 20 MB. Raw logs are `.qa/original-visible.log` and `.qa/original-minimized.log`. These are brief observations, not a sustained frame-percentile or battery benchmark; shared process memory is not independently owned.

## 0.7 crowd navigation and interaction timing

- Spaced initial app-group placement, destination reservations, longer rest periods, short strolls and occasional group changes replace crowd convergence on unreserved points. Soft look-ahead yielding, stable passing direction, slower tight turns and stalled-route recovery keep movement continuous. Navigation visibility edges are cached when app layout changes. No runtime service or asset download was added.
- Original activities carry a separate time and duration through the native snapshot. Installed clip frame counts at 30 fps drive greeting entrance/loop/exit, 130-frame conversation turns, farewell bows and seated entrance/rest/stand-up. A monotonic simulation clock drives pose blending; idle time no longer starts a new gesture mid-clip. Seated Miis finish getting up before walking and are excluded from launch/selection interruptions.
- Conversation partners remain stationary and reciprocal, face each other, greet with a small stagger, alternate complete talk cycles, bow and release together. Original look-around, scratch, yawn, seated rest and brief reaction clips occur occasionally. The source meshes and skeletal keys are unchanged. These behavior probabilities and navigation rules are a recreation; the original Wii U menu behavior program has not been recovered or emulated.
- 44 tests pass with original resources. The 60-character, three-minute deterministic behavior test observed about 9.6% moving character-frames after warmup, no sampled pairs closer than 0.028 in physical normalized space, and 9 seated activities. Those observations describe this tuned simulation, not a measurement of the Wii U. Tests also cover source-driven greeting duration, whole-cycle conversation turns, paired release, bounded motion, all activity clip starts, and original entrance/loop/exit selection.

Native 0.7 checks exercised the calmer ordinary 60-character plaza, original visitor body picking, profile return, pause/resume and minimize/restore without editing character data. Three two-second visible samples after the initial sample reported 5.9–8.4% CPU / 92 MB main app, 15.2–18.2% / 241 MB WebKit content and 6.5–9.0% / 158 MB WebKit GPU. All three reported 0.0% CPU in corresponding minimized samples. Logs: `.qa/crowd-visible.log` and `.qa/crowd-minimized.log`. These brief samples are not sustained battery or frame-time benchmarks.

## 0.8 native controller port

- Recovered US menu v277 controller code from a verified local `men.rpx`, then ported animation transition/playback, ordinary idle selection/holding, and paired interaction action/timer routines to native Swift. The app runs these ports with compatible installed original body/head resources. The original executable remains research-only; no firmware loading/interpreter or new runtime service/dependency was added.
- Native crowd snapshots carry exact clip indices, source frames, previous clip/frame and original linear blend weights. Source curves and body/head assets are unchanged. Seated exits finish before movement begins. Fixed host update steps make behavior independent of 30/60 Hz delivery; paused snapshots do not accumulate renderer interpolation.
- The original paired scheduler selects talk variants, occasional complementary dances, rock-paper-scissors, outcomes, role handoffs, source-frame duration/rate and cooldown draws. Ordinary idle selection uses the original probabilities and rejected draw order rather than the 0.7 activity bag.
- Original scalar heading wrapping, capped turn smoothing and lean accumulators are ported. Walking and ordinary paired facing use the recovered heading update with host bearings. Root lean rendering, original trig lookup and speed-dependent walking cap inputs remain outstanding.
- The port is partial: navigation/collision steering, partner matching, paired dance positioning/synchronization, family arrivals and presentation remain outstanding. No full Wii U scene/clock equivalence is claimed. Native app world coordinates, controller seed, grouping inputs, app launch reactions and fixed 60 Hz update cadence are host adaptations. Full scope/provenance is in ORIGINAL_CROWD_PORT.md.

Validation: the complete 57-test suite passed with the original local FFL/Men2 resources and original-instruction fixtures, including native WebKit rendering, source clip/frame/blend checks and scheduler catch-up wrapping/clamping. The decision fixtures cover 93,901 mask/restriction/transition/idle/social/timer/heading cases plus 500 original RNG draws. The 120-second, 60-character native-host simulation exercised 50 source clips and bow/talk/RPS/outcome actions; its 30/60 Hz delivery traces matched. The parser still checks 115,273 exact source keys across all 172 clips. These are bounded verification runs, not full-console equivalence or sustained performance/battery tests. Logs: `.qa/native-port-full-tests.log`, `.qa/original-lounge-tests.log`, `.qa/native-port-final-tests.log`.

Native 0.8 checks verified the ordinary 60-character plaza, pause/resume and minimize/restore. Three two-second visible samples after the initial sample reported **6.0–8.5% CPU / 132–153 MB** for the main app, **14.2–21.0% / 268–269 MB** for WebKit content, and **6.4–8.2% / 162 MB** for WebKit GPU. All three reported **0.0% CPU** in corresponding minimized samples; GPU memory fell to 25 MB. Logs: `.qa/native-port-visible.log` and `.qa/native-port-minimized.log`. These are brief local observations, not sustained battery/frame-time acceptance. The optimized app signature and archive integrity passed; local firmware/resources/research fixtures are excluded from app and source ZIPs.


## Floating app previews and plaza soundtrack — 12 October 2026

App tiles now bob and tilt gently above fixed soft shadows, with glass rims and a pale diamond mosaic floor/recessed rings inspired by the supplied WaraWara reference. Clicking selects an app and moves the shared plaza view toward its original location and nearby Miis, with app information appearing beside them as a speech bubble. Previews show a local summary, installed bundle version/category, availability and related local journal notes. Open launches explicitly; Back, Escape and outside click return. Existing context-menu launching, shortcut editing, reordering and list controls remain available. Reduce Motion disables tile movement and background scaling.

The user-supplied Home (WaraWara Plaza) music is a bundled 68-second stereo AAC resource, sourced from https://www.youtube.com/watch?v=chgpqelL6ZQ, with provenance under Resources/Audio/SOURCE.txt. AVAudioPlayer loops offline, starts softly at 12%, and supports persistent mute/0–35% volume. Pause/hidden/minimized/sleep/list/safe mode suspend it; app previews and sheets retain it. No network player or runtime download was added.

Debug/release builds and native tests verified the update; 55 passed, five optional resource checks skipped, zero failed. Tests include soundtrack decode/duration/channels/preparation, volume bounds/migration and bundle metadata.

## 0.9 navigation, partners and dance positioning

Recovered routines now select ten accepted destination candidates with preferred squared-distance scoring, original per-obstacle clearance relaxation and central ellipse roles. Standing social pairs require both original facing/distance predicates and use the first eligible neighbor in native spatial order. The source opening draw can start with a bow or complementary talk/listen roles. Paired phase correction, 9/11-unit dance separation, phase-weighted root motion and tangent facing are active with the original skeletal clips. App reactions may start a side-by-side orbit dance through the separate original predicate/selector; automatic menu group-event dispatch remains outstanding. Source circle-overlap extrema replace summed separation pushes, with host-provided radii and neighbor lists.

The original-instruction fixtures add 1,584 partner predicates, 1,000 social starts, 1,050 dance predicates, 1,000 dance starts, 400 destination searches (including obstacle rejection), and 4,000 paired phase/root cases. Decisions and final RNG states match; dance root comparisons allow 0.000002 source units for host sqrt/normalization boundaries. The native integration test checks actual reachable dance starts and smooth root movement, and preserves 30/60 Hz delivery parity. Geometry routes, collision impulses, group dispatch, full locomotion and head-look/blink are still partial/native as detailed in ORIGINAL_CROWD_PORT.md. Runtime remains local.

All **67 tests** passed with the installed original resources (`.qa/spatial-full-tests.log`). After replacing per-frame JSON requests with structured WebKit arguments, all **20 native app/renderer tests** passed again (`.qa/spatial-bridge-tests.log`), including exact native clip/frame/blend delivery and paused pose repeatability. The frame bridge retains only one in-flight and one latest pending snapshot; its high-frequency path avoids JSON number formatting/parsing and request-deadline task creation.

Native 0.9 UI checks passed for the normal 60-character plaza with ten app controls, motion pause/resume and minimize/restore. Three two-second visible samples after the initial sample reported **15.2–20.1% CPU / 124 MB** for the main app, **16.4–22.9% / 266 MB** for WebKit content, and **6.1–7.4% / 158–159 MB** for WebKit GPU. All three reported **0.0% CPU** across the minimized samples; GPU memory fell to 25 MB. These are brief local observations, not a sustained battery/frame-time benchmark or a directly controlled comparison with 0.8. Logs: `.qa/spatial-visible.log`, `.qa/spatial-minimized.log`; preview: `.qa/Spatial Port Plaza.png`. The app signature and release archives were verified, with firmware, local resources and research fixtures excluded.


## Reference spacing and plaza zoom — 12 October 2026

The supplied reference now guides the ten-icon oval: two high central tiles, two slightly lower outer tiles, side icons, and two foreground tiles. Eleven/twelve shortcuts use an expanded staggered arrangement. Icons scale with viewport size, and both SceneKit and FFL use a 48-unit-wide orthographic view, halving the previous character size. World/source distances, original speed, footfall distance and separation remain consistent with that view. Initial visitor groups sit below each tile, with local characters near the central walkway. Window-dependent control clearances leave room for labels and projected heads. Short-window groups fall back to open walkway space. Later original-controller destinations still use the recovered source selector.

A single compact journal bubble leaves more visible plaza. Lower-left minus/percentage/plus controls provide 75–175% zoom and reset. Trackpad magnification applies the same transform to app controls and characters; enlarged views support bounded drag panning outside Arrange mode. Reset recenters the view. The floor fills the viewport at every zoom. App previews retain their separate presentation, and the zoom controls disappear while a preview is open. Zoom is local view state and does not modify saved shortcuts or characters.

The native suite passed 67 tests, with two optional instruction-fixture checks skipped, zero failures (`.qa/reference-layout-tests.log`). Actual original FFL/menu renderer checks passed. New layout checks exercise 8/10/12 shortcuts at 1060×470, 1280×580 and 1600×900, visitor clearance/distribution, and bounded zoom/panning. Native window inspection verified the revised icon/Mii proportions, plus/minus/reset controls, zoom shortcuts while WebKit has focus, and drag panning. Navigation uses a window-scoped native event monitor to handle input over either embedded renderer. Pinch input remains implemented but was not exercised by the available UI automation.


## In-plaza app focus and dedicated Mii Maker — 12 October 2026

App focus now moves the floor, app tiles and character renderer together, easing toward the selected app at 1.8–2.1×. The icon stays in its plaza location and nearby Miis continue moving. The app information appears to the right in a speech bubble, with explicit Open, notes and shortcut settings. Back/Escape/outside click returns to the previous manual zoom and pan. Reduce Motion changes focus immediately.

Mii Maker has its own corner icon and a pastel menu with Create Mii, Select Mii, file import and file/portrait options. Create opens a starting-Mii choice, then the existing full feature editor; drafts join the plaza only after Save Character. On plaza startup, saved local Miis start centrally and choose walking destinations shortly afterward. Friends and generated visitors start in app groups; only local saved Miis receive the central placement.

The maker uses the supplied https://www.youtube.com/watch?v=oTu4WcpB9Iw recording as a bundled offline AAC loop, at a separate remembered 10% volume by default. Opening and leaving the maker switches the single audio player between maker and plaza tracks, with a soft fade-in and no overlapping playback. The mute control is shared. Audio provenance is recorded in Resources/Audio/SOURCE.txt.

Validation: the native suite executed 73 tests, with six optional resource/service checks skipped and zero failures (`.qa/plaza-focus-maker-tests.log`). New checks cover focus alignment for every icon at three window sizes, central placement and early movement of saved Miis, maker AAC decoding/preparation and persisted volume validation. The optimized app built and signed successfully. Native UI inspection verified app focus with original Miis, the info bubble, Escape return, the corner entry, Create → starting Mii → editor, unsaved draft cancellation, Select → existing saved Mii, and return to the plaza.


## Wii U-style Mii editor — 12 October 2026

The editor follows the supplied Mii Maker video: eight large green tabs for face, hair, brows, eyes, nose, mouth, accessories and body, plus a portrait camera button. Feature pictograms are recreated vector paths. A larger rotatable Mii stands on the left; the right holds three-column, twelve-option pages, square two-column palettes, glossy selected tiles and a yellow adjustment rail. Eyes, eyebrows, noses and mouths now have isolated feature tiles. Installed FFL resources provide the actual part textures/geometry and colors; the built-in fallback draws only the corresponding feature. Other appearance grids retain rendered head previews.

Face includes shape/makeup/wrinkle subtabs. Accessories contain glasses, mustache, beard and mole controls; the beard has its own six-choice grid. The body page uses height/build sliders with silhouettes. Next opens Mii information, where nickname, creator, birthday and export flags are editable before Save Mii. Camera export, files, presets, shuffle/reset, saved-Mii switching, primary selection and Undo remain available. Paging clamps transient state when switching categories and opens the page containing the current feature. The existing maker soundtrack continues through the editor.

Native verification checked the eight pictograms, rendered choices, square palettes, adjustment selection, size changes and Undo, paging, accessory categories, body sliders, and the final information/Save Mii screen. The regression suite executed 81 tests with seven optional checks skipped and zero failures (`.qa/wiiu-editor-tests.log`).

## Custom music and isolated feature tiles — 12 October 2026

Preferences → Music provides separate plaza and Mii Maker file imports, remembered volume sliders and Use Default actions. Imports accept locally playable audio up to 256 MB, validate a managed copy with AVAudioPlayer, and atomically save the track selection. Invalid imports preserve the working track. Imported music survives moving/deleting its source and stays in the local Music data folder, separate from portable plaza exports. Switching tracks replaces the single looping player and retains soft fade-in, mute, safe-mode and visibility behavior.

The eye, eyebrow, nose and mouth grids now show only the individual feature. Original-resource tiles capture the actual FFL mask parts or nose geometry using the same textures and colors as the live Mii. Temporary models are disposed after each capture; the existing bounded portrait cache handles reuse. Catalog samples keep a consistent size and refresh when their feature color changes. Safe mode and the fallback renderer use isolated vector artwork. Native UI checks verified both import paths, default restoration, all four feature grids, selection and Undo.

Validation: the complete native suite executed 99 tests with the local Wii U FFL/menu resources, four optional checks skipped and zero failures (`.qa/custom-music-final-tests.log`). Focused coverage verifies playable imports, durable independent copies, invalid/oversized-file rejection, restoring defaults, transparent fallback catalogs, distinct actual FFL part captures and subsequent portrait rendering. The optimized app was built and ad-hoc signed (`.qa/custom-music-final-release.log`).

## Music audition before applying — 12 October 2026

Each Settings music row now has Preview/Stop. Choosing an import creates an unapplied local selection with Use Music and Cancel actions. Preview plays that selection once at the row’s quiet volume, pauses background playback and resumes eligible background playback after Stop or completion. Switching between plaza and maker previews replaces the active audition. Closing Settings discards unapplied selections and stops playback; hiding the window, sleeping and safe mode also stop previews.

All 19 targeted custom-music, native-boundary and desktop tests passed (`.qa/music-preview-tests.log`). New checks verify that choosing a file leaves the saved manifest unchanged, invalid selections retain a previous valid choice, applying survives deletion of the original, Cancel preserves saved music, previews never overlap background playback, and natural completion resets the Stop control. Native UI verified both Preview/Stop rows, switching between them, selecting and auditioning a file before applying, cancellation, and stopping on Settings close. The optimized app and signature were verified (`.qa/music-preview-release.log`).


## Fuller icon groups — 12 October 2026

New plazas default to 160 Miis, with a configurable 20–200 population and a Fill the plaza action for existing saves. Normal-density visitor spacing is now 0.012 of plaza width rather than 0.025; each group has a narrower horizontal and depth footprint. Four fifths of decorative visitors choose destinations near their home icon, keeping the groups populated over time. The remaining visitors roam; explicit friend activity assignments continue to take precedence. Local saved characters retain their central placement and movement. The selected population now remains unchanged in Low Power Mode (see crowd consistency below).

Model validation, simulation allocation, note target bounds and renderer capacity support 200 Miis. Authored body batches now hold 512 instances so paired limbs from 200 identical characters fit. Native tests completed with 80 passing, three optional checks skipped and zero failures (`.qa/dense-crowd-tests.log`), including actual FFL rendering of 200 identical characters, persisted population bounds, dense groups at every reference icon, and clearances across 8/10/12 shortcuts and three viewport sizes.

## Natural gatherings and launch entrance — 12 October 2026

The 160-Mii crowd now mixes loose, uneven app gatherings with roughly 35% walkway visitors. Roaming roles are mixed independently of icon order, avoiding empty groups caused by repeating index patterns. Wanderers start on open ground between gatherings and pause briefly between trips; the remaining visitors keep wider, slightly offset home groups. Resource-free collision avoidance now scales to the selected spacing so visitors can pass through the fuller crowd. Explicit friend activity assignments and saved Miis' central starting positions remain supported.

On boot, the plaza starts empty and Miis run down from above in staggered streams. Icons grow with a small overshoot and move outward into the oval in clockwise order. Installed menu resources supply the original Run00_l animation, with a short blend into idle on arrival; the native host supplies the paths and timing. The entrance plays once per process, waits for the renderer's configuration to complete, pauses with rendering, and skips to the settled plaza for Reduce Motion or Pause Motion. Notes appear after the entrance. Rebuilding the crowd or replacing a renderer does not replay it.

Entrance paths, continuous arrivals, skipping, original run-clip selection, icon timing, ongoing wandering, group coverage, renderer readiness/handoff and frozen presentation clocks are covered by regression tests. The focused native suite passed all 14 tests (`.qa/natural-plaza-native.log`); the shared full suite passed 95 tests with four optional checks skipped (`.qa/custom-music-final-tests.log`). The optimized app was built and signature-verified, and the entrance and fuller crowd were visually checked in a separate demo app.

## Recovered locomotion, collision impulses and automatic dances — 12 October 2026

The local original-resource crowd now uses recovered ordinary walking speed,
acceleration and direction smoothing, movement ramp, target smoothing and
foot-phase stopping. Clip stride no longer determines travel speed. Contacts use
the source opposition/anti-oscillation filter, perpendicular relative-motion
impulse, damping, gait projection, speed scale recovery and correction memory.
A spatial hash supplies native geometry; restricted reciprocal pairs block pushes
as in the source.

Automatic opportunities now select an actor, query directional slots, evaluate
the population-dependent source dance gate and enter the original orbit clips,
timers and root positioning without user input. Six direction masks and cyclic
random-slot search are recovered; Mac proximity supplies occupancy. Greeting
animation/watch/message handlers, complete original group topology, collision
reaction animations and run/tired/fall states remain incomplete. Native app
layout, app affinity/walkways and entrance presentation are retained.

6,668 added original-instruction comparisons pass, including final RNG states.
Four 120-second dense crowd traces exercised collision impulses while checking
finite/bounded movement, reciprocal partners and identical 30/60 Hz delivery.
A separate known eligible two-actor placement reaches automatic dancing without
click/cheer input; a chance event is not required from every random crowd trace. See ORIGINAL_CROWD_PORT.md for exact recovery
boundaries and reproducible commands. No network/runtime dependency was added.

Release controller-only timings across 3,600 ticks were 0.046 / 0.155 / 0.201 ms
mean, and 0.056 / 0.194 / 0.254 ms p95, for 60 / 160 / 200 actors. This synthetic
clip benchmark excludes WebKit/rendering and is not a whole-app or battery
measurement (`.qa/motion-benchmark.log`).

Final isolated 0.11 validation executed 106 tests: 105 passed, one optional social
visual check skipped, zero failures (`.qa/motion-snapshot-final-tests.log`). Original local
FFL/body rendering was included. The saved 160-Mii native plaza was inspected,
and pause/resume verified with motion restored. The final brief paused sample
reported 0.7% main / 0.1% content / 0.0% GPU CPU; this is not a sustained energy
measurement (`.qa/motion-paused.log`). Native preview:
`.qa/Locomotion Port Plaza.png`. App/source archives exclude firmware, installed
resource files, local saves and recovery fixtures.

## Mii Maker over the wallpaper — 12 October 2026

Opening Mii Maker from wallpaper mode now presents a centered native panel over
the existing plaza. The wallpaper renderer stays visible above desktop icons
while the panel owns input. The maker menu, editor and file import flow use this
panel, which scales to smaller screens. Back to plaza and the window close button
restore the previous desktop input mode without rebuilding the plaza. Maker music
can play while this panel is visible and the regular app window is hidden.

All 26 targeted desktop, viewport, custom-music and native-boundary checks passed
(`.qa/maker-overlay-tests.log`). Native UI verification covered the menu, existing
Mii editor, cancelling an import, Back to plaza, the close button and restored
keyboard zoom shortcuts. The optimized app and its signature were verified
(`.qa/maker-overlay-build.log`).

## Live maker background and new-Mii welcome — 12 October 2026

The wallpaper crowd keeps simulating behind a windowed Mii Maker. The panel now
supports resizing and native full screen; full screen suspends the wallpaper
until exit, while sleep, occlusion, Pause Motion, Reduce Motion and safe mode
retain their existing suspension behavior.

Saving a newly created or imported Mii closes the maker and uses that saved
character as the actor for a 6.2-second plaza welcome: drop into the center,
wave toward the camera, then pull back to the user's prior zoom and pan and
release the Mii to roam. Other Miis keep simulating during the sequence.
Full-screen confirmation exits the maker's Space before starting the welcome.
The scene waits for renderer readiness and freezes the welcome clock when hidden.
The native and FFL renderers both support the vertical drop; installed original
body resources supply the waving animation. Editing an existing Mii does not
replay the welcome. Pause Motion and Reduce Motion skip the drop and camera move.

The final 14 focused checks passed (`.qa/mii-arrival-final-tests.log`), covering
background eligibility, full-screen pause/resume, persistence, new-versus-existing
saves, readiness, paused clocks, deterministic crowd continuation, original-body
greeting selection, roaming release and camera restoration. The other 29 tests
in the broader crowd/controller, music and native-boundary run passed
(`.qa/mii-arrival-tests.log`); an arrival-test setup was corrected to give its
neighbors explicit walking destinations and passed in the final focused run.
The optimized build succeeded (`.qa/mii-arrival-build.log`). Native UI preview
verified creation, the drop, waving close-up, pullback and confirmation from
full-screen Mii Maker using an isolated demo save.

## Wallpaper soundtrack playback — 12 October 2026

Wallpaper mode no longer forces the plaza soundtrack off. The saved built-in or custom plaza track plays at its remembered volume even while the companion is hidden, the wallpaper is covered, or Finder owns desktop input. Rendering still suspends when covered. Sleep/session lock, mute, safe mode and Pause continue to stop audio. Opening Mii Maker switches to its own music, and leaving it restores the wallpaper soundtrack. The Plaza and menu-bar menus now expose Mute Music / Unmute Music. Settings and startup descriptions reflect this behavior.

All 20 focused wallpaper, audio, import/preview and native-boundary checks passed (`.qa/wallpaper-music-tests.log`), including actual AVAudioPlayer playback with hidden windows, custom music, maker switching, mute, sleep/wake and safe mode. The optimized app was built and signature-verified (`.qa/wallpaper-music-release.log`). Native inspection verified wallpaper startup, the mute menu updating the shared Settings switch, and return to the wallpaper with music enabled and the user's existing volume preserved.


## Soundtrack crossfades and automatic full-screen mute — 12 October 2026

Plaza and Mii Maker now overlap their local looping players during a 1.2-second native volume crossfade. A quick reversal reuses the still-playing outgoing track, and duplicate lifecycle updates leave the ramp intact. Retired players stop after the fade; mute, sleep, safe mode and Settings previews stop both sides immediately. Closing the feature editor clears its audio state before the maker panel disappears, preserving the return crossfade. Built-in and imported music use the same transitions and independent saved volumes.

A permission-free monitor observes workspace activation/Space changes and samples foreground window geometry every 0.75 seconds. AppKit presentation flags proved stale in the inactive wallpaper process during native QA, so detection uses window PID, layer, opacity and bounds with display/notch geometry; it never reads window titles or captures pixels. Bounded settling checks handle Space animations. Another foreground application covering a full display temporarily mutes background playback and previews, then eligible music fades back in on return. Borderless full-display windows also count; ordinary maximized windows within the menu/Dock area do not. Ordinary covered/maximized windows keep wallpaper audio playing; Mac Plaza’s own full-screen Mii Maker is excluded. The automatic condition does not change the saved Play music preference, and Settings/the menu expose the temporary mute status.

All 26 focused native audio, desktop, arrival, import/preview and boundary tests passed (`.qa/audio-transitions-tests.log`). Checks exercise actual simultaneous playback in both directions, rapid reversal without restarting, retired-player cleanup, preview/mute interruption, full-screen eligibility and return, and feature-editor closure.

Native validation used a blank external AppKit window and the exact monitor source in a separate background harness. Confirmed foreground full screen produced suppression=true, exit=false, and re-entry=true (`.qa/audio-monitor-geometry-check.log`), avoiding private browser content. The optimized app was rebuilt and signature-verified (`.qa/audio-transitions-release.log`).


## Yield music to other audio, calls and large windows — 12 October 2026

A Core Audio process-activity monitor now detects other processes’ active output and input streams, including browser audio helpers and calls. It excludes Mac Plaza’s own PID so its soundtrack and Settings previews cannot mute themselves. It polls flags on a utility task every 0.35 seconds without recording audio, opening a microphone or requesting capture permission. Music pauses immediately when activity is detected and resumes with its existing soft fade after 1.5 seconds of continuous inactivity. Unknown samples retain suppression rather than restarting during a Core Audio reset. An app retaining a silent active stream may delay resumption; call input intentionally keeps the plaza quiet during conversational pauses.

Window detection now also mutes for a foreground window covering at least 85% of the plaza screen’s usable desktop area, including maximized/Fill windows which leave the menu bar and Dock visible. Smaller windows and large windows on a different display do not trigger that rule. The existing full-screen check remains. Independent audio, window and full-screen reasons must all clear before playback resumes. Both plaza and Mii Maker, custom soundtracks and both crossfade players respect these conditions. Settings and the menu describe the current reason, interrupted previews stop without restarting, and the saved Play music switch and volumes stay unchanged.

All 31 focused automatic-music, crossfade, wallpaper, desktop, arrival, import/preview and native-boundary checks passed (`.qa/automatic-music-tests.log`). Native Core Audio coverage starts a silent external afplay process, detects its output by PID, stops it and verifies inactivity. Additional checks cover input-only calls, excluding our own audio, continuous quiet time, combined reasons, saved mute, preview interruption, large-window coverage and multiple displays.

Native window verification used a blank AppKit test window and the exact production monitor in a background harness. Filling the usable desktop produced covered=true, restoring its smaller frame produced false, and repeating both transitions confirmed the result (`.qa/automatic-music-window-check.log`). The optimized app was rebuilt (`.qa/automatic-music-release.log`) and passed deep, strict code-signature verification.

## Wii U-style speech panels and quieter posts — 12 October 2026

Journal posts and Mii friend statuses now use rounded white speech panels with soft gray outlines, short pointers, dark capsule name tabs and full Mii head portraits. Journal entries, replies and composer text areas share the panel treatment. Drawing posts remain monochrome, and clicking a plaza post still opens its journal entry or friend profile. The visual treatment follows Nintendo's WaraWara Plaza reference (`https://www.nintendo.co.jp/hardware/wiiu/miiverse/index.html`).

A shared 52-second cadence replaces the constantly visible journal card and eight-second friend rotations. After the plaza entrance, there are 12 quiet seconds, a journal post for ten seconds, 14 quiet seconds, one friend post for ten seconds, and 18 quiet seconds before the next journal post. Only one post is shown at a time. Hover and keyboard focus hold the reading interval; Pause Posts freezes it. Sheets, app previews, editing, search, list mode, hidden plazas and entrance/arrival sequences suspend elapsed time. Journal selections advance by one so a three-item list no longer repeats the same item indefinitely. Friend posts still follow their Mii and avoid launch controls.

All 27 focused cadence, native boundary, viewport and social presentation checks passed with both visual fixtures enabled (`.qa/plaza-post-tests.log`). Reviewed rendered journal and speech panel captures (`.qa/wiiu-journal.png`, `.qa/wiiu-journal-bubble.png`) and actual sample-friend plaza/status captures. The optimized app was rebuilt (`.qa/plaza-post-release.log`).

## Arrival effects and smoother camera — 12 October 2026

The welcome now lasts 7.6 seconds, with a 1.45-second camera approach and a
3.4-second pullback. Quintic easing settles with zero velocity and acceleration
at each end, and perceptual magnification interpolation softens the approach.
Camera targets follow the same native simulation ticks as the Mii and sound
cues, with transform interpolation between targets and no independent idle timer. The zoom buttons also use a softer,
slightly longer transition. The previous zoom and pan are restored exactly.

Two small bundled stereo WAVs play once at landing and at the wave after the
landing bounce. At the user's request, the synthesized cues were replaced with
original recordings from the supplied Wii U System Soundtrack playlist: the first
0.95 seconds of Startup for landing, and the first 2.8 seconds of Mii Maker Loading
for the wave. These are soundtrack excerpts, not isolated original plaza effects.
Only short boundary fades and peak normalization are applied; pitch, speed and
stereo remain intact. scripts/prepare-arrival-sounds.py reproduces the excerpts
from decoded local WAVs, and Audio/SOURCE.txt records sources and input hashes.
The existing selected soundtrack remains in use.
Effects layer over it and follow plaza volume and mute. Rendering suspension,
skipping, mute and music audition stop in-flight effects; paused or unready
renderers cannot advance their cue times. Muted cues are not queued for replay.
Pause Motion and Reduce Motion continue to skip the welcome choreography.

All 22 targeted audio-transition, wallpaper-music, custom-music, desktop and
arrival checks passed (`.qa/arrival-effects-tests.log`), including cue readiness,
pause/resume, one-shot timing, stereo decoding, unclipped/faded PCM boundaries,
independent background music, mute/audition behavior and camera continuity. The
optimized build succeeded (`.qa/arrival-effects-build.log`).

Native wallpaper preview verified the final synchronized approach, waving
close-up, return to 100% zoom and resumed roaming in an isolated demo save.

The original-recording replacement passed all three targeted native arrival-audio
checks (`.qa/original-arrival-sounds-tests.log`). Checks decode both stereo clips,
verify clean boundaries and that each ends before pullback, and exercise actual
AVAudioPlayer layering, mute, preview interruption and simulation cue timing.
The app audio resources and release archives were refreshed without replacing
the current executable.

## 0.12 crowd fidelity and placement continuity

App gatherings now use the recovered 397-node hexagonal group database,
occupancy counts, ray searches and assignment swaps. Automatic events read
source node slots. Recovered locomotion selects the original walk/run variants,
tired, fall, recovery and catch-breath clips with source thresholds, speed curves,
RNG gates and cooldowns. Standing collision reactions use the original four
surprise clips and source rate/blend calculations. Full database admission,
vacancy filling, surprise followups and the global event dispatcher remain
partial; `ORIGINAL_CROWD_PORT.md` records exact boundaries.

Miis shuffle once per boot. Appearance edits, friend refreshes, population/power
changes, and renderer replacement retain the simulation and stable identities.
Returning hidden actors recover their previous positions; roster changes remap
pairs and boot ranks. Visitor roaming roles and home groups follow identity.
Layout updates retarget movement and let covered actors walk out; they no longer
teleport a Mii to a new random destination. New-Mii arrival choreography remains
a separate intentional local presentation.

The original-instruction runner verifies 2,969 additional state/database/reaction
cases and the existing 100 contact vectors now check the direction passed to
reactions. Native FFL/body rendering and continuity regressions use the existing
local resources. The full suite passed 141 tests with one optional visual test
skipped; the final focused crowd/renderer check is recorded in
`.qa/group-state-last-verification.log`. The controller-only optimized benchmark
averaged 0.178 ms per update for 160 actors (0.213 ms p95); see the port document
for scope and timing limits. Runtime crowd logic remains local Swift.

## Home screen settings and app controls (0.12.1)

The top-right controls now show Change Apps, a Settings gear and Mii Maker in
both the window and interactive wallpaper. Change Apps enters the existing saved
layout editor, clears search and preview state, and starts on the first page.
Drag icons to reorder them, choose Add App or drop applications from Finder,
and click a shortcut to change its app, rename it or remove it. Done leaves
editing; Undo restores the previous shortcut layout. Settings also exposes
Change Apps and returns wallpaper input to the editor when selected.

Native checks cover the full mouse hit areas above WebKit, the expanded Add App
and Undo strip, and returning from Settings to wallpaper editing. Existing app
bookmark identity and Mii scene continuity checks remain passing. QA captures
are local to `.qa/Home Screen Controls.png` and `.qa/Change Apps Controls.png`.

## Speech boxes follow their Mii — 12 October 2026

The plaza journal and friend statuses now share one native overhead layer, driven
by the renderer's live head anchors. Journal posts attach to their author's UUID;
guide messages attach to the primary Mii. An absent/deleted author cannot make a
different Mii speak their post. Both FFL and fallback SceneKit positions feed the
same layer, and the existing plaza zoom/pan transform applies to speaker and box.

A message retains its selected speaker while walking, including when briefly
hidden near the top edge. Panels stay above the head, with a bottom pointer
aligned to its horizontal position. Small lateral adjustments prefer to clear
app controls. If the app artwork occupies all overhead space in a gathered group,
the panel can overlap it; it never jumps below the Mii or across the plaza. Only
one native layer subscribes to anchors, avoiding competing journal/friend owners.
The ten-second message intervals and quiet gaps remain unchanged. Native buttons
expose the full spoken text and still open the journal entry or friend profile;
drawing posts retain their accessible description.

All 21 focused speech tracking, cadence, viewport and social presentation checks
passed with visual fixtures enabled (`.qa/speech-tracking-tests.log`). Tests cover
author identity, pointer alignment, movement, window resizing, missing anchors,
speaker retention at the screen edge and actual walking-Mii renderer updates.
Sample-friend plaza captures were reviewed. The optimized app was rebuilt
(`.qa/speech-tracking-release.log`).

## Back to Plaza and live wallpaper verification (0.12.2)

Settings and app-shortcut details now have an explicit Back to Plaza button.
It closes the menu and resumes wallpaper input without resetting the current
page or app-editing mode. The top-right editing control also says Back to Plaza
and exits editing. Escape and the existing close controls remain available.

A separate QA app identity and fresh temporary directory were used to verify
Settings, Change Apps, the native Add App picker, Calculator appearing on the
wallpaper, Move Earlier and Move Later, removal, Undo, and the Back controls.
The added/rearranged shortcut survived a clean demo restart. Removal restored
the demo's eight original shortcuts, and Undo restored the exact nine-shortcut
arrangement. The demo was restored and cleanly closed. All eight files in the
user's saved plaza folder retained their original SHA-256 hashes, including
plaza.json, its backup, music data and renderer resources.

Wallpaper UI actions were exercised through native accessibility controls.
Coordinate-based automation could not target the desktop-level window, so the
drag gesture itself was not replayed; native hit-area tests still cover the HUD
surfaces over the 3D renderer. Reordering was verified through the shortcut
menu's Move Earlier / Move Later buttons and persisted app order.

`--demo --demo-directory=/absolute/path` selects an explicit isolated folder for
the demo document, music and renderer resources. The directory override is
ignored during an ordinary run. Social state stays isolated in demo mode, and
demo wallpaper changes do not persist the user's wallpaper preference. Native
regressions cover this isolation contract and menu return/input restoration.
Live verification snapshots and saved-state hashes are under `.qa/wallpaper-ui-*`
and `.qa/saved-plaza-*-wallpaper-ui.json`; native results are recorded in
`.qa/back-to-plaza-final-tests.log`.

## Speaking Mii head profile pictures — 12 October 2026

Speech boxes now give their speaker a 42-point square profile-picture tile with
an undistorted, head-only Mii portrait. The icon uses the same local FFL resource
and renderer as the plaza, preserving the current hair, skin, facial features
and accessories. Journal authors use the same head icon. Original resource
changes and Mii appearance edits refresh the picture; cached portraits avoid
rendering on every movement frame. The built-in head artwork remains available
while a portrait loads or when original resources are unavailable. Async results
are checked against the current speaker and resource key before display, so an
old portrait cannot replace a newly selected speaker's picture.

The speech tracking, social presentation and cadence suite passed 13 active
checks with one unrelated opt-in journal-design capture skipped
(`.qa/mii-head-icon-tests.log`). A further head-render check passed, verifying
distinct 128-square portraits with visible complete heads; the rendered gallery
and sample-friend speech box were visually reviewed
(`.qa/mii-head-render-tests.log`, `.qa/mii-speaking-head-icons.png`). The optimized
app was rebuilt (`.qa/mii-head-icon-release.log`).

## Wallpaper app dragging — 12 October 2026

App tiles and their labels now own native mouse surfaces above the renderer.
The controls reject background window movement, and app arrangement uses a local
mouse gesture instead of SwiftUI’s system drag session. A translucent icon follows
the pointer and the destination is outlined. Releasing over another app inserts
the shortcut in that destination slot and shifts the intervening shortcuts;
releasing over empty floor or cancelling leaves the document and Undo unchanged.
Dragging is enabled only in Change Apps. Clicks still open app details, and all
accepted reorders are saved locally and can be undone.

Seven focused regressions passed, covering native wallpaper icon/label hit areas,
the complete local drag handler against the actual desktop-level window, release
and cancellation, bidirectional ordering, page-boundary preservation, rejected
drops, Undo, persistence, and Mii continuity. Live mouse gestures in the isolated
demo verified forward and backward movement, label dragging, empty-floor
cancellation and Undo. The UI automation service cannot send coordinate gestures
to desktop-level windows (noWindowsAvailable); wallpaper verification therefore
uses the native window/gesture tests, with the shared control additionally tested
through live mouse gestures in the ordinary window. Test data uses an explicit
--demo-directory and a separate app identity. The regular app’s Miis, notes,
shortcuts, backup, and renderer resources were preserved. A pauseMotion change
made by the separately running regular app during verification was left intact.
Results: .qa/drag-local-tests.log and .qa/drag-saved-*.json.


### Restart verification — 12 October 2026

Cleanly quit the regular app, confirmed the saved document was unchanged, and
restarted Artifacts/Mac Plaza.app. The running About panel confirms version
0.13.2 (17); wallpaper mode was restored. Change Apps and Back to Plaza both
worked through native accessibility controls.

The native wallpaper drag regression now optionally copies a local saved-document
fixture into its temporary data directory. With the current 10-app, 4-avatar,
1-note save as that fixture, all seven focused tests passed. The drag test exercises
mouseDown/mouseDragged/mouseUp, forward and backward movement (including a label
start), save persistence, Undo, outside cancellation, and cancellation when
editing ends. It confirms the whole copied document is restored after Undo.
Results: .qa/restart-wallpaper-tests.log.

Physical pointer dragging on the actual wallpaper still cannot be replayed by
Computer Use: it returns noWindowsAvailable before delivering input to a desktop
level window. This is a verification limitation; the native window tests passed.
The regular app was left running on the plaza, outside Change Apps.

The real plaza.json, music configuration, and renderer assets remained byte-for-byte
unchanged. Normal clean shutdown refreshed plaza.json.backup to the current saved
document. A full before snapshot and comparison report are under
.qa/restart-verification/20261012-172821/.


## Crowd consistency — 12 October 2026

The selected population is the total crowd, including local Miis, friends and
filler visitors. A population of 60 produces exactly 60 active actors and 60
rendered rigs; Low Power Mode no longer silently reduces it to 30. Safe mode
continues to disable the 3D crowd.

Two roster-change bugs were corrected. Filler appearance was selected using its
absolute array index, so admitting a saved Mii or friend could change existing
visitors' appearances. It now follows the stable visitor ordinal. Renderer frames
previously carried only array positions, which let an in-flight old frame move
newly reordered Miis. Frames now carry identities, the roster is identified
before poses are sent, and the JavaScript renderer reuses surviving rigs and
animation state by identity. Edited or newly replaced rigs start at the previous
displayed pose; removed fallback geometry leaves its instance batches so it
cannot draw ghost limbs. Ordinary roster updates no longer clear all rigs.

Friend admission retains existing crowd members despite presence-list sorting,
while explicit Mii assignments keep their priority. Temporary friend appearances
survive short service gaps within the session; missing friends are still removed
from the displayed roster immediately and sign-out clears the cache. Replacing
one member of a full native crowd reuses the vacated position and movement state
rather than creating an actor at a random destination. New-Mii completion retains
its explicit center drop/wave choreography.

All 46 focused regression checks completed with zero failures and one opt-in
social visual review skipped (`.qa/crowd-consistency-regressions.log`). Tests cover
60 unique actors, original and fallback renderer rig retention, reversed rosters
and stale queued frames, repeated substitutions without extra instances, stable
visitor appearances, unchanged survivor positions, one minute of continuous
60-actor simulation, Low Power Mode, friend priority/refresh gaps, boot entrance,
new-Mii completion, original animation playback and wallpaper lifecycle.

Final slot-admission checks passed all seven tests in `.qa/crowd-consistency-final-tests.log`.
The optimized build succeeded (`.qa/crowd-consistency-final-build.log`).

The live Discord-connected restart also exercised a roster arriving during boot.
Replacement actors now inherit both the original entrance rank and its final
visible destination; copying only their current off-screen position could leave
late-loaded friends outside the plaza. The added 56-friend startup regression,
renderer/crowd checks and Mii completion checks passed all 12 tests
(`.qa/crowd-consistency-boot-tests.log`); the final optimized build succeeded
(`.qa/crowd-consistency-boot-build.log`).

The final installed app was restarted with the live Discord roster. The full
60-member crowd entered and settled in the plaza with motion enabled, and the
population display remained at 60. The signed app and release/source archives
were refreshed with this build.

## Natural gatherings — 13 October 2026

The crowd keeps its selected total and existing identity reconciliation. Roughly
85% of unassigned Miis now gather by icons, including saved Miis; the smaller
remaining cohort chooses open destinations between groups instead of across the
whole plaza. Each icon has a slightly different skewed oval footprint. Original
renderer targets use stable offsets derived from identity, preserving original
neighbor spacing for conversations and dances without a rigid visible grid.
Existing actors walk to new destinations; roster refreshes do not relocate them.
Explicit app affinities and the center drop/wave for newly created Miis remain.

All 30 focused optimized regression tests passed in
`.qa/natural-gathering-tests.log`, including both real WebKit body renderers,
60-member continuity, boot and arrival, original social playback, and two-minute
natural-group simulations with original and fallback controllers. The sampled
60-Mii layout kept more than 85% of position samples near icons while a minority
walked at any moment. The arrival test now verifies background movement and
individual animation clocks, allowing an idle gathering to remain stationary
through the welcome.

The optimized build completed successfully (`.qa/natural-gathering-build.log`).
The installed app was restarted and visually checked with the live 60-Mii crowd
and expanded icon layout: loose groups remained around icons and travelers kept
moving between them. Code signing and both release ZIP integrity checks passed
(`.qa/natural-gathering-package.log`).


## Background speech listener music correction — 12 October 2026

Native Settings showed automatic audio suppression despite Play music enabled, safe mode off, and the plaza volume at about 10%. Core Audio and process identity diagnostics identified macOS corespeechd (com.apple.CoreSpeech), which held both input and output streams open continuously. The activity detector now reads the owned Core Audio bundle ID property and excludes only this background speech listener. Other app output, microphone use, unknown identities, and Siri still suppress music; the existing 1.5-second quiet period and window/full-screen rules remain. No macOS speech settings are changed.

All 11 automatic music, wallpaper playback, and crossfade checks passed (.qa/corespeech-music-tests.log), including background-listener exclusion with active browser/call streams and real external afplay detection. A live read using the corrected production detector confirmed that the same CoreSpeech streams no longer suppress playback.


### Friends menu (0.13.3)

A dedicated Friends icon sits between Change Apps and Settings. The searchable roster shows Discord availability, current custom statuses, recent games/app activity and shared notes. Selecting a friend shows their Mii and allows a local library Mii assignment for friends without their own shared Mii. Assignments use the existing account-scoped persistence and retain the friend identity, status and activities; their own shared Mii takes priority. Private Presentation hides roster details.

In wallpaper mode Friends opens in the same resizable native panel shell as Mii Maker, retaining the wallpaper renderer and its simulation. Closing, Escape, or Back to plaza restores the original wallpaper input mode. Full-screen menus, explicit Pause Motion, Reduce Motion, safe mode and hidden renderers retain their existing suspension rules. Ordinary window mode presents Friends with the same sheet behavior as Mii Maker.

The requested https://www.youtube.com/watch?v=e4y-KXu6syM Friend List recording is bundled as a separate 147-second offline AAC loop. Plaza, Friends and Mii Maker crossfade over 1.2 seconds, with rapid reversal retaining playback position. Friends has its own persisted 10% default volume, shared mute, and a separate import/preview/reset row in Settings. External audio/calls and sleep continue to suspend music. Optional friends volume decodes older saved plazas without migration.

Verification includes native wallpaper hit areas and panel restoration; retained simulation eligibility; actual playback/crossfades between all three tracks; local assignment identity/status preservation; independent imported audio copies and backward-compatible volume validation.

The optimized app was rebuilt and passed deep/strict signature verification (.qa/corespeech-music-release.log). After a clean native-menu restart, Settings showed Play music on, safe mode off, enabled Preview buttons, and no automatic audio mute notice. Core Audio confirmed the restarted Mac Plaza process producing output alongside the ignored CoreSpeech listener. The plaza was left open with music at about 10%.


## Installed Steam game shortcuts — 12 October 2026

The original Add App picker only browsed application bundles, making games inside Steam’s hidden Library/Application Support folder difficult to discover. Balatro was verified installed as a native Mac app with Steam ID 2379780. Change Apps now has Add Steam Game; Settings and the File menu also open the searchable multi-select picker. It reads local Steam libraryfolders.vdf and installed app manifests across the default and additional libraries, finds native Mac game bundles, and uses each game’s own icon. No Steam account or network access is needed for discovery. Missing drives, incomplete downloads, Windows-only folders, malformed manifest targets, and missing executables are excluded.

Shortcuts retain a validated optional Steam app ID alongside the existing app identity/bookmark. Launch verifies the current installed manifest and opens a fixed numeric steam://rungameid/<id> URL with the Steam application, preserving Steam’s launch options. Regular app launch remains native. Existing manually selected Steam game bundles acquire the same identity, and older game shortcuts are recognized at launch. Game previews identify Steam games without displaying an engine version as the game’s version. Replacement retains position, custom label and icon; additions support duplicate detection and layout undo. Portable exports omit local paths/bookmarks and retain the public game ID; imported shortcuts still require reconnecting to a local application. The picker takes the plaza to the page containing the selected game.

All 23 targeted checks passed (.qa/steam-games-tests.log): discovery across libraries, quoted names, installed-state filtering, manifest/path boundaries, numeric launch targets, actual installed Balatro and its icon, persistence, old document decoding, portable export, duplicate/replacement/undo behavior, mismatched identities, normal app picking, metadata, app arrangement and core storage regressions. No game was launched by the tests.

The optimized app was rebuilt (.qa/steam-games-release.log) and passed deep/strict signature verification. Live native UI verification found Balatro in Change Apps → Add Steam Game, selected it, enabled Add to Home Screen, and added its shortcut. The resulting plaza tile and Steam game preview were verified, including Ready to open and Open Balatro; the saved document contains steamAppID 2379780. The plaza was left open with the new shortcut. No game was launched during verification.


## Steam game artwork and descriptions — 13 October 2026

Zoomed Steam previews now show game cover/header artwork and the public Steam store short description before launch. The native card keeps availability, Open, notes and shortcut settings outside its scrolling details area. Shorter windows use a compact artwork/title row; the full card uses a larger cover banner. Native Mac app previews retain installed metadata and local descriptions.

SteamGameDetailsStore reads existing Steam library artwork, including hashed library_header cache folders and older cache layouts. Previewing a game fetches public basic details by numeric app ID from the Steam store; only trusted Steam/CDN HTTPS image hosts are accepted, identity is checked, descriptions are converted to bounded plain text, image downloads and dimensions are bounded, and images are normalized locally. The ephemeral session sends no login credentials or cookies. Public results are cached separately from plaza exports, refreshed after seven days, and retained through outages or unavailable store entries. Concurrent lookups for a game are shared, failures back off, and switching previews cannot show another game’s details. Launch does not wait for network results.

All 11 focused Steam preview, shortcut and normal app metadata checks passed (.qa/steam-preview-tests.log), including mocked concurrent requests, cache reload without networking, stale/offline cache retention, local hashed artwork, separate game identities, HTML/entity conversion, URL/image validation, actual installed Balatro discovery and the opt-in live Steam preview. Full and compact native card captures were reviewed at .qa/steam-preview-fixture/balatro-preview-510.png and balatro-preview-340.png. No game was launched by these checks.

The optimized app was rebuilt (.qa/steam-preview-release.log) and passed deep/strict signature verification. After a clean native-menu restart, the live Balatro zoom preview showed its cover art, Steam store description, attribution, Ready to open and Open Balatro. The full plaza view was visually checked with the enlarged icon and gathered Miis beside the information card. The preview was left open for inspection; no game was launched.


## Floating Settings over the wallpaper — 13 October 2026

Settings now shares the native wallpaper overlay routing used by Mii Maker and Friends. It opens as MacPlazaDesktopSettings over the existing plaza renderer, keeping the ordinary companion window hidden and the visible crowd walking. Settings has a responsive scrollable form rather than a scaled fixed-height sheet. Back to Plaza, Escape and the panel close button restore plaza interaction; switching among Settings, Mii Maker and Friends retains the renderer. Settings keeps the plaza soundtrack, respects automatic music suppression, and stops/discards an in-progress music audition/selection when closed. Turning wallpaper mode off still restores Settings in the ordinary app window.

All 10 focused Settings overlay, desktop lifecycle, Friends/Mii Maker switching, wallpaper audio and custom music checks passed (.qa/settings-overlay-tests.log). Coverage includes retaining the renderer, input ownership, normal-window suppression, close/return behavior, preview cleanup, passive desktop state, and leaving wallpaper mode.

The optimized app was rebuilt (.qa/settings-overlay-release.log) and passed deep/strict signature verification. Live native UI checks confirmed the Settings button and Command-comma both open the Settings dialog with MacPlazaDesktopSettings, Back to Plaza returns to MacPlazaWallpaper, the form fits the floating panel and scrolls, and music preview controls remain available when no automatic mute condition applies. Settings was left open for inspection.


## Wii U–inspired Settings categories and original music — 13 October 2026

Settings opens as a nine-category icon menu: Music & Sound, Home Screen, Screen & Startup, Miis & Motion, Friends, Mii Appearance, Data Management, System Update, and System & Recovery. Glossy white category tiles, colored feature icons, an orange wrench header, a subtle patterned background and rounded Back controls echo the original Wii U menu. Each category reveals only its existing controls; the bottom icon strip jumps between categories. Escape returns to Categories, then to the plaza. Compact layouts fit all nine tiles down to the overlay’s 640×507 minimum. Recovery sessions open directly to recovery options. All prior control bindings remain available. Leaving Music & Sound stops previews and discards unapplied imports.

Settings now selects its own system-settings soundtrack, with a saved optional settingsMusicVolume (10% default, validated 0–35%). The requested video was verified in the browser as “11. System Settings | Wii U System Soundtrack” by LuisFerLCC 2. YouTube direct retrieval was blocked, so the original 117.984-second System Settings (TV) recording was obtained from the archive explicitly credited in that video, then converted to stereo AAC with original pitch/speed. Source URLs and the original MP3 checksum are recorded in Resources/Audio/SOURCE.txt.

Music & Sound includes separate Settings Import, Preview/Stop, Use Music/Cancel, volume and Use Default controls alongside Plaza, Mii Maker and Friends. Existing independent imports, persistence, smooth crossfades, other-audio/call/window suppression, saved mute, sleep and safe mode policies apply. Settings refreshes audio on appearance and volume change. Closing Settings returns to the plaza soundtrack.

All 25 focused Settings, audio transition, suppression, custom music, wallpaper, desktop and Friends checks passed (.qa/settings-categories-music-tests.log). New checks decode the actual bundled recording, verify legacy defaults and volume bounds, stage/apply/persist an independent replacement, preview/restore it, exercise Settings crossfades and automatic suppression, and preserve saved mute. Opt-in native captures cover the category grid at full/minimum size, Music & Sound, Screen & Startup and Recovery (.qa/settings-categories/). Browsing the captured categories leaves the saved document unchanged.

The optimized app was rebuilt (.qa/settings-categories-music-release.log), includes the Settings recording, and passed deep/strict signature verification. Live native UI checks confirmed MacPlazaDesktopSettings presents the nine category buttons and a separate Miis & Motion page with the bottom category strip. Native UI inspection intermittently timed out after restart, but the running app later reconnected and the categories were verified. Active external output/input streams were present during final audio inspection, so the app correctly remained automatically muted under the existing policy. Full music controls and replacement behavior were verified by the native capture and playback/import tests above.


## Wii U–style plaza floor — 13 October 2026

Replaced the oversized diamond mosaic and eight decorative ground rings with a continuous fine white-and-gray checker plane. Perspective makes the tiles smaller and flatter toward a bright white horizon, following the original WaraWara Plaza reference at https://www.nintendo.co.jp/hardware/wiiu/miiverse/img/img_warawara.jpg. The floor is a shared native Canvas backdrop for both character renderers, retaining the existing camera coordinates and enlarged background coverage. Mii and app shadows remain.

Standalone native captures at 1280×720 and 1512×982, plus 75% and 210% zoom, are saved in .qa/plaza-floor/. Normal, zoomed and zoomed-out captures were visually reviewed for continuous coverage, checker scale, horizon fade and removal of decorative rings. This is a visual-only change; no functional tests were added.


### Rotating home screen (0.14.0)

Settings → Home Screen includes a persistent, optional “Rotate home screen at startup” toggle (rotation defaults on when no explicit choice is saved; explicit off remains pinned), plus Shuffle Home Screen Now. A balanced page alternates randomly chosen recent apps and current installed Discord games, deduplicates bundle/Steam identities, fills spare slots from installed pins and avoids repeating the previous icon order when at least two choices exist. Selection is capped at 12; recent candidates come from the latest 24 validated local entries. No periodic icon shuffle interrupts the user. A late-arriving first Discord game roster can complete the startup mix, deferred while editing, previewing, launching or in unrelated menus.

A bounded installed-app scan covers /Applications, /System/Applications, ~/Applications and native Mac games in local Steam libraries. Launch identities and bookmarks are validated locally. Discord supplies only match metadata, never launch URLs or filesystem paths. Missing/ambiguous apps and inactive, stale or offline game observations are omitted. Generated shortcuts receive stable identity-derived UUIDs; saved pin UUIDs/custom labels/artwork take precedence. Normal app previews, launching, notes, friend gatherings, wallpaper and accessible list views consume the same displayed layout. Generated previews offer Pin to saved layout. Edit Pins shows the original saved layout without overwriting it with generated apps.

Recent-app metadata lives separately in recent-apps.json under Application Support/MacPlaza. macOS app-launch notifications and successful Plaza launches are recorded only while rotation is enabled. Currently running regular apps seed the first mix, ordered by their launch dates. History retains at most 60 identities and expires entries after 90 days. It is absent from shareable exports and is never uploaded. Previous selection keys persist locally so subsequent boots vary even with unchanged input. Apps launched while Plaza is quit are observable only if still running on the next start.

Focused tests cover balanced selection, fallback/empty pools, duplicate and Steam identities, stale/ambiguous/uninstalled Discord games, stable local history, backwards compatibility, defer-while-previewing behavior, restoring/editing pins and removal of uninstalled shortcuts. Existing native app reorder, crowd continuity, boundary and wallpaper regression checks are included.

The optimized app rebuilt successfully in 33.21 seconds (.qa/plaza-floor-release.log) and passed deep/strict signature verification. After a clean native-menu restart, the live wallpaper plaza was visually checked: the fine checker floor fills the viewport, fades toward the horizon, and has no decorative ground rings. The plaza was left open at 100% zoom.


## Custom Mii library capacity — 13 October 2026

Raised the saved custom Mii limit from 12 to 100. A shared PlazaDocument constant
now drives document validation, the maker counter, creation/import availability,
and the editor save guard. The library remains scrollable and existing Miis can
still be edited at capacity. No save schema migration or saved-data changes are
needed.

All 16 focused core/library tests passed, including a 100-Mii document round trip
through JSON and disk storage, creation of the 100th Mii, editing at capacity,
and rejection of a 101st without modifying the full library.
Results: .qa/mii-library-100-tests.log.

The optimized local app was rebuilt, signed, and restarted. Native UI verification
confirmed “Mii Maker 5 / 100 Miis”, with Create and Import available. Returned to
the wallpaper plaza; the real saved document remained unchanged.


## Friend-shared journal — 13 October 2026

Public text/drawing notes and their author Miis now sync through the authenticated
Plaza service. Game topics carry Steam App IDs or Mac bundle IDs, matching across
shortcut UUIDs, renamed labels, and rotating home-screen slots. Plaza posts need
no game match. Friend posts enter the home-screen speech rotation, author Miis
gather beneath matching visible games, and shared notes are readable in app
previews and the journal. Received posts are read-only; private notes, replies,
drafts, paths and bookmarks stay local. Public-note recipients sync independently
of private profile/presence/activity settings. Blocks, hidden friends, revoked
and expired grants are honored. Edits, deletion and switching back to private
use serialized atomic replacements, retried on the normal 15-second service poll.

The owner explicitly requested migrating this Mac’s existing notes: two notes
were marked public, with a full pre-migration plaza and service backup under
.qa/shared-notes-migration. Other plaza content was preserved. Live verification
confirmed two service publications and 225 authorized friend grants; the existing
private profile, presence and activity settings remained off. Native UI showed
both notes as Public and confirmed successful synchronization. Other users’ old
private journals retain their visibility until they choose to publish.

All 38 service tests passed, including authenticated HTTP exchange between two
accounts, large drawings, independent journal audiences, stable scoped IDs,
validation rollback, edits/deletion, blocks/revocation and unrelated endpoint
regressions. The focused Swift suite executed 28 tests with no failures and one
optional live speech fixture skipped. Logs: .qa/shared-notes-server-tests.log,
.qa/shared-notes-final-tests.log.


Rotation is the default. Existing explicit pinned-mode choices remain respected; a missing preference uses rotation. The current user plaza has rotation enabled in Settings.


## Shared replies and likes — 13 October 2026

Public notes now expose shared likes and Mii-authored text replies in the journal
and matching game previews. Likes are idempotent per-account settings. Reply
creation/retry/editing reuses a stable UUID; only its author can edit it. Both
the reply author and note owner can delete it. Public-note edits/republication
now preserve existing interaction rows; retraction cascades them. Friend grants
and blocks are checked for every write/read. Existing local replies and private
appreciation stay local. Replies require a connection; failed sends retain text.

The service stores shared interactions in new indexed SQLite tables and keeps the
legacy note feed compatible. The new thread feed includes own-note interaction
metadata without duplicating notes in the local journal. Ordered snapshot reads
prevent a late earlier poll from replacing newer interaction state.

All 46 service tests passed, including HTTP actions, simultaneous likes, replay,
reply ownership/moderation, revocation, limits, account deletion and service
restart persistence. The focused Swift suite ran 13 tests with no failures and
one optional live tracking fixture skipped. Backups are under
.qa/shared-interactions-migration; logs are .qa/shared-interactions-*-tests.log.


### Longer main plaza soundtrack — 13 October 2026

The user-selected https://www.youtube.com/watch?v=j0stAz4wrxk recording replaces the short main theme. The full 1840.807-second stereo AAC (44.1 kHz) is bundled at Audio/warawara-home.m4a, preserving its original duration and quality without re-encoding. The Settings title is Wii U Home Menu · Extended. The existing loop, remembered volume/mute, 1.2-second menu crossfades and automatic suppression continue to apply. Mii Maker, Friends and Settings keep their separate music. Provenance and SHA-256 are recorded in Audio/SOURCE.txt. The native audio decode check now verifies the longer duration.


### Resume the main theme after menus — 13 October 2026

PlazaAudio retains the main theme’s playhead after its outgoing 1.2-second fade releases the player. Returning from Friends, Settings, Mii Maker or note writing resumes the same recording at that position with the existing fade-in. The playhead pauses while the menu is open instead of advancing silently. Quick reversals still reuse the active outgoing player. Audio/call/mute/preview interruption during a fade retains the position before stopping its player. Resume state is local to the running session and scoped to the selected source URL; replacing a track starts the new recording from the beginning.

Native playback regressions wait beyond each complete fade and verify resumption after every requested menu, paused time during menu visits, interrupted fades and a fresh start for a replacement recording. Existing custom imports, previews, mute, wallpaper and Settings music checks are included.


## Activity badge, writing shortcut and soundtrack — 13 October 2026

A native hit surface now hosts bottom-right Activity and Write Note controls.
Activity has a live unread badge, an inbox with note navigation and explicit read
actions, a short in-plaza alert and optional UserNotifications banners/Dock badge.
No notification permission is requested until Enable macOS notifications is
chosen. The service stores read flags; account-scoped preferences store delivery
cursors, with no migration or changes to plaza.json. Initial history is quiet;
new activity does not replay on polling/relaunch. Blocks, revoked grants,
withdrawals, self-interactions and duplicate retries are handled by the service.
Polling continues for activity while hidden and pauses while sleeping/locked.

Writing notes or replies uses the supplied 146.84-second Wii U Chat – Main Menu
AAC recording locally, with 1.2-second crossfades and a separate default 10%
volume. Import/preview/volume controls are available in Music settings. The local
recording is excluded from distributable packages alongside other optional
recordings; portable plaza exports contain no audio.

All 51 service tests passed. Focused activity/writing/native wallpaper/continuity
tests passed (10 tests), along with the 18-test music/shared-note regression run.
Checks include ID ownership, read races, event limits, restart persistence,
notification delivery cursors, native hit areas and writing music without saved
document changes. Logs: .qa/activity-*-tests.log. Backups: .qa/activity-migration.

Write Note and Activity now share the native wallpaper panel shell with Settings,
Friends and Mii Maker. Their close controls return input to the existing wallpaper
without replacing its renderer or resetting its crowd. Windowed panels keep
motion active; full-screen panels respect the existing visibility and pause rules.
An untouched composer no longer writes empty draft metadata or replaces a draft
for another topic; meaningful draft edits and intentional clearing still save.
Verified by native panel and save-preservation regressions.

## Miiverse communities and local soundtrack — 14 October 2026

Miiverse opens from a native button directly above Write Note. It shares the
floating wallpaper panel shell and reuses the journal’s drawing, like, reply,
edit and undo controls. A read-only catalog groups all authorized shared notes
and local private/public notes by portable app identity, preserving topic labels
for uninstalled apps and deduplicating local notes against their shared copies.
All Notes, My Notes, Friends’ Notes and The Plaza sections accompany app
communities. Search includes app labels, note text, author and drawing
descriptions; newest, oldest and most-liked sorting are available. Private notes
remain local; this feature changes no sharing permissions or service routes.

Miiverse music uses the user-supplied 109-second Wii U Miiverse – Loading AAC
recording, stored locally at Audio/miiverse.m4a. Independent volume defaults to
10%, is adjustable in the window, and has the existing Settings import/preview
controls. Nested writing transitions return to Miiverse music; leaving the window
resumes the main theme. The optional volume field preserves old saves, validates
0–35%, and records a value only on explicit adjustment. Distributions omit the
recording. Catalog tests cover unmatched communities, portable identity, own
shared-copy deduplication, filtering, searching, sorting and removed apps. Native
checks cover button hit areas, floating panels, save preservation, offline audio
decode and crossfades. Logs: .qa/miiverse-*-tests.log.


### Discord call-end / music import investigation — 14 October 2026

Reported: a friend on the latest Mac release (download manifest currently 0.17.0) sees a complete quit after leaving a Discord call and problems importing the developer’s music recordings. The friend’s crash report and macOS version have not been provided. The local retired crash reports predate this report and concern QA/startup issues; they do not establish its cause. No real Discord-call crash has been reproduced locally.

Confirmed import defect: validatedCopy used AVAudioPlayer.prepareToPlay as a file-validity check. Preparation acquires playback hardware, so output-route/hardware failure can reject a valid recording. A restricted-output probe reproduced prepareToPlay=false for the valid 1840.807-second theme. MusicFileValidation now parses the audio container/format and reads its first encoded audio packet through AudioFile APIs without opening an output stream. All five user-selected M4A recordings validate in the same restricted environment. This verifies container/packet readability rather than decoding an entire file or guaranteeing future hardware availability. Invalid imports still preserve the existing track, and staged selections for Settings and Writing are now cleared with the other roles.

Confirmed recovery weaknesses, with crash relevance unconfirmed: Core Audio input/output property failures were substituted with false (silence), allowing an incomplete snapshot to start the quiet countdown. Process disappearance/read failures now produce an unknown snapshot, retaining suppression until complete quiet samples arrive. Process-list size/alignment and scalar result sizes are checked. The SDK header explicitly requires releasing kAudioProcessPropertyBundleID’s returned CFObject, so its existing takeRetainedValue is correct and was retained.

Candidate call-end mitigation: other-app audio activity now releases old playback queues while suppressed. After the quiet interval, playback creates a fresh player on the current system route and restores the main playhead (and the interrupted menu’s position). This avoids reusing the pre-call AVAudioPlayer after a possible Bluetooth/USB route change. Playback failures log the role and have up to three delayed retries; mute, previews and further activity cancel retry. Process-monitor and playback events use the local.macplaza.audio OSLog subsystem, without logging friend identities, tokens or music filenames. These changes are not a confirmed fix for the friend’s complete quit until their faulting thread is inspected.

Validation: 28 focused native audio/menu checks passed, including missing call-process properties, eight repeated simulated call suppression/resume cycles with imported audio, saved mute, real external afplay process start/stop, menu crossfades, main-theme position, imports and preview cleanup. No live Discord call or physical Bluetooth-route transition was initiated during testing. Production compilation is checked locally; no installer or public update was published by this investigation.


## Tester diagnostics export — 14 October 2026

Settings → System & Recovery now includes Export Diagnostics… with a native ZIP save dialog, progress indicator, completion/error text and Finder reveal. Export runs off the main thread and does not upload anything. It includes a build/macOS/architecture and renderer/recovery summary, a Read Me with reproduction instructions, and up to ten matching Mac Plaza IPS/legacy crash reports from the last 30 days. Both user and system DiagnosticReports directories are considered; unreadable folders are recorded without preventing the summary export. Symlinks, unrelated/mismatched reports, malformed content, old reports and oversized files are skipped. Reads are capped at 5 MB each and report content at 20 MB. Original reports are unchanged; the current user's home path is replaced with ~ in exported copies. Reports can retain other paths and system details, as explained beside the button and in the ZIP.

The exporter never reads the saved plaza document, Miis, journal entries, Discord credentials, custom music or general system logs. A no-crash export still provides the system summary. A temporary private staging directory is removed after either success or failure, and the ZIP destination is replaced atomically.

All three focused diagnostics checks passed (.qa/diagnostics-tests.log), exercising real ZIP creation/extraction, recent/current and legacy report selection, other-app/malformed/old/symlink exclusion, home-path replacement, original-file preservation, bounded report count/bytes, no-report export, and failure preservation.

The optimized app rebuilt successfully in 22.90 seconds (.qa/diagnostics-release.log) and passed deep/strict signature verification. Live native verification opened the floating Settings → System & Recovery panel, found Export Diagnostics, saved .qa/diagnostics-live.zip through the native dialog, and confirmed the success message and readable layout. The ZIP was independently inspected for the expected Summary.json, Read Me.txt and crash-report folder; this Mac currently yielded zero matching recent reports, so the no-report export was verified end to end. Settings was left on System & Recovery.


## Tester descriptions in diagnostics ZIPs — 14 October 2026

The Export Diagnostics save dialog now includes an optional multiline “What were you doing before the crash?” editor, reproduction prompts and a visible 10,000-character counter/limit. The in-memory draft survives cancelling the save dialog or an export failure, and clears after success. The immutable description captured at Save is exported as UTF-8 Tester Notes.txt, preserving internal line breaks and Unicode; blank descriptions produce “No description provided.” The Read Me identifies the notes file. No description is saved into plaza data or uploaded automatically. The exporter independently rejects an over-limit description before replacing any existing destination.

All four focused export checks passed (.qa/diagnostics-description-tests.log), including multiline Unicode/emoji in an extracted ZIP, blank notes, over-limit rejection preserving an existing ZIP, and the previous crash selection, limits, privacy and failure coverage.

The description accessory uses a native AppKit text view inside the modal save panel, with explicit text-container/minimum editing-area sizing. Settings and the archive Read Me now show alexanderhosier@squidproductions.org. After successful export, Email Diagnostics… uses the macOS compose-email sharing service to open a reviewable draft with the ZIP attached and that recipient set. If email sharing is unavailable, the panel explains how to attach/send the ZIP manually. No email is sent automatically.

The final optimized app rebuilt in 22.62 seconds (.qa/diagnostics-description-release.log) and passed deep/strict signature verification. Live native verification entered multiline text with Unicode/emoji, observed the 141-character counter, cancelled and reopened the panel to confirm draft retention, then exported .qa/diagnostics-description-live.zip. Independent ZIP inspection confirmed the exact Tester Notes.txt text and support email in Read Me.txt. Settings showed the Email Diagnostics button and recipient link. Clicking Email Diagnostics opened a Mail draft titled Mac Plaza diagnostics with alexanderhosier@squidproductions.org as recipient and diagnostics-description-live.zip attached. The QA draft was closed with Don't Save; nothing was sent.


## Diagnostics offer after interrupted startup — 14 October 2026

The existing unfinished-session marker now queues a native one-time startup offer: “Mac Plaza didn’t close normally,” with Export Diagnostics… and Not Now. The explanation covers crashes, forced quits and power loss, retains safe mode, identifies the report email address and points to Settings for later export. Choosing Export opens System & Recovery and the existing description/save flow, with Email Diagnostics available after success. Not Now dismisses without exporting, sending or changing safe mode. The marker still clears through the existing clean-termination path. The exported system summary records previousSessionInterrupted.

The offer waits for a connected window and for existing startup errors/sheets to clear, then activates the recovery window so wallpaper/login starts cannot hide it. First-launch Discord setup is deferred on an interrupted launch. Window attachment, startup completion and sheet dismissal all retry the pending offer; consuming it before presentation prevents duplicate prompts during view/window updates.

All eight focused crash startup, storage-marker and diagnostics export checks passed (.qa/crash-diagnostics-tests.log), including clean first/relaunches, an interrupted startup entering safe mode, deferral without a window, safe mode surviving a clean relaunch without a false crash offer, corrupt-data error/original-file preservation, and previous export coverage.

The final optimized app rebuilt in 22.77 seconds (.qa/crash-diagnostics-release.log) and passed deep/strict signature verification. A separate demo bundle and data folder simulated unfinished sessions without changing the user's saved plaza. Native checks confirmed the startup alert, Not Now dismissal retaining safe mode, clean quit clearing the marker, and a clean relaunch without another offer. Export Diagnostics then opened the actual description/save dialog; .qa/crash-startup-live.zip was saved and independently inspected for previousSessionInterrupted=true, safeMode=true and the exact tester note. System & Recovery appeared after the save dialog with the email button/address and success message. The presentation order was corrected so a Settings sheet transition cannot cancel the save dialog. The isolated QA app quit cleanly after the successful final run. All eight focused checks passed again after that correction.

The main app was restarted cleanly with the updated release and returned to wallpaper mode without a recovery prompt. The isolated test bundle was moved to .qa/Crash Diagnostics QA.fixture after testing so it is no longer available as a rotating home-screen app. No real crash was induced and no diagnostics email was sent.

## Bundled Miiverse music for private friends — 14 October 2026

The private 0.18.1 app download includes the exact requested Miiverse AAC so
friends hear it offline without importing a file. A specific private-build flag
retains only miiverse.m4a; other local recordings and source-archive audio remain
excluded. Packaging can use a separate app output path, leaving the running app,
its recordings and saved plaza untouched. Existing volume, mute and custom
recording precedence are unchanged. Artifact verification checks the exact
recording hash, native audio decode, archive signature, authenticated downloads
and saved-plaza preservation.

## Linked Discord names and primary public Miis — 14 October 2026

Public note/reply identity now comes from the authenticated service account, with
a full displayName separate from the 24-character Mii nickname. Existing stored
payloads receive a read-only identity projection, preserving note IDs, replies,
likes and visibility flags. New clients publish their sanitized primary Mii via
the notes batch; its appearance is retained only while public notes remain.
Primary changes update existing shared appearances. Account-scoped avatar IDs
and Discord identity merge note authors with their temporary visitors instead
of adding a second walker. Status and activity remain intact. Private notes and
saved Mii nicknames are unchanged. Notes, previews, Miiverse search, replies,
activity messages and speech posts use the linked name; public composers identify
the primary Mii and Discord name explicitly.

All 54 service and 39 focused native/core checks passed, covering legacy naming,
long names, primary changes, atomic invalid batches, retraction, spoofed name
rejection, visitor merging and private-note preservation. Logs are in
.qa/public-identity-*-tests.log; pre-deployment backups in
.qa/public-identity-migration.


## Audio resource crash fix — 0.19.1, 14 October 2026

Eight tester crash reports across 0.16–0.19 showed the same SwiftPM resource-bundle assertion while starting/resuming audio. PlazaResources replaces the fatal Bundle.module fallback with optional lookups confined to the installed app, while development/tests can use adjacent resource bundles. Missing recordings use synthesized playback; absent arrival effects are skipped. Renderer assets use the same safe resolver. Custom music, muting and crossfades are preserved. Build 28 is a focused hotfix above 0.19.0.
