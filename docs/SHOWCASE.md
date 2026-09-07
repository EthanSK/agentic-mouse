# Ethan S K's personal setup website

Build with `make test-site`, then serve `.build/site`. GitHub Actions runs the same build and tests on every push to `main`, then publishes the artifact to GitHub Pages. Pull requests only build and test. The Pages publishing source must be **GitHub Actions**.

## Source of truth

`Sources/ShowcaseExporter` links `ScimitarKit` and exercises the real `ModePickerCoordinator` with inert leases, manual clocks, and recording HUDs. It exports the reachable mode graph, labels, colours, repair markers, physical crosswalk, wheel descriptions, app list, and keypad groups. No native configuration, installed app icons, hardware connection, or private preferences are read.

`docs/simulator.mjs` consumes that generated graph. Both hands keep their own mode and Default-legend state. Automatic app mode follows the browser’s Current app selector; manual selection stays fixed, including through Chrome’s website submenu. Keypad text and action feedback are disposable browser examples. Third-party apps, OS actions, external bridge execution, and the native input security system are not emulated. The hero and controls chapter load the same separately authored Naga Left-Handed Edition and Scimitar Elite Wireless SE meshes. Each physical key carries only its printed number; the browser resolves its action through the native crosswalk. The hardware geometry is a photo-based reconstruction, not manufacturer CAD or an automatic scan.

`Scripts/build-site.py` writes `.build/site`, including generated `simulator-data.json` and a no-JavaScript full map. It applies a content-derived cache version to the homepage, CSS and browser modules. The published data identifies the exact source commit; uncommitted native work is not silently bundled into a deployment. The historical `docs/script.js` table is no longer consumed by the homepage or the generated full map. Do not use it as the showcase’s source of truth.

The hero mice slowly turn; the thumb-button chapter rocks through a small angle
that keeps the key faces visible. `mouse-motion.mjs` shares their 30 fps idle loop.
Pointer and keyboard input pause it immediately, with a smooth restart after six
idle seconds. A held pointer or visible keyboard focus keeps it paused. After a
drag, the chapter gradually returns to the side view; hero dragging retains its
chosen orientation. Off-screen, hidden-page, reduced-motion and unavailable-WebGL
scenes do not run an idle rendering loop. Scroll, resize and interaction still
request individual frames, with a capped pixel ratio and no per-frame HUD rebuild.
The camera world matrix must be current **before** projecting HTML
buttons: projecting before the first render can place focus targets far outside
the chapter. Keyboard testing caught that failure. The enclosing chapter uses
`overflow: clip`, which does not create a hidden scroll container. Keep the HTML
grid usable if WebGL is unavailable. The scroll tour permanently yields after
visitor input; mobile and reduced-motion layouts have no long pinned chapter.

## Personal setup and code review

The website presents Ethan's personal setup; Agentic Mouse remains the app and
repository name. The compact `#engineers` section immediately after the hero
highlights Better Git VS Code. Its current personal workflow uses printed 5/8 on
both mice: a short release navigates, while a hold of at least 300 ms stages the
current file and advances in that direction **on release**, not at the threshold.
This was verified against the local native `VSCodeModeGestureClassifier` source
on 7 September 2026. The published native source still has the older staging
chords. Keep that distinction visible until the native change is released; do
not copy partial native/exporter changes into a website-only release or silently
relabel the generated simulator to imply an unreleased gesture is implemented.
VoiceInk++ is linked in the hero and speech explanation; Agent Bridge is linked
beside the review workflow and in the existing tools directory. Verify their
public sources before changing integration claims; the website does not perform
dictation, Git operations, or cross-machine messaging.

The `#watch-and-talk` feature, lounge copy and speech dialog explain Ethan's
YouTube dictation workflow. VoiceInk++ emits recording-start/stop notifications;
his separate YouTube helper and Chrome extension pause the playing video and
resume only the video they paused on a normal recording stop. This is not passive
speech detection or a capability provided by the website. The native triple-click
clipboard route deliberately preserves playback instead of resuming it. Keep
that exceptional gesture out of a blanket claim that every stop starts a video.

The final `#follow` section links to Ethan's verified public LinkedIn profile,
`https://www.linkedin.com/in/ethansk/`, and its recent activity. The large LinkedIn
mark is an inline vector; the banner works without JavaScript or third-party
requests. LinkedIn's [official embed guidance](https://www.linkedin.com/help/linkedin/answer/a529065/embed-content-from-the-linkedin-feed)
documents individual public posts, not an automatically updating personal feed.
Keep the recent-posts link honest; do not present static copy as live activity.

## Skills directory

The bottom `#skills` section in `docs/index.html` is a curated, static directory.
Its native HTML disclosures and public links work without JavaScript. Keep public
downloads, private workflow descriptions, the AIMVS development reference, and
earlier experiments clearly distinguished. The automatic pre-commit review is
disabled in Ethan's setup; the IDE-link patch is a documented failed experiment.
Neither belongs among current recommended tools.

Public repository visibility and descriptions were checked on 7 September 2026.
Before changing an entry, verify its current public README or `SKILL.md`; an
installed skill or a repository name alone does not prove it is published or
portable. Never commit the local skill inventory, usage/session evidence, private
skill source, or personal configuration. Private entries describe the workflow
only. Keep the source links in this HTML as the single maintained catalog; no
browser request to local skill folders or private GitHub APIs is needed.

## Native HUD preview

The controls chapter and HUD section share `docs/native-hud.mjs`. A physical mouse
key, HUD card, or keyboard activation updates both views through the same simulator.
The browser renders the native 4 × 3 hierarchy: action titles above printed source
labels, navigation colours, quieter opaque action fills, selection borders, repair
crosses, the mode footer, and Keypad cycles with the pending character highlighted.
The main HUD sits beside the mouse on desktop and below it on phones. Phone key
activation scrolls only enough to bring the HUD into view. The native application
and the visitor's Mac are never controlled.

`ShowcaseExporter` derives card colours from `ModeHUDCardColors`, borders from
`ModeHUDCardBorderTreatment`, padding from `ModeHUDLayoutMetrics`, and the version
from the committed `Resources/Info.plist`. Mode definitions, not browser tables,
choose which cards receive app icons. `assets/apps/*.png` contains 128 × 128 exports
of the corresponding installed application's public icon artwork; the normal build
uses these committed assets and does not inspect installed applications. The icons
and trademarks remain their owners' property. Add the matching icon if a new named
app is introduced; the website test checks every referenced icon.

The CSS matches `ModeHUDView` and `HUDView` spacing and type hierarchy. Browser blur
approximates macOS glass; it does not reproduce AppKit's system compositor. Changes
to SwiftUI's layout still need a matching CSS change and visual comparison. Native
mapping, colour-role and mode changes rebuild automatically on a push. Action
feedback clears after the native panel's four-second interval. A hidden Default
legend remains hidden after exiting a mode; each mouse retains its own state.

## Dependencies

Browser dependencies are pinned and served from `lib/`, without runtime CDN imports:

- [Three.js 0.185.1](https://www.npmjs.com/package/three/v/0.185.1): module/core builds,
  `GLTFLoader`, `DRACOLoader`, and their geometry utilities. MIT; see `lib/THREE-LICENSE.txt`.
- Draco WebAssembly decoder, pinned from the Three.js 0.185.1 distribution.
  Apache 2.0; see `lib/draco/DRACO-LICENSE.txt`.
- [three-mesh-bvh 0.9.14](https://github.com/gkjohnson/three-mesh-bvh): a shared
  spatial index for exact mesh picking, so each frame does not scan every triangle
  twelve times. MIT; see `lib/THREE-MESH-BVH-LICENSE.txt`. The bundled module exports
  only `MeshBVH` and `acceleratedRaycast`, with Three.js kept external.
- [GSAP 3.15.0](https://www.npmjs.com/package/gsap/v/3.15.0): GSAP and ScrollTrigger.
  Their distribution headers retain the copyright and
  [GSAP Standard License](https://gsap.com/standard-license/) reference.
- [Manrope](https://fonts.google.com/specimen/Manrope), loaded through Google Fonts,
  with a system sans-serif fallback.

The repository's MIT license covers its original code, not third-party trademarks,
photography or separately licensed dependencies.

## Rebuild the 3D hardware

The browser loads two compressed GLB assets from `models/`. They are shared between
both hero views and the side-button chapter. The default side view faces the thumb
buttons; Reset view restores that orientation. Returning to the controls chapter
starts on the right mouse, unless a hero key explicitly opens the left mouse's
action. Keyboard focus lights the physical key rather than drawing a flat square
over its angled face. A hidden key cannot intercept a
click through the shell. Product photographs and an HTML button grid remain usable
when WebGL or model loading is unavailable.

To change the physical reconstruction, use Blender 5.2 and run:

```sh
blender --background --factory-startup -t 4 --python Scripts/build-mouse-models.py
make test-site
```

Optional comparison renders: append `-- --renders /absolute/output/directory`.
The script fits separate shell profiles, panels, grip details, button assemblies,
and markings, then exports Draco-compressed GLBs. Blender is needed only when
editing the hardware meshes; normal site builds use the committed assets.

`models/marks.json` contains sampled emblem outlines from the
[Simple Icons Razer](https://github.com/simple-icons/simple-icons/blob/develop/icons/razer.svg)
and [Corsair](https://github.com/simple-icons/simple-icons/blob/develop/icons/corsair.svg)
SVGs. Simple Icons distributes its artwork under [CC0](https://github.com/simple-icons/simple-icons/blob/develop/LICENSE.md); the company trademarks
remain their owners' property. The physical references are the official galleries
linked below, including Razer Gallery 2/4/5 and Corsair SE images 1/4/5.

## Images

Every displayed image retains its source aspect ratio. Hardware thumbnails use
`object-fit: contain`; the lounge reveal clips the frame without stretching it.

- `corsair.webp`: [Corsair Scimitar Elite Wireless SE product image](https://assets.corsair.com/image/upload/c_scale,q_auto,w_1200/products/Gaming-Mice/CH-9314415-WW/gallery/SCIMITAR_ELITE_SE_BLK-YLO_01.png).
- `razer.webp`: [Razer Naga Left-Handed Edition thumbnail](https://medias-p1.phoenix.razer.com/sys-master-phoenix-images-container/h09/hba/9529652346910/naga-left-handed-2-500x500.png), used only at small sizes.
- `razer-angled.webp`: AI-assisted background replacement of Razer's high-resolution
  Gallery 3 photograph from the [official product gallery](https://www.razer.com/gaming-mice/razer-naga-left-handed-edition/RZ01-03410100-R3M1).
  The light background blends into the hero; the physical grid remains in its
  original left-handed orientation. It is a presentation image, not a mapping source.
- `razer-side.webp`: Gallery 4 from the same official Razer product gallery, converted
  to WebP without changing its proportions, used as the thumb-grid reference inset.
- `hbada.webp`: [Hbada E3 Pro 2026 grey chair image](https://www.hbada.uk/cdn/shop/files/E3_Pro_2026_Gray_with_footrest_ergonomic_office_chair_front.png?v=1778028844&width=1200).
- `ethan-lounging.webp`: an AI composite using Ethan's actual desk photo from
  5 September 2026 and a recent portrait selected from his named People collection
  in iPhone Photos. The portrait, taken on 2 September 2026, supplies his short
  haircut, face and outfit: a black graphic T-shirt and beige shorts. The desk
  photo supplies the bamboo top, laptop, monitors, speakers and microphone setup.
  The corrected image uses those original photos for identity and room details,
  the previous composition for framing, and the official black/yellow Corsair
  product image for the mouse under his right hand. The latest edit lowers the
  hips to correct the compressed lower torso while retaining the longer legs.
  The original portrait was supplied again as the face reference for that edit.
  The reclining pose and chair are AI reimagined. Both mice rest on the main
  desktop, with one in use and the other parked beside it. The image
  remains labelled as AI on the page; it is not a documentary photograph or a
  live application screenshot. Private photo-library originals stay outside the
  repository. The image URL uses the site's content version for browser updates.

Product photography and names remain the property of their respective owners.
Original private identity reference files, native configuration, review transcripts,
and browser-test screenshots do not belong in the public site.

## Review before publishing

Check the page in a real browser at desktop and phone sizes, including 320 pixels.
Try the hand switch, every mode family, pointer selection, Tab/arrow/Enter input,
and the technical-map link. Inspect settled scroll states and image proportions.
Hardware details were checked against the purchase confirmations on 5 September
2026. The FlexiSpot order specifies a black E7 Pro frame and 180 × 80 cm bamboo
desktop. The Corsair invoice confirms
`CH-9314415-WW` (black/yellow), the Razer order names the Naga Left-Handed Edition,
and the Hbada order confirms the grey E3 Pro 2026 with footrest. The chair URL selects
that exact variant. FlexiSpot has replaced the original product page with the 2026
revision, so the site explicitly identifies Ethan's 2025 model and the link's
limitation. Keep private receipts, invoice files and order URLs outside Git.

The build advances asset cache versions automatically. After publication, verify
the exact live HTML, modules and generated data against the build artifact. A website preview cannot prove physical mouse
acceptance or native command delivery.

## Dark header and room beta

The main walkthrough is dark by default, including the full-map page, error page
and web manifest. `hero-galaxy.mjs` draws an authored Three.js particle spiral,
inspired by the [GPT-6 Astra header](https://openai.com/index/gpt-6-astra/).
The reference's published poster shows cool white and warm stars winding into a
spiral; its page data describes drag/arrow rotation and scroll dispersion. The
reference's full animation could not be observed because its script chunks returned
403 responses. Do not describe our animation as OpenAI's original implementation.
No OpenAI source or artwork is bundled. One point-cloud draw call replaces a bloom
pipeline; the existing mouse scheduler caps rendering at 30 fps and suspends it
for off-screen, hidden-page and reduced-motion states. Pointer input and scroll
change the field without intercepting mouse model input.

`beta.html`, `beta.css` and `beta.mjs` form a separate desk walkthrough, linked from
the main header. It uses the existing portrait as a correctly proportioned plane
with a moving Three.js camera: this is a photo-based 2.5D environment, not a scan
or a reconstruction of unseen parts of Ethan's room. Wheel input, touch dragging,
arrow keys and the zoom buttons move the camera; the bottom dock also provides
keyboard-accessible routes to every feature. Its room canvas renders only while
the camera changes. It keeps the photograph and navigation when WebGL is unavailable.

The mouse panels reuse `MouseSimulator`, `createNativeHUD` and `createHeroMouse`
with the same committed Swift export as the main website. Never maintain a separate
beta mouse map. The code-review panel is explicitly an example of Ethan's current
300 ms release-to-stage workflow, separate from the published native map. The
YouTube panel is a silent local illustration: it neither reads a microphone nor
controls real media, and resumes its example video only if dictation paused it.
Both sites build and deploy together through the existing Pages workflow.

For local use, run `make site`, then serve `.build/site` and open `/beta.html`.
The main walkthrough stays at `/`; the beta does not replace it.

Website copy uses the same `write-user-facing-messages` historical examples and
corrections as AIMVS, following Ethan's explicit request. Prefer his direct,
single-sentence headings over paired marketing slogans. Keep application-specific
AIMVS naming constraints scoped to AIMVS.
