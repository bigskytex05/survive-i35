# Survive I-35: Game Design and Build Spec

You are building a complete, shippable game in **Godot 4 (latest stable), using GDScript**. Read this whole document before writing code. Build it in the phases listed at the end, and stop after each phase so I can test.

## 1. The pitch

**Survive I-35** is a humorous arcade racing game that spoofs the real experience of driving the I-35 corridor between Austin and Dallas, Texas: endless construction, surprise lane closures, bumper-to-bumper traffic, speed traps, and weird roadside sights.

Each level starts with a funny scenario explaining why the player urgently needs to get to Austin or Dallas. The player picks a car and a prop, then races the clock (3 to 5 minutes) down a stylized I-35. Beat the timer and you win.

Tone: affectionate local satire, like a Texan making fun of their own commute. Funny, never mean-spirited.

## 2. Platforms and technical requirements

- **Targets:** Android (phones and tablets) and web browsers (HTML5 export). Desktop builds are a free bonus for testing.
- **Renderer:** Use the **Compatibility** renderer (OpenGL ES 3 / WebGL 2). This is required for good web and low-end Android support. Do not depend on features that only work in Forward+.
- **Web export:** Configure it so it runs **without SharedArrayBuffer / cross-origin isolation** (thread support off), so it can be hosted on itch.io or any static host.
- **Performance target:** 60 fps on a mid-range Android phone, 30 fps minimum on a low-end one. Keep draw calls low, reuse materials, pool traffic cars and props instead of instancing and freeing them constantly, and prefer baked or simple lighting.
- **Orientation:** Landscape.
- **Input:** Must work with all three:
  - **Touch (Android, mobile web):** on-screen buttons for steer left, steer right, gas, brake, and a large prop button. Add an optional tilt-to-steer setting.
  - **Keyboard (web):** WASD or arrow keys to drive, Space for the prop, Esc to pause.
  - **Gamepad:** left stick to steer, triggers for gas and brake, A / bottom button for the prop.
  - Use Godot's InputMap actions (`steer_left`, `steer_right`, `accelerate`, `brake`, `use_prop`, `pause`) so every input method goes through the same code.
- **Code quality:** Small, single-purpose scripts. Data-driven design using custom `Resource` classes (`.tres`) for cars, props, levels, and traffic types, so new content can be added without touching code. Typed GDScript everywhere. Add short comments explaining non-obvious logic.

## 3. Art direction

The look is inspired by **Over The Hill** (Funselektor Labs, the makers of *art of rally*). Recreate the *feel*, not any of its assets:

- **Low-poly, flat-shaded 3D.** Simple chunky shapes, no realistic textures. Most surfaces are a single solid color or a simple gradient.
- **Elevated chase camera** looking down at the car at roughly a 35 to 50 degree angle, slightly zoomed out so the player can read traffic and lane closures ahead. Smooth follow with a little lag, and a subtle pull-back as speed increases.
- **Soft, warm, slightly desaturated palette.** Think golden-hour Texas: sun-bleached grass, warm tan dirt, pale blue sky, light concrete, with saturated accent colors reserved for things that matter (orange construction barrels, red and blue police lights, the player's car).
- **Soft lighting and atmosphere:** one directional sun with soft shadows, distance fog that fades the far road into the sky color, and gentle ambient color. A subtle vignette is fine.
- **Clean, minimal UI:** rounded sans-serif font, flat panels, generous spacing. The UI should feel calm and tidy even though the gameplay is chaotic. That contrast is part of the joke.
- **Toy-like vehicles:** slightly chunky proportions, simple wheels, visible but simple suspension bounce and body roll.
- **Phase 1 uses primitives** (boxes, cylinders, simple CSG or code-generated meshes) with the correct palette. Structure scenes so real low-poly models can replace the primitives later by swapping a single mesh node.

Define the palette once in a shared theme/constants file so it is easy to tweak.

## 4. Core gameplay loop

1. **Title screen** with the game logo over a slow fly-by of the highway.
2. **Level select:** a stylized map of the I-35 corridor with level pins between Austin and Dallas.
3. **Scenario card:** a short, funny briefing explaining why the player must get there fast, the start city, destination, and time limit.
4. **Garage:** choose 1 of 3 cars, then choose 1 of 3 props.
5. **Countdown** (3, 2, 1, GO), then drive.
6. **Race** against the timer through traffic, construction, and speed traps.
7. **Finish:** a results screen with time remaining, a star rating, stats (tickets received, cars "crashed out" by your gesture, near misses), and a funny one-line outcome based on how you did.
8. **Fail:** if the timer hits zero, show a funny failure line for the scenario (for example: "You arrived just in time to watch everyone leave the stadium.") with Retry and Change Loadout buttons.

### Timer and pacing

- Every level has a time limit between **3:00 and 5:00**.
- Real I-35 distances are compressed. A full Austin to Dallas run should take about 4 to 5 minutes of play, and shorter trips about 3 minutes.
- Show the remaining time big on the HUD. In the last 30 seconds, turn it red and pulse it.
- Show a progress strip at the top of the screen with the start city, the destination, the player's position, and upcoming named towns and mile markers.

### Star rating

- 1 star: finish before time runs out.
- 2 stars: finish with at least 20% of the time remaining.
- 3 stars: finish with at least 35% of the time remaining and zero tickets.

Tune these numbers once the levels are playable.

## 5. Levels and scenarios

Every trip **ends in Austin or Dallas**. Trips can start anywhere along the corridor, so some levels are shorter. Level data lives in a `LevelData` resource with: id, title, scenario text, start town, destination, distance, time limit, traffic density, construction density, number of speed traps, special events, success line, and fail line.

Starter levels (placeholders; I'll write better scenarios later):

| # | Title | Route | Time | Scenario |
|---|---|---|---|---|
| 1 | Kickoff | Round Rock to Austin | 3:00 | You have tickets to the big college football kickoff. Gates close in 3 minutes. Burnt-orange traffic everywhere. |
| 2 | The Unveiling | Waco to Austin | 3:45 | Your tech startup is unveiling its world-changing product (an app that tells you whether I-35 is under construction; the answer is always "yes"). You're the keynote. |
| 3 | Big D Game Day | Hillsboro to Dallas | 3:30 | Your cousin bet you couldn't make it to the big rivalry game at the fairgrounds before kickoff. Corny dog on the line. |
| 4 | Brisket Emergency | Austin to Dallas | 5:00 | You promised to deliver the family brisket to Grandma's 90th birthday in Dallas. It's still warm. Don't let it get cold. |
| 5 | The Wedding | Dallas to Austin | 5:00 | You're the best man and you have the rings. The ceremony is at a rustic venue just outside Austin, and the rustic venue does not wait. |

Make it easy for me to add more levels by creating a new `.tres` file.

### Route and towns

The highway is a stylized, compressed version of the real corridor. In order from south to north: **Austin, Round Rock, Georgetown, Salado, Temple, Waco, West, Hillsboro, Dallas.** Show green highway signs with town names and distances as the player approaches each one. Levels only use the stretch between their start and end towns.

## 6. Driving and the road

- **Arcade handling, not simulation.** Responsive steering, quick acceleration, a little drift. It should feel good on a touchscreen.
- The road is a long, mostly straight highway with gentle curves and overpasses, **3 to 4 lanes per direction**, with a shoulder and a concrete median barrier.
- Build the road from **reusable chunks** (straight, gentle curve, overpass, town exit, construction zone) that are spawned ahead of the player and recycled behind them. Each level defines a sequence or weighted mix of chunks, so levels feel authored rather than random.
- **Collisions:** bumping traffic or barriers costs speed and briefly wobbles the car. A hard crash causes a short spin-out (about 1.5 seconds) and drops the car back into a safe lane. No game over from crashing; the clock is the real enemy.
- **Near misses** (passing very close to a traffic car at speed) give a small time bonus of +0.5s and a little UI pop. This rewards bold driving.
- The speedometer shows mph. Display the current posted speed limit next to it, like a real speed limit sign.

## 7. The three cars

Data-driven via a `CarData` resource (top speed, acceleration, handling, mass, size, color, special trait). Each car has an honest trade-off:

| Car | Strengths | Weaknesses | Trait |
|---|---|---|---|
| **Truck** | Highest mass; shoves traffic and plows through construction cones with little speed loss | Slowest acceleration, wide turning | **Bully:** traffic cars it bumps get pushed aside instead of stopping it |
| **SUV** | Balanced all-rounder; best handling on the dirt shoulder | No standout strength | **Shoulder Surfer:** almost no speed loss when driving on the shoulder or grass |
| **EV** | Fastest acceleration (instant torque), tight steering | Lowest mass; gets knocked around | **Silent Running:** quieter, so police take longer to notice you speeding (a smaller detection radius) |

Color each car distinctly and let the player choose a paint color in the garage (cosmetic only).

## 8. The three props

The player picks one prop per level. Data-driven via a `PropData` resource (id, name, description, icon, type, cooldown, duration).

### 8a. Radar Detector (passive)

- The player is **invisible to police speed traps** for the whole level.
- Show a small radar detector on the HUD that beeps and lights up when a speed trap is near, purely as a fun effect.
- Balance: it does **not** stop a chase that has already started (for example, if you ram a cop car). It only prevents speed traps from triggering.

### 8b. Censored Hand Gesture (active)

- Press the prop button and the player's driver throws an offensive hand gesture out the window. The gesture is **always shown blurred/pixelated** with a big black "CENSORED" bar and a cartoon bleep sound. Never show the actual gesture.
- It targets the **nearest traffic car within about 15 meters**, ahead or beside the player.
- That driver gets furious (angry emoji pops above the car, horn honks) and **swerves toward the player** to hit them.
- Resolution:
  - **About 75% of the time they miss**, overcorrect, and crash out, taking out **1 to 3 other traffic cars** near them in a chain-reaction pileup. This clears space ahead of the player. The wreck becomes a smoking obstacle for a few seconds, then fades or gets towed.
  - **About 25% of the time they hit the player**, causing a spin-out.
  - The player can steer away to dodge, which should increase the miss chance. Skill matters.
- **Cooldown:** about 8 seconds. Show a radial cooldown on the button.
- Track a "Road Rage KOs" stat for the results screen.

### 8c. High Beams (active)

- Press the prop button to switch on blindingly bright high beams for about 4 seconds.
- **Do not make the whole game go dark.** Keep the normal daylight scene. Show the effect with two strong light cones (a SpotLight3D or emissive cone meshes with additive blending) projecting forward from the player's headlights, plus a lens-flare glare sprite.
- Traffic cars inside the cone ahead of the player become **"blinded"**: the driver covers their eyes (a simple pose or a "😵" icon above the car), the car slows by about 40%, and it drifts slightly within its lane. That makes them easy to pass.
- The blinded state lasts about 3 seconds after the beam leaves them.
- **Cooldown:** about 10 seconds.
- Balance: using high beams on a **police car** makes it chase you, with a funny popup like "Did you just high-beam a TROOPER?"

## 9. Traffic

- AI traffic drives in lanes at varied speeds, changes lanes occasionally (sometimes without signaling, as a joke), brakes for obstacles, and merges when lanes close.
- Traffic density varies by stretch: heavy around towns and construction zones, lighter in open country. Austin and Dallas approaches should feel like a parking lot that suddenly opens up.
- Include **slowdown waves**, the classic I-35 phantom traffic jam: traffic suddenly brakes for no visible reason and then speeds back up.
- **Placeholder traffic roster:** use generic types for now: compact sedan, minivan, pickup, 18-wheeler semi (big, slow, hard to see around), and a slow-moving construction truck. Each is a `TrafficCarData` resource with mesh, size, speed range, lane-change aggression, and a `personality` field.
- **Meme / regional stereotype cars come later.** Design the traffic system so I can add new car types with custom behaviors (for example, "always camps in the left lane at 5 under", "weaves between lanes at 100 mph", "brakes for no reason") by creating a new resource and optionally a small behavior script. Leave a clearly marked `TODO: meme car roster` in the traffic spawner and include a sample behavior hook so it's obvious how to extend.

## 10. Construction (the signature mechanic)

I-35 is always under construction. Construction must be a central, dynamic part of every level:

- **Lane closures:** orange barrels and cones taper lanes closed. Warning signs ("LEFT 2 LANES CLOSED AHEAD") and flashing arrow boards appear 150 to 200 meters before each closure so the player can react.
- **Surprise closures:** some closures activate as the player approaches. A construction crew walks out and drops cones, so a lane that looked open closes in front of you.
- **Flaggers:** a worker with a SLOW/STOP paddle occasionally holds traffic in a one-lane section. Driving past a STOP sign triggers a ticket and a time penalty.
- **Lane shifts:** temporary lanes that jog left or right, with faded old lane paint still visible as a visual joke.
- **Concrete barriers (Jersey barriers)** narrow the road and hurt on impact. Cones are lighter and fly away when hit, costing a little speed.
- **Idle crews:** sometimes there's a fully closed lane where one worker leans on a shovel and four others watch. Pure background humor.
- **Construction zone speed limits** are lower (for example 55 mph instead of 75), which matters for speed traps.
- Construction zones should be the main way levels create difficulty, not just more traffic.

## 11. Police and speed traps

- Each level contains a set number of **speed traps**: a police car parked in the median or behind an overpass pillar, partly hidden.
- A trap has a detection zone. If the player **passes through it above the posted speed limit (with about 5 mph of grace)**, the cop lights up and gives chase.
- **Going at or under the speed limit while passing the trap avoids the chase entirely.** This is a core skill: spot the cop, brake down, cruise past, then floor it.
- Give subtle visual tells before a trap: a glint off the windshield, a parked car shape in the median, or brake lights from traffic ahead slowing down.
- **The chase:** the cop pursues with lights and siren. If the cop gets alongside the player and stays there for about 2 seconds, the player is **pulled over**: a short, funny cutscene card ("License and registration... you know how fast you were going?") and a **15-second time penalty**, then the race resumes.
- The player can escape a chase by building a big enough lead for about 8 seconds, or by losing the cop in heavy traffic or a construction zone.
- **Radar Detector** makes speed traps never trigger (see 8a).
- The EV's trait shrinks the detection zone (see 7).
- Track "Tickets" for the results screen. A zero-ticket run is needed for 3 stars.

## 12. Roadside easter eggs and local humor

Line the highway with low-poly roadside gags. Use **parody names**, not real business names or logos, to avoid trademark issues. Most are pure scenery; a few are interactive. Place them where they belong geographically when possible.

Ideas to implement (make it easy to add more):

- A **gigantic beaver-mascot gas station** ("Busy Beaver's: 120 Pumps, 0 Open Parking Spots") with a huge line of cars spilling onto the frontage road.
- A **kolache bakery stop in West** ("Czech Yourself Kolaches"). Optional: driving through its exit lane gives +3s ("Sugar rush!"), but it costs time to get back on.
- **Farmhouse-chic silos in Waco** with a sign: "Shiplap Everything."
- **Injury lawyer billboards** every few hundred meters with ridiculous slogans ("HURT ON I-35? OF COURSE YOU WERE. Call The Texas Sledgehammer").
- **"Don't Mess With Texas" signs** and "Construction Ends 20??" signs where the year has been repainted many times.
- An orange-and-white striped **A-frame burger joint**.
- **Bluebonnet patches on the shoulder** with families stopped to take photos, sometimes right on the shoulder you wanted to use.
- **Fireworks stands** that look like circus tents.
- **Longhorn cattle** watching traffic from the fence line.
- **Armadillos** that wander onto the shoulder. Hitting one does nothing except make the player feel bad (a sad "rip 🪦" popup).
- A **sign counting how many days I-35 has been under construction**, with an absurdly large number.
- A **giant Texas flag** that's bigger than everything around it.
- **Austin end:** the old double-decker highway being demolished, "Keep Austin Weird" mural, food trucks, scooters abandoned everywhere, a guy in a cape on a unicycle.
- **Dallas end:** a glowing ball tower on the skyline, a tangle of overlapping overpasses (the "Mixmaster"), endless luxury SUVs.
- **Tornado sirens / sudden hail:** an optional random event where hail briefly pelts the screen and everyone slows down.
- **Tumbleweed** rolling across lanes at a dramatic moment.

Put each easter egg in its own small scene so new ones can be dropped into road chunks.

## 13. HUD and UI

- **HUD:** time remaining (top center, big), progress strip with towns (top), speedometer plus speed-limit sign (bottom right), prop button with cooldown ring (bottom right on mobile), touch controls (bottom left and right on mobile, hidden on desktop unless a touch is detected), small radar detector indicator when equipped.
- **Popups:** short, punchy text bubbles that float up and fade ("NEAR MISS +0.5s", "ROAD RAGE KO x3!", "TICKET -15s", "LANE CLOSED!").
- **Menus:** title, level select map, scenario card, garage (car and prop picker with stats bars and a one-line funny description), pause, settings (volume, tilt steering, touch control size, graphics quality low/high), results, and fail.
- Every menu is navigable by touch, mouse, keyboard, and gamepad.
- Scale the UI cleanly from small phones to desktop browsers.

## 14. Audio

- Use placeholder sounds generated in code or free CC0 assets for now. Keep the audio system organized with buses (Master, Music, SFX, UI) and a simple `AudioManager` autoload.
- Needed sounds: engine (pitch follows speed, with a distinct electric whine for the EV), horn, tire screech, crash, cone hit, siren, radar detector beep, censored bleep, high-beam "whoomp", UI clicks, countdown beeps, win and fail stingers.
- Music: an upbeat country-rock or Texas swing loop for racing, something calmer for menus. Placeholder for now.

## 15. Save data

Save to `user://` (works on Android and web via IndexedDB): unlocked levels, best time and stars per level, last selected car, prop, and paint, and settings. Level 1 is unlocked at the start; finishing a level unlocks the next.

## 16. Suggested project structure

```
res://
  autoload/        GameState.gd, SaveManager.gd, AudioManager.gd, Palette.gd
  data/
    cars/          truck.tres, suv.tres, ev.tres
    props/         radar_detector.tres, censored_gesture.tres, high_beams.tres
    levels/        01_kickoff.tres ...
    traffic/       sedan.tres, minivan.tres, pickup.tres, semi.tres, construction_truck.tres
  resources/       CarData.gd, PropData.gd, LevelData.gd, TrafficCarData.gd
  scenes/
    main/          Title.tscn, LevelSelect.tscn, Scenario.tscn, Garage.tscn, Results.tscn
    race/          Race.tscn, PlayerCar.tscn, RaceCamera.tscn, HUD.tscn
    road/          RoadManager.tscn, chunks/*.tscn
    traffic/       TrafficSpawner.tscn, TrafficCar.tscn, behaviors/
    police/        SpeedTrap.tscn, PoliceCar.tscn
    construction/  LaneClosure.tscn, Flagger.tscn, ConeDrop.tscn
    props/         RadarDetector.gd, CensoredGesture.gd, HighBeams.gd
    roadside/      easter egg scenes
    ui/            shared UI components, touch controls
  assets/          models/, audio/, fonts/, ui/
```

Adjust if you have a better structure, but keep the data-driven approach.

## 17. Build phases

Build in this order. **Stop after each phase**, summarize what you built and what's placeholder, and tell me exactly how to test it in the Godot editor and on web.

1. **Phase 1: Driving core.** Project setup (Compatibility renderer, input map, landscape, palette), a player car with arcade handling, the elevated chase camera, endless road built from recycled chunks, basic lighting, fog and art direction using primitives, and keyboard plus touch controls.
2. **Phase 2: Traffic and timer.** Lane-based AI traffic with pooling, collisions and spin-outs, near-miss bonus, timer, progress strip, finish line, simple win and fail screens.
3. **Phase 3: Construction.** Lane closures with warning signs, surprise cone drops, flaggers, lane shifts, construction speed limits, and the speed-limit sign on the HUD.
4. **Phase 4: Police.** Speed traps, chases, pull-over penalty, escape logic.
5. **Phase 5: Cars and props.** The three cars with traits, the three props with full behavior and cooldowns, and the garage screen.
6. **Phase 6: Levels and meta.** LevelData resources for the 5 starter levels, title screen, level select map, scenario cards, results with stars, save and unlock system.
7. **Phase 7: Humor and polish.** Roadside easter eggs, popups, audio, settings menu, screen shake, particles (cone debris, smoke, hail), and UI polish.
8. **Phase 8: Export.** Android and web export presets, a performance pass on a low-end target, and a short README on how to export and host the web build (for example on itch.io).

Before starting Phase 1, briefly confirm your plan and list any questions. If something in this spec is ambiguous, choose a sensible default, note it in a `DECISIONS.md` file, and keep going.

## Notes for later

- **Meme car roster:** deliberately left as a placeholder (section 9). When you're ready, we can write a follow-up prompt that adds each car as a new traffic resource and behavior.
- **Scenarios:** the five levels in section 5 are starters. Swap in better ideas any time by editing the table before you give it to Cursor, or later by asking Cursor to add new level `.tres` files.
- **Real names:** the easter eggs use parody names on purpose. Real brands (gas stations, burger chains, TV personalities) can create trademark trouble if you ever sell the game.
