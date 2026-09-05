# The Agentic Mouse showcase

GitHub Pages publishes this directory from `main`. The homepage uses ordinary HTML,
CSS and browser modules; it does not need a build service. Preview it with
`python3 -m http.server 8841 --bind 127.0.0.1 --directory docs`.

`showcase.js` reads the existing `CELLS` and `LAYERS` declarations from `script.js`.
Keep that file as the shared public mapping source, including source-specific
Razer arrow overrides and reported physical issues. The homepage never dispatches
a native command. Its HUD and lighting are labelled interactive previews.

The Three.js chapter renders on scroll, resize and interaction, with a capped
pixel ratio. Its camera world matrix must be current **before** projecting HTML
buttons: projecting before the first render can place focus targets far outside
the chapter. Keyboard testing caught that failure. The enclosing chapter uses
`overflow: clip`, which does not create a hidden scroll container. Keep the HTML
grid usable if WebGL is unavailable. The scroll tour permanently yields after
visitor input; mobile and reduced-motion layouts have no long pinned chapter.

## Dependencies

Browser dependencies are pinned and served from `lib/`, without runtime CDN imports:

- [Three.js 0.185.1](https://www.npmjs.com/package/three/v/0.185.1): module/core builds,
  `RoundedBoxGeometry`, `RoomEnvironment`. MIT; see `lib/THREE-LICENSE.txt`.
- [GSAP 3.15.0](https://www.npmjs.com/package/gsap/v/3.15.0): GSAP and ScrollTrigger.
  Their distribution headers retain the copyright and
  [GSAP Standard License](https://gsap.com/standard-license/) reference.
- [Manrope](https://fonts.google.com/specimen/Manrope), loaded through Google Fonts,
  with a system sans-serif fallback.

The repository's MIT license covers its original code, not third-party trademarks,
photography or separately licensed dependencies.

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
- `ethan-lounging.webp`: an AI scene commissioned by Ethan using his own studio and
  thedrums/Spotify Canvas photographs as identity and setting references. It is
  clearly labelled as AI on the page. It illustrates the reclining setup rather
  than claiming to be a documentary photograph or a live application screenshot.

Product photography and names remain the property of their respective owners.
Original private identity reference files, native configuration, review transcripts,
and browser-test screenshots do not belong in the public site.

## Review before publishing

Check the page in a real browser at desktop and phone sizes, including 320 pixels.
Try the hand switch, every mode family, pointer selection, Tab/arrow/Enter input,
and the technical-map link. Inspect settled scroll states and image proportions.
When changing assets or scripts, advance the homepage's cache query and verify the
live Pages response after pushing. A website preview cannot prove physical mouse
acceptance or native command delivery.
