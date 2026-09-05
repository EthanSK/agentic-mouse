# The Agentic Mouse showcase

Build with `make test-site`, then serve `.build/site`. GitHub Actions runs the same build and tests on every push to `main`, then publishes the artifact to GitHub Pages. Pull requests only build and test. The Pages publishing source must be **GitHub Actions**.

## Source of truth

`Sources/ShowcaseExporter` links `ScimitarKit` and exercises the real `ModePickerCoordinator` with inert leases, manual clocks, and recording HUDs. It exports the reachable mode graph, labels, colours, repair markers, physical crosswalk, wheel descriptions, app list, and keypad groups. No native configuration, installed app icons, hardware connection, or private preferences are read.

`docs/simulator.mjs` consumes that generated graph. Both hands keep their own mode and Default-legend state. Automatic app mode follows the browser’s Current app selector; manual selection stays fixed, including through Chrome’s website submenu. Keypad text and action feedback are disposable browser examples. Third-party apps, OS actions, external bridge execution, and the native input security system are not emulated. The hero and controls chapter load the same separately authored Naga Left-Handed Edition and Scimitar Elite Wireless SE meshes. Each physical key carries only its printed number; the browser resolves its action through the native crosswalk. The hardware geometry is a photo-based reconstruction, not manufacturer CAD or an automatic scan.

`Scripts/build-site.py` writes `.build/site`, including generated `simulator-data.json` and a no-JavaScript full map. It applies a content-derived cache version to the homepage, CSS and browser modules. The published data identifies the exact source commit; uncommitted native work is not silently bundled into a deployment. The historical `docs/script.js` table is no longer consumed by the homepage or the generated full map. Do not use it as the showcase’s source of truth.

The Three.js chapter renders on scroll, resize and interaction, with a capped
pixel ratio. Its camera world matrix must be current **before** projecting HTML
buttons: projecting before the first render can place focus targets far outside
the chapter. Keyboard testing caught that failure. The enclosing chapter uses
`overflow: clip`, which does not create a hidden scroll container. Keep the HTML
grid usable if WebGL is unavailable. The scroll tour permanently yields after
visitor input; mobile and reduced-motion layouts have no long pinned chapter.

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
- `ethan-lounging.webp`: an AI scene commissioned by Ethan using his
  original studio photograph for the setting and his [real GitHub profile portrait](https://github.com/EthanSK)
  for the face. The earlier generated identity reference was replaced after Ethan
  reported that it did not look like him. It is
  clearly labelled as AI on the page. It illustrates the reclining setup rather
  than claiming to be a documentary photograph or a live application screenshot.

Product photography and names remain the property of their respective owners.
Original private identity reference files, native configuration, review transcripts,
and browser-test screenshots do not belong in the public site.

## Review before publishing

Check the page in a real browser at desktop and phone sizes, including 320 pixels.
Try the hand switch, every mode family, pointer selection, Tab/arrow/Enter input,
and the technical-map link. Inspect settled scroll states and image proportions.
The build advances asset cache versions automatically. After publication, verify
the exact live HTML, modules and generated data against the build artifact. A website preview cannot prove physical mouse
acceptance or native command delivery.
