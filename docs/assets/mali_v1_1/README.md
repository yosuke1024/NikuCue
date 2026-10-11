# NikuCue — Mali Texture Assets v1.1

## What this package contains
Six **RGBA 1024×1024 PNGs** with transparent backgrounds: idle, happy, celebrate, pet, sleepy, sad. The 6 pictures were generated from the owner-approved Concept A and cleaned/aligned for an **initial whole-image animation prototype**, along with a contact sheet and a manifest mapping existing app states to texture files.

Important: These files are **not bone-rigging source artwork, sprite-sheet frames, or proof of perfectly consistent anatomy**. The design retains small image-to-image changes. Do not present the character as animation-finished or ship automatically without visual sign-off. The approved Concept A in `Reference` is a visual identity reference, not an animation layer file.

## Fix in v1.1 — anatomical correction
The prior `mali_sleepy.png` incorrectly showed a lifted front paw *plus* both front paws planted on the floor. It was anatomically inconsistent. The replaced sleepy texture uses the owner-approved seated body silhouette and half-closed eyes: **both front paws remain on the floor; no extra arm and no mouth-covering yawn**. This is a deliberate expression change from “yawning” to “drowsy.” Use this corrected file, not the old v1 image. The other five textures are unchanged.

## Implementation order
1. Add the six PNGs to an Xcode asset catalog (`MaliIdle`, `MaliHappy`, `MaliCelebrate`, `MaliPet`, `MaliSleepy`, `MaliSad`), or use the existing TexturePackArtProvider import pipeline. Verify alpha is respected by SpriteKit and SwiftUI on a dark AND light background.
2. Preserve the current **state machine and reaction queue**; replace *only* code-drawn Mali visuals. A fallback code-drawn cat is permitted in DEBUG; it must not be the shipping visual.
3. Map `idle -> idle`, `greet -> happy`, `pet -> pet`, `celebrate -> celebrate`, `cheer -> happy`, `settle -> idle`, `doze -> sleepy`. `sad` is supplied as an **optional emotion only**; never display it to guilt users for skipping/pausing habits.
4. Render all images in the same square coordinate space, with bottom/floor anchor stable for seated variants and correct scale for the airborne `celebrate` pose. **Do not crop each PNG independently at runtime.**
5. Blend a pose change over approximately 0.12–0.22 s; do not morph faces by shape interpolation. For celebrate, a modest lift and return can be used with soft ease-in/ease-out. For pet, a tiny tilt or scale is okay, but do not distort the artwork.
6. Idle subtle breathing at <=1.5% scale change is only a temporary treatment. Blinks, tail swishes, and articulated movement require **separate redrawn layers or animation frames**; do not fake them by stretching the single portrait.
7. Respect Reduce Motion, pause/resume, and backgrounding; keep the original state machine and 40 acceptance checks.
8. Show owner a 15–30s on-device video demonstrating idle, pet, completion, rest, and dark/light backgrounds before advancing to more rigging work.

## Quality gates / Known limitations
- Raw image-generator outputs contained low-alpha colored speckles at the fringe; this pack reduces those artifacts, but **manual visual inspection is still mandatory**.
- Facial proportions, nose and mouth positions, fur texture, and bell proportions differ slightly across expressions. Use cross-fade, not naïve frame-by-frame flipbook playback.
- Images are full-character compositions, not independently movable body parts. Smooth ear and tail motion require a dedicated layer-asset pipeline later.
- The package does not include a pre-tested .xcodeproj or working iOS executable. Only assets, manifest, QA and instructions are supplied.
- This change does **not** alter the product’s name NikuCue, icon (paw print), habit features, Thai/English/Japanese texts, data storage, or banner/IAP strategy.

## Acceptance checklist
- Each PNG is RGBA, square, correctly named, with transparent background.
- No visible colored dots or obvious pale rectangular matte on pale AND dark UI backgrounds.
- Same Mali recognizably across 6 textures; eye, bell and ear colors are close.
- Seated poses do not visibly jump vertically when switched.
- Tapping `pet` shows the affectionate expression, without queuing duplicates.
- `celebrate` is triggered only after a successfully persisted completion event.
- `settle`/skipped habits do not show sad/guilt expressions.
- Smooth (not excessive) transitions; Reduce Motion prevents nonessential animations.

Owner approval is required before declaring the character visual production-ready.
