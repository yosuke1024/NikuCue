# Claude Code change request — Mali asset pack v1

The latest owner-approved Mali character design is the high-quality illustrated Concept A. The previous path-based/code-drawn cat is **DEBUG placeholder only**, not a production visual.

Integrate the assets in this folder into the existing NikuCue iOS project. Read `README.md` and `mali_asset_manifest.json` carefully. Use these PNGs as initial **whole-body** textures via the existing `TexturePackArtProvider` (or equivalent asset abstraction) without refactoring domain logic, persistence, purchase, ads, or notification code.

Priority: render on iOS simulator/device; build a debug gallery to switch all six expressions; implement restrained opacity transitions and the short reaction motions outlined in README; preserve reduce-motion support. The sad texture is optional and never shown on missed/skipped habits.

Do not claim that layered rigging or natural blinking/tail physics are achieved with these six images. Ask for dedicated layer art later if necessary.

Validation deliverables: paths of imported assets, Xcode build/test results (or explicit limitations if not runnable), a short screen recording/screenshot of all six expressions on light/dark surfaces, and a list of any visual defects needing owner review. Do not mark the character complete without explicit sign-off.


## Mandatory v1.1 correction
Replace the previously imported `mali_sleepy.png` (not add as an alternate). Clear any asset catalog or preview caches as needed. The new `doze` texture depicts half-closed eyes with a closed mouth, both front paws grounded. Do not use the old yawning texture: it has an extra front leg. This is an asset-only update; leave domain logic and state mappings unchanged.
