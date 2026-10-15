# Decisions

Defaults chosen where `GAME_DESIGN.md` left room, plus engine-specific findings.
Newest phase at the bottom of each section is fine; just keep the reasoning.

## Engine and project

- **Godot 4.4.1 (standard build).** That's what is installed (with export templates) on the
  build server. The project opens in any newer 4.x editor.
- **Compatibility renderer** for desktop and mobile (`gl_compatibility`). Nothing uses Forward+ features.
- **Physics interpolation is on** (60 Hz physics, smooth rendering on 90/120 Hz phones). The camera
  runs in `_process` using the car's interpolated transform. Anything teleported (pooled chunks,
  respawns) calls `reset_physics_interpolation()`.
  - Engine finding: in 4.4, MultiMesh instances placed on an *interpolated* MultiMeshInstance3D
    never appeared in the web build. Tree MultiMeshes opt out (`physics_interpolation_mode = OFF`);
    they never move while visible anyway.
- **Folder layout** follows the suggested structure, plus `core/` for engine-agnostic helpers
  (`MeshKit`, `Materials`, `UiTheme`), `tools/` for build/test scripts, and `tests/`.
  The camera is a script on a `Camera3D` inside `Race.tscn` rather than a separate `RaceCamera.tscn`.
- **Collision layers:** 1 = player, 2 = traffic (reserved; traffic collides analytically, see
  Phase 2), 3 = obstacles.
- **Tests:** a tiny headless runner (`tests/run_tests.gd`) instead of a plugin like GUT, so there's
  nothing to install. Run `tools/run_tests.sh`.

## Road

- **Road coordinates:** everything can be expressed as `s` (meters along the road) and `d` (meters
  right of the median centerline). `RoadManager.sample()/project()/yaw_at()` convert to and from world
  space. Traffic, cones and speed traps (later phases) will live in `(s, d)`, which keeps AI cheap.
- **Right-hand traffic.** The player's carriageway is right of the median (`d > 0`); the oncoming
  carriageway is mirrored. **Lane 0 is the fast lane** next to the median, so "LEFT 2 LANES CLOSED"
  maps directly to lanes 0-1.
- **3 lanes per direction for now** (spec allows 3-4). `RoadSpec.LANES` is one constant; 4-lane
  stretches near Austin/Dallas will arrive with the lane add/drop tapers in Phase 3.
- **Flat road** (no hills). Gentle curves are 7 degrees over a 120 m chunk (~980 m radius). The
  road's heading is steered back toward its original direction, so it wanders but never turns around.
- **Chunks are 120 m** (a multiple of the 12 m US lane-dash period, so paint lines continue
  seamlessly). Chunk meshes are generated in code and cached per shape; chunks are pooled.
- **Phase 1 chunk mix** is random-weighted (straight 4, left 2, right 2, overpass 1; no back-to-back
  overpasses; the first 240 m is straight). Levels will supply authored sequences/weights in Phase 6.
- **Boundaries:** the median barrier and a ranch fence 30 m out are enforced analytically in road
  coordinates (exact on curves, no tunneling, no physics cost). Physics collisions are used only for
  fixed objects (overpass piers, the finish gantry's outer post; Jersey barriers later).
- **The grass between the shoulder and the fence is drivable** (slow), which the SUV's
  "Shoulder Surfer" trait needs.

## Driving

- **Arcade controller on `CharacterBody3D`**, not `VehicleBody3D` (wheel-suspension simulation is
  twitchy on touchscreens and hard to tune for "arcade").
- **Steering assist:** when steering is released, the car eases back in line with the road
  (`PlayerCar.steer_assist`, 0 disables it). This makes tap-to-steer on phones comfortable. Could become
  a setting in Phase 7.
- **Digital input smoothing:** keys and touch buttons ramp steering in ~0.2 s, so a tap is a lane
  nudge, not a full-lock swerve.
- **Holding brake at a standstill reverses** (capped at ~20 mph).
- **Real-world scale and speeds.** SUV tops out at 105 mph. Corridor distances get compressed per level
  in Phase 6, not by shrinking the world.

## Look

- **Flat shading via one shader** (`assets/shaders/flat.gdshader`): face normals come from screen-space
  derivatives, so code-built and imported meshes both get crisp facets. Code-built meshes use vertex
  colors with a single shared material (one draw call per mesh).
  - Engine finding: Godot already converts vertex colors from sRGB to linear. Pass palette colors as-is.
  - Derivative normals are flipped to face the camera, because sign conventions differ across GL backends.
- **Linear tonemapping and calibrated light**, so on-screen colors land close to the palette values.
- **The sun comes from the west, straight across the road**: a low evening sun over a
  north-south interstate. It also lines long shadow edges (barriers, cars) up with the shadow-map
  grid, which keeps them crisp instead of stair-stepped.
- **Palette lives in `autoload/Palette.gd`**; the sky/fog/sun (`Atmosphere.gd`), ground shader and UI
  theme (`UiTheme.gd`) all read from it. The one exception is the white/black speed-limit sign style in
  `HUD.tscn`, which is a real-world sign.
- **Font:** Nunito (rounded sans-serif, SIL Open Font License, license file next to the font).

## UI and input

- **Touch controls appear automatically** on touchscreens (or on the first touch). On desktop press
  **T** to toggle them and test with a mouse. Each finger is tracked separately; sliding a thumb between
  the steering buttons switches direction without lifting.
- **The PROP button** shows the equipped prop and its cooldown ring (Phase 5); it's hidden for the
  passive Radar Detector.
- **Speedometer placement:** bottom-right on desktop as specced; on touch screens it moves to the
  top-left, because the bottom corners belong to the thumbs and the car sits bottom-center.
- **Pause:** Esc / P / gamepad Start / on-screen button. The game also auto-pauses when the app or
  browser tab loses focus.
- **FPS readout** is shown during development for performance testing. It moves behind a settings
  toggle in Phase 7.
- **Gamepad:** left stick or d-pad to steer, RT gas, LT brake, A prop, Start pause.

## Web build and hosting

- **Web export without threads** (`variant/thread_support=false`), no PWA, so it runs on any static
  host without cross-origin isolation headers.
- **Test hosting:** `https://bigskytex.cloud/survive-i35/` (unlisted folder). That path gets gzip
  for `.wasm`/`.pck` (the 43 MB engine downloads as ~10 MB) and `no-cache` so new builds show up right away.

## Phase 2: traffic and timer

### Traffic
- **Everything lives in road coordinates.** Each vehicle is a rectangle in (s, d) (`Footprint`).
  Over a car's length the road is nearly straight (~1 km radius), so treating (s, d) as flat is
  accurate to ~1%. This makes lane logic, following and collisions cheap: no physics bodies, no raycasts.
- **Driving model: the Intelligent Driver Model (IDM).** It keeps a time gap to whatever is ahead
  (a car, the player, a wreck) and brakes harder the faster that gap closes, up to 9 m/s². Easing
  off for a lower *desired* speed (a slowdown or a jam) is capped at 4.5 m/s², so traffic slows
  firmly but doesn't panic-stop for no visible reason.
- **Lane changes: a simplified MOBIL.** A driver moves over when the other lane lets it go
  meaningfully faster, plus a keep-right habit (`keep_right`: semis and work trucks drift right).
  Aggressive drivers need less gain and accept tighter gaps; pickups weave, minivans don't. Some
  lane changes happen "for no reason". `signal_chance` decides who uses a blinker (pickups: 35%).
- **Nobody merges in behind something slower without room to brake for it.** The front-gap rule
  includes braking distance, because a car keeps rolling for the whole 1.5-3 s lane change
  before it can react. (Found by a browser test where traffic rear-ended a parked player; now a
  regression test over the seeds that used to fail.)
- **Lane bands.** `TrafficLanes` sorts vehicles into bands (inner shoulder, 3 lanes, outer
  shoulder + grass), each ordered along the road. "Who's ahead of me" and "is there a gap" are
  short scans, and collisions are only checked between neighbors in a band.
- **Five placeholder types** (`data/traffic/`): sedan, minivan, pickup, 18-wheeler, construction
  truck. Speeds are set relative to the posted limit (`speed_vs_limit_mph`), so traffic slows by itself
  when Phase 3's construction zones lower the limit.
- **Meme cars:** `TrafficCarData.behavior` takes a script extending `TrafficBehavior` (hooks:
  desired speed, lane preference, per-tick). `behaviors/LeftLaneCamper.gd` is the worked example,
  and there's a `TODO: meme car roster` in `TrafficSpawner.gd`.
- **Oncoming traffic** is lighter (55%), keeps its lanes and never touches the player (the median
  is in between). It's there so the highway looks alive.
- **Density** is cars per km per lane: Kickoff uses 8 in open country, ×1.6 within 350 m of a
  town, ×2.1 in a metro jam. Cars spawn 370-450 m ahead in the haze. They spawn behind only
  when the player is slow (< 54 mph), and then come up gently. At most 34 cars go your way and 16 the other.
- **Metro jams:** Austin and Dallas approaches have a 420 m jam at 42% speed that clears 380 m
  before the finish: the parking lot that suddenly opens up. A level that starts in a metro starts in its jam.
- **Phantom slowdowns:** every 20-38 s (not in jams) a slow patch appears 260-340 m ahead and
  drifts back toward you at 4.5 m/s for 24 s, slowing traffic to 25% at its heart. A popup announces it.
- **Pooling:** cars are pooled per type and hidden, not freed. A 60 s run creates about 40-55 car
  nodes in total.
- **Traffic meshes** are one body mesh per car (wheels baked in; they're too small to see spin from
  the chase camera), cached per type and paint, plus small light meshes sharing glowing materials
  (brake lights, blinkers, the work-truck beacon). Paints are muted so the player's car and the
  hazards stay the loudest things on screen. Levels can feature a paint (Kickoff: 30% burnt orange).

### Crashes
- **Collisions are rectangle overlap tests (separating axis) in road space.** Bodies are pushed
  apart in proportion to their weight and trade momentum with a little bounce (0.25) and scrape
  friction. Masses: sedan 0.85, SUV 1.0, pickup 1.3, work truck 3.5, semi 5.0.
- **Spin-out at a closing speed of 9 m/s (~20 mph) or more.** Rear-ending traffic at full speed
  spins you out; side-swipes and taps just cost speed and wobble the car. The spin lasts 1.5 s,
  turns more than a full circle, and eases the car into the lane with the least traffic bearing
  down on it, facing down the road at 13-36 mph. 1.2 s of immunity follows. The camera tracks the
  road while you spin, so the view doesn't whirl.
- **Traffic gets rattled too:** a hard hit makes a driver slide, maybe spin, put the hazards on and
  brake, then ease back into the nearest lane.

### Near misses
- Passing a car going your way counts when there's less than 1.1 m of daylight between you as you
  pass its middle, you're doing at least ~50 mph, and you're at least 4 m/s faster. It must be a
  clean pass (no contact in the last 1.5 s). Lane width leaves ~1.7 m between centered cars, so
  you have to hug the line. +0.5 s each.

### Clock, route and flow
- **3-2-1-GO countdown** with the level card (title, route, scenario). Traffic moves during the
  countdown; you don't. The clock starts at GO and runs in physics time, so pausing stops it.
- **Mile markers are approximate real I-35 mileposts** (they count up going north; Dallas uses
  I-35E numbering). Kickoff runs Round Rock (mile 252) to Austin (234). The progress strip
  and the roadside mile posts use the same numbers.
- **Finish:** an overhead green "AUSTIN / CITY LIMIT" sign on a gantry from the median to the
  grass, with a checkered line across the lanes. Crossing it stops the clock; the car brakes
  itself and the results card follows 1.6 s later.
- **Results:** time left (or miles short), near misses (and the time they earned), spin-outs and
  top speed, plus Retry. Change Loadout came with Phase 5; stars and Next Level arrive with
  Phase 6. The pause menu gained Restart.
- **Kickoff is 4.0 km for 3:00**, tuned with `tools/run_balance.sh`: an autopilot (careful lane
  keeper, rarely weaves) finishes every test seed with 7-26 s left. Players who weave and use the
  shoulder should do much better. Retune once construction and police exist.

### HUD
- **The clock lives in a slim top bar with the progress strip,** not in a big panel at top
  center. The chase camera puts the road 60-160 m ahead at the top-center of the screen, which is
  exactly what you need to read at 100 mph (and where Phase 3's lane-closure warnings will appear).
  The bar is one short row; the clock is big and turns red with a once-a-second pulse in the
  last 30 s, and shows tenths in the last 10.
- **Popups** are cream pill bubbles just above the car that float up and fade; they stack.


## Phase 5: cars and props (built before Phases 3 and 4)

- **Order changed on request.** After Phase 2 the user asked for the car and prop selection the
  spec describes, so Phase 5 came before construction (3) and police (4). The parts that need
  police are wired but idle until Phase 4: the Radar Detector's protection
  (`PropController.blocks_speed_traps()`) and its HUD beeps (`RadarDetector.threat`), the EV's
  Silent Running (`CarData.police_detection_scale`), and high-beaming a trooper.
- **Flow:** the game opens on the garage (`scenes/main/Garage.tscn`): step 1 is car and paint, step 2
  is the prop, then the race. The `GameState` autoload carries the loadout, so Retry keeps it; the
  results screen and pause menu have Change Loadout. The title screen, level select and scenario
  card are Phase 6; until then the garage shows the trip in a card at the top-right. A race started
  on its own (tests, F6 on `Race.tscn`) uses the car and prop set on the scene (SUV, no prop).
- **Garage input:** moving focus onto a card picks it, so arrows and the d-pad browse. A click or tap
  only picks; Next moves on. Enter / gamepad A on a card confirms it, Esc / B goes back.
- **Paint:** six saturated paints (`Palette.PLAYER_PAINTS`); each car's default is one of them. A
  paint you pick sticks when you switch cars.

### Cars
| | Top speed | Accel | Steer | Grip | Mass | Off-road drag |
|---|---|---|---|---|---|---|
| Truck | 108 mph | 7.0 | 1.15 | 7.0 | 2.2 | 0.6 |
| SUV | 105 mph | 9.0 | 1.5 | 8.0 | 1.0 | 0.2 |
| EV | 100 mph | 12.5 | 1.8 | 9.5 | 0.75 | 1.0 |

- **The truck has the highest top speed but takes forever to get there.** The EV is the reverse.
- **Bully (truck):** against anything lighter than the truck, the other car takes 80% of the push
  plus a sideways shove out of the lane. The truck keeps 70% less of the bump's speed change and
  counts half the closing speed toward a spin-out. Work trucks (3.5) and semis (5.0) are heavier,
  so they still win.
- **Silent Running (EV):** `police_detection_scale = 0.6`, for Phase 4's speed traps. Being the
  lightest car, the EV also gets knocked around the most.
- **Balance** (autopilot on Kickoff, 5 seeds, `CAR=... tools/run_balance.sh`): Truck 1-23 s left,
  SUV 8-25 s, EV 10-27 s. The bot avoids contact, so it never uses Bully; real truck drivers will
  shove through traffic. Truck acceleration went from 6 to 7 because a careful driver ran out of
  time on 2 of 5 seeds at 6.
- **Placeholder bodies:** `CarData.body_style` picks the shape CarModel builds: a boxy SUV, a lifted
  pickup (chrome grille, cab marker lights, open bed), or a low EV hatch (no grille, glass roof,
  light bars). `CarModel.headlights` is where the high beams shine from; real models can set it
  with HeadlightL/HeadlightR markers.

### Props
- **Data:** `PropData` (`data/props/*.tres`) plus a behavior script extending `Prop`
  (`scenes/props/`). `PropController` reads the prop button, runs the cooldown and calls the
  script. The cooldown starts when the prop fires (High Beams: on for 4 s of its 10 s cooldown).
  Props only fire while racing, in control and not spinning. If nothing happens (the gesture with
  nobody in range), no cooldown is spent.
- **Censored Gesture:** the target is the nearest car going your way, ahead or alongside, within
  15 m bumper to bumper. The driver keeps pace with you, creeps toward you for 0.45 s with the angry
  face up (horn), then lunges sideways at up to 4.5 m/s for up to 1.1 s.
  - 75%: the lunge is aimed to stop 0.8 m short. When it gets there (or time runs out, or it clips
    another car) the driver yanks back, spins and crashes out. Then 1-3 cars within 30 m go down
    too, 0.22 s apart, spinning away from you.
  - 25%: the lunge is aimed at you. Contact during the lunge spins you out (normal spin immunity
    applies) and the driver drives off. To dodge, brake (they can only slow at 9 m/s², you brake at
    18-24) or steer away. A lunge that times out counts as a miss.
  - Road Rage KOs count the driver plus the pileup.
  - The gesture is drawn as a jittering pixel mosaic under a CENSORED bar; no gesture is drawn
    underneath. The bleep, horn and high-beam thump are synthesized in code (`core/Sfx.gd`)
    until the Phase 7 audio pass.
- **Wrecks** slide to a stop, smoke for 6 s, then get "towed" (shrink away over 0.5 s) and go back
  to the pool. Traffic treats them like stopped cars. The smoke is a few mesh puffs animated in the
  physics step, not particles (CPUParticles uses MultiMesh, which had web issues in 4.4; see
  above).
- **High Beams:** a 42 m cone, ±11.5°, starting as wide as the car. Blinded drivers aim for 60% of
  their speed (slowing at traffic's usual 4.5 m/s² cap), stop changing lanes, wander ±0.45 m in
  their lane, and stay blinded until 3 s after the beam leaves them. The look is all additive
  (`blend_add`, unshaded): a cone from each headlight, a pool of light on the road, and billboard
  lens glare drawn over the car body. There's no SpotLight3D: it's cheaper on phones and the scene
  stays in daylight.
- **Radar Detector:** passive. A small dark box with LEDs on the HUD; touch screens get no PROP
  button because there's nothing to press.
- **Mood faces** over traffic (angry, dizzy) are SVG icons on billboard Sprite3Ds: Nunito has no
  emoji and web builds can't reach system emoji fonts.
- **HUD:** on desktop the prop dial (icon, cooldown pie and ring, an "on" ring, a SPACE key cap) sits
  above the speedometer. On touch screens the PROP button shows the same dial. The radar box is
  top-right (left of the pause button on touch screens).

## Music, difficulty and destinations (requested after Phase 5)

### Music and volume
- **Soundtrack:** the user's "Highway Momentum" (`assets/audio/music/highway_momentum.mp3`) loops
  through the whole game, garage included. It lives on an `AudioManager` autoload (the spec's
  suggested name), so it carries on across scene changes and while paused.
- **Buses:** Master → Music and SFX, created at startup. The synthesized prop sounds play on SFX.
- **Controls you can't miss:** a speaker button (mute everything) plus a music volume slider:
  top-left of the race HUD (under the speedometer on touch screens), on the garage's bottom row,
  and bigger in the pause menu. **M** (or the gamepad's Back/Select) toggles mute anywhere.
  The HUD and garage versions don't take keyboard focus, so arrow keys keep steering and browsing;
  the pause menu's version does, for gamepads.
- **The slider is music-only, mute is everything.** Separate effect volume comes with the
  Phase 7 settings menu. Moving the slider while muted unmutes. The slider uses a squared
  curve, because straight linear amplitude does nothing over most of its range.
- **Saved** in `user://settings.cfg` (browser storage on the web), ahead of the Phase 6 save
  system. Tests switch saving off.
- **Headless runs don't play the music:** there's no audio output there, and a stream that is
  never mixed is never cleaned up (it leaked at exit).

### Difficulty
- **Kickoff went from 4,000 m to 5,600 m** and keeps the spec's 3:00. The user finished the
  4,000 m version with more than a minute left every time, so they average at least about
  75 mph. At that pace 5,600 m leaves roughly 10-30 s. The careful autopilot now runs out of
  time (700-1,200 m short), which is intended: it was always the floor, not the target.
- `tools/run_balance.sh` gained `SKILL=1`, a confident driver (weaves early, brakes late, uses the
  shoulder in cars that don't mind it). It crashes more than it gains, so it still isn't a good
  stand-in for a strong player; reports from real players are the better guide.

### Start and finish set pieces
- **`LevelData.start_site` / `finish_site`** point at scenes whose roots extend `StartSite` /
  `FinishSite` (`scenes/sites/`). A level without a finish site gets the old city-limit
  gantry. Sites are built in code during race load (a mid-race build caused a hitch).
- **Road zones:** a finish site shapes the road around itself through `RoadManager`:
  - a straight zone (640 m before the line, 720 m after);
  - an open zone with no fence, trees or poles on the player's side;
  - paved zones (full speed; `surface_at`);
  - limit zones that move the player's outer boundary (`outer_limit_at`; PlayerCar uses it).
- **Kickoff's finish is the stadium's parking lot, not a line across the highway.** I-35 carries
  on past the stadium. A signed exit (a sign at half a mile, an overhead EXIT ONLY sign, and a
  roadside marquee counting down "KICKOFF IN m:ss" with the race clock) leads off the right
  shoulder to the lot gate. You finish when you're past the gate *and* off the highway lanes,
  so a missed exit costs time: you have to cut right across the shoulder into the lot.
  Traffic stays on the highway, which keeps the AI out of the lot.
- **The lot** (tailgate tents, grills with smoke, coolers, cornhole, fans in burnt orange, an
  $80 cash-only booth, a waving attendant, about 450 parked cars baked into one mesh) leaves the
  drive-in aisle clear. The stadium has a facade, a team-color band, a press box, light towers,
  a "TEXAS-SIZED MEMORIAL STADIUM" banner, and a scoreboard that mirrors the marquee. Its name
  is a parody, with no real logos.
- **Camera:** the chase camera looks down at the road, so tall scenery sits above the frame.
  Over the last 520 m to a site it tilts up a little (`RaceCamera.lift`). After the finish it
  swings round to frame the stadium with the car in shot (`showcase`), the FINISH banner fades,
  fireworks go off, and the results wait 3.8 s instead of 1.6.
- **Start:** a generic `StartSite` builds a water tower with the start town's name, a
  "LEAVING <TOWN>" sign and a green distance sign to the destination (real miles), all from the
  route. Round Rock adds a parody doughnut shop with a giant orange-glazed doughnut. During the
  countdown the camera starts on those landmarks (`RaceCamera.intro`) and eases back behind the
  car by GO. Start scenery stays before s = 230, because the first overpass can come at 240.
- **Other destinations** (convention center, fairgrounds, Grandma's house, a rustic wedding venue)
  arrive with their levels in Phase 6; each is a new FinishSite scene.

## Sound effects (requested after the music)

### Two web-only audio bugs
- **The music was silent on the web.** `AudioManager` created the Music and SFX buses with
  `AudioServer.add_bus()`. In Godot 4.4's web audio (sample playback), the default position (-1)
  is mishandled: each new bus lands one slot too early in the browser's copy of the bus list,
  so the sends formed a loop that never reached the speakers. Fix: add the buses in one go by
  raising `AudioServer.bus_count`. Found by measuring the Web Audio output level in headless
  Chromium (0 before, ~0.04 after).
- **Loops stuttered on the web.** Godot 4.4 loops a web sound by starting a new copy from
  JavaScript when the old one ends: a short gap every time, and the new copy forgets its pitch.
  `tools/build_web.sh` patches the exported `index.js` to use the browser's own gapless looping
  (`AudioBufferSourceNode.loop`). The patch checks that the code it replaces is still there and
  fails the build if not, so a Godot upgrade can't silently drop it (and may make it
  unnecessary).

### The sounds
- **Synthesized, not downloaded.** `tools/make_sfx.gd` generates every effect as a WAV in
  `assets/audio/sfx/` (no licenses to track; the spec allowed code-generated placeholders). The
  files are committed and imported as normal assets, so nothing is synthesized at runtime (that
  would hitch the web build). Any file can be swapped for a real recording with the same name.
- The list follows the spec: engines (a burbly V8 for the truck, a smoother six for the SUV, an
  electric whine for the EV), tire squeal, crash and bump, barrier scrape, near-miss whoosh and
  chime, horns, siren and "whoop", countdown beeps, a clock tick for the last ten seconds, UI
  clicks, a win fanfare, a sad-trombone fail, a "ka-ching" ticket, fireworks, and the props'
  existing bleep, honk, whoomp and radar chirp.
- **Engine pitch** climbs through gears and drops at each shift (`CarData.engine_gears`,
  `engine_pitch`); the EV has no gears, so its whine just rises. Holding the gas during the
  countdown revs it. Picking a car in the garage blips its engine.
- **No 3D audio.** Sounds out on the road (pileup crashes, other drivers' horns, the siren) are
  plain players whose volume falls off with distance (`Sfx.play_at`). That's predictable on
  every platform, including the web's sample playback.
- **Mix:** the engine sits a bit under the music (the user asked for the song specifically);
  the win and fail stingers duck the music for two seconds. The pause menu has an Effects
  slider next to Music; the HUD and garage keep just the music slider and mute.
- Every button clicks (`AudioManager` hooks every BaseButton as it enters the tree); a button
  can set its `sfx` meta to another sound or to nothing.
- Headless runs (tests, the balance bot) play nothing but record the names in `Sfx.heard`, so
  tests check that a spin-out crashes, a near miss whooshes, and so on.

## Phase 4: police (built before Phase 3, on request)

### Speed traps
- **Count per level, spots per run:** `LevelData.speed_traps` (Kickoff has 3). They're spread
  over the open road: not in the first 700 m, not near the finish site, not in a metro jam.
  New spots every run.
- **Hiding spots are off the right side of the road**, not in the median: our median is a Jersey
  barrier right next to the fast lane, with no room for a car. The cruiser sits angled toward
  the road, partly hidden behind a hedge under a parody billboard, under a big live oak, or (when
  the road happens to pass under an overpass nearby) tucked by the overpass piers, as
  Overpass.gd always intended.
- **Tells:** a glint off the cruiser's windshield every 1.8 s, traffic easing off to just under
  the limit for 170 m before a trap (brake lights ahead), and the billboard itself, which shows
  up well before the cruiser. White "SPEED LIMIT 75" signs stand every 1.5 km.
- **The radar zone is 60 m before the cruiser to 12 m past it**, over the limit + 5 mph. It
  started at 110 m, but the chase camera only shows about 140 m of road at top speed, so at
  110 m you'd be clocked about when the cruiser came into view. At 60 m you get ~1.7 s to spot
  it and brake. The EV's Silent Running scales the zone by 0.6 (36 m).
- **Radar Detector:** traps never trigger ("RADAR DETECTOR: TRAP DODGED"); its LEDs follow
  `Police.threat_at` (from 450 m out). It doesn't stop the other ways to start a chase.

### Chases
- **The trooper is a traffic car** (`PoliceCar` extends `TrafficCar`, made by
  `TrafficCarData.car_script`), so it bumps, brakes and gets boxed in like everyone else. 125
  mph top speed, faster than any player car. A cruiser clocked before you reach it waits for
  you to pass, then pulls out behind you.
- **Pursuit AI:** flat out in the lane with the most open road until it's 40 m back, then it
  paces you and pulls alongside in the lane next to yours, on whichever side has a clear way
  up. With traffic on both sides it sits on your bumper until a lane opens. It doesn't
  sideswipe into cars, and bumps don't rattle it.
- **Pulled over** after 2 s alongside (the meter fills red). The world freezes behind a ticket
  card (the trooper's line, the citation, -15 s), then you pull back out from the shoulder at
  ~30 mph with the cruiser parked behind you, lights still going. Tickets show on the results
  screen (needed for 3 stars when stars arrive in Phase 6).
- **Escape:** 120 m ahead for 8 s (the meter fills green), or 320 m at once. Traffic is the
  usual way: the trooper brakes for slowpokes too. A chase also ends quietly at the finish or
  when time runs out.
- **Other ways to start one** (radar or not): hitting a cruiser, parked or moving; high-beaming
  one ("Did you just high-beam a TROOPER?"); flipping one off (troopers in range get the
  gesture first, and they don't road-rage, they write tickets).
- **Readability:** the trooper is usually behind you, out of the chase camera's view, so a
  pursuit meter under the top bar shows what it's doing and how far back it is, and the siren
  gets louder as it closes.

### Balance
- Slowing for a trap costs a sharp driver ~1.5-2 s (brake late, floor it right after) and a
  cautious one ~3 s, so Kickoff's three traps take roughly 5-9 s off the margin. A ticket (15 s
  plus the stop) usually means missing kickoff. The balance bot now brakes for traps it can see
  (`SPOT_TRAP`), and `TRAFFIC=0` / `TRAPS=n` make it easy to measure things like this.
- Lower construction-zone limits (spec section 10) will apply to traps once Phase 3 adds them.
