# Ruana y Pólvora — Stealth Prototype

A concept prototype built in **Godot 4.7** to test one question:

> Does approaching a patrolling guard from behind and executing him feel
> *tense* to approach and *satisfying* to pull off?

Set during the Colombian war of independence: a criollo assassin, a Spanish
royalist patrol, and a jungle at golden hour.

## Play

**Keyboard** — `WASD` move · `Mouse` look · `Shift` jog · `Ctrl`/`C` crouch ·
`E` assassinate · `R` restart · `Esc` menu · `H` cycle HUD

**Gamepad (Xbox)** — Left stick move · Right stick camera · `RT` jog ·
`B` crouch · `X` assassinate · `View` restart · `Menu` pause

Jogging gives you away. Crouching gets you closer. If you are spotted, run into
the tall grass and crouch — it breaks his line of sight.

## The design, in three numbers

Each movement mode has a **role**, enforced by how far the guard can hear you:

| mode | speed | heard at | role |
|------|-------|----------|------|
| crouch | 1.25 m/s | 0.9 m | reaches assassination range unheard — slow but safe |
| walk | 1.45 m/s | 3.0 m | 1.2 s exposed against a 1.5 s detection window — tight |
| jog | 3.9 m/s | 8.0 m | always gives you away — for repositioning or escaping |

The guard patrols at 0.95 m/s. **Every one of those numbers is load-bearing**:
when crouch speed was set to 1.25 while the guard also moved at 1.25, closing
the distance became mathematically impossible. The test suite now asserts the
game is winnable.

## Built with AI, verified by hand

- **Characters** — Meshy (image-to-3D), rigged in Mixamo
- **Animation** — Mixamo library clips, retargeted at runtime
- **Voice & SFX** — ElevenLabs (18 clips, Castilian Spanish against the
  player's criollo — deliberate, and subtitled in English)
- **Code** — Claude Code

Every AI-generated piece needed measurement to be trusted. A few that only
showed up because something measured them:

- The hidden blade spawned **15.4 m away from its own hand** — a
  `BoneAttachment3D` lives in skeleton space, and the position was never divided
  by the rig's scale (the mesh scale was).
- A Mixamo clip downloaded against a different character reported **239 m/s**
  (863 km/h): it came in that character's units, ~93× off. `rig.gd` now detects
  and normalizes foreign clips.
- The guard had **no hearing at all** — only a vision cone. You could sprint at
  his back and nothing happened.

## Verification

Four headless suites, no hardware required:

```bash
godot --headless --path . --script verify_locomotion.gd   # speeds, foot-sliding, blade
godot --headless --path . --script verify_detection.gd    # sight, hearing, design invariants
godot --headless --path . --script verify_gamepad.gd      # input map
godot --path . --script verify_menu.gd                    # pause menu (needs a window)
```

The ones that matter most are **cross-system invariants** — the unit tests were
all green while the game was unplayable:

- no movement state may out-run the animation clip that sells it
- crouch and walk must out-pace the guard
- walking must reach range, but **not for free**
- jogging must *never* work — otherwise nobody would ever crouch

## Web build

Web only supports the `gl_compatibility` renderer, so SSAO and volumetric fog
are unavailable there; `main._compatibility()` detects this at runtime and
compensates with stronger depth fog and glow.

```bash
bash build_web.sh      # exports to build/web/
python serve_web.py    # local test at :8000 WITH the COOP/COEP headers
```

`python -m http.server` will **not** work: without cross-origin isolation Godot
cannot use `SharedArrayBuffer` and boots to a black screen. `vercel.json` ships
those headers.

---

*Throwaway prototype. Standards are deliberately relaxed for speed — this code
is meant to answer a design question, not to ship.*
