import * as THREE from "three";

/** Draw an authored spiral field inspired by the Astra header, without a post-processing pipeline. */
export function createHeroGalaxy(hero) {
  const canvas = hero.querySelector(".hero-galaxy");
  let renderer;
  try {
    renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: false, powerPreference: "low-power" });
  } catch {
    canvas.hidden = true; // WebGL can be disabled or exhausted by other pages; the dark CSS backdrop remains visible.
    return;
  }
  renderer.setPixelRatio(Math.min(devicePixelRatio, 1.25));
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(45, 1, .1, 60);
  camera.position.z = 17;
  const count = matchMedia("(max-width: 760px)").matches ? 4500 : 9000;
  const positions = new Float32Array(count * 3);
  const colors = new Float32Array(count * 3);
  const sizes = new Float32Array(count);
  let seed = 37;
  const random = () => ((seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0) / 4294967296);
  for (let i = 0; i < count; i++) {
    const radius = Math.pow(random(), .62) * 8;
    const branch = (i % 3) * Math.PI * 2 / 3;
    const scatter = Math.pow(random(), 3) * 1.4;
    const angle = branch + radius * .78 + (random() - .5) * scatter;
    positions[i * 3] = Math.cos(angle) * radius + (random() - .5) * .12;
    positions[i * 3 + 1] = Math.sin(angle) * radius + (random() - .5) * .12;
    positions[i * 3 + 2] = (random() - .5) * (.15 + scatter * .6);
    const warm = random() > .86;
    const brightness = .4 + random() * .6;
    colors.set((warm ? [1, .72, .47] : [.66, .82, 1]).map(v => v * brightness), i * 3);
    sizes[i] = random() > .985 ? 7 + random() * 8 : 1 + Math.pow(random(), 4) * 4;
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute("position", new THREE.BufferAttribute(positions, 3));
  geometry.setAttribute("color", new THREE.BufferAttribute(colors, 3));
  geometry.setAttribute("size", new THREE.BufferAttribute(sizes, 1));
  const trail = Array.from({ length: 6 }, () => new THREE.Vector4());
  const trailBirth = new Float32Array(6).fill(-10);
  const pointer = new THREE.Vector2();
  const previousPointer = new THREE.Vector2();
  const uniforms = {
    time: { value: 0 }, spread: { value: 0 }, pixelRatio: { value: renderer.getPixelRatio() },
    aspect: { value: 1 }, pointer: { value: new THREE.Vector3() },
    trail: { value: trail }, trailBirth: { value: trailBirth },
  };
  const material = new THREE.ShaderMaterial({
    uniforms, transparent: true, depthWrite: false, vertexColors: true, blending: THREE.AdditiveBlending,
    vertexShader: `
      attribute float size;
      uniform float time;
      uniform float spread;
      uniform float pixelRatio;
      uniform float aspect;
      uniform vec3 pointer;
      uniform vec4 trail[6];
      uniform float trailBirth[6];
      varying vec3 starColor;
      void main() {
        float radius = length(position.xy);
        float angle = time * .035 / (1.0 + radius * .18);
        mat2 turn = mat2(cos(angle), -sin(angle), sin(angle), cos(angle));
        vec3 p = position;
        p.xy = turn * p.xy * (1.0 + spread * .45);
        p.z += sin(radius * 1.4 + time * .14) * .07 + spread * sin(radius * 3.0);
        vec4 projected = modelViewMatrix * vec4(p, 1.0);
        vec4 clip = projectionMatrix * projected;
        vec2 screen = clip.xy / clip.w * vec2(aspect, 1.0);
        vec2 away = screen - pointer.xy;
        float distance = length(away);
        float influence = 1.0 - smoothstep(0.0, .32, distance);
        vec2 displacement = (away + vec2(-away.y, away.x) * .45)
          / max(distance, .035) * influence * influence * .22 * pointer.z;
        float energy = influence * pointer.z;
        for (int i = 0; i < 6; i++) {
          float age = time - trailBirth[i];
          float fade = 1.0 - smoothstep(0.0, 1.4, age);
          vec2 segment = trail[i].zw - trail[i].xy;
          float along = clamp(dot(screen - trail[i].xy, segment) / max(dot(segment, segment), .00001), 0.0, 1.0);
          vec2 offset = screen - (trail[i].xy + segment * along);
          float reach = 1.0 - smoothstep(0.0, .28 + age * .07, length(offset));
          float wake = reach * reach * fade;
          displacement += (offset / max(length(offset), .04) * .035
            + segment / max(length(segment), .12) * .065) * wake;
          energy += wake * .12;
        }
        displacement /= max(1.0, length(displacement) / .24);
        clip.xy += displacement / vec2(aspect, 1.0) * clip.w; // Work in projected space so the wake follows the cursor at every depth and viewport shape.
        gl_Position = clip;
        gl_PointSize = clamp(size * pixelRatio * 18.0 / -projected.z, 1.0, 24.0);
        starColor = color * (1.0 - spread * .45) * (1.0 + min(energy, 1.0) * .55);
      }`,
    fragmentShader: `
      varying vec3 starColor;
      void main() {
        float radius = length(gl_PointCoord - .5) * 2.0;
        if (radius > 1.0) discard;
        float glow = exp(-radius * radius * 6.0) * .5;
        float core = exp(-radius * radius * 65.0);
        gl_FragColor = vec4(starColor, glow + core * .6);
      }`,
  });
  const stars = new THREE.Points(geometry, material);
  stars.rotation.set(-.6, .15, -.48);
  stars.position.y = .1;
  scene.add(stars);
  let width = 0, height = 0, available = true, visible = false;
  let frame = 0, lastDraw = 0, previousFrame = 0, dirty = true;
  let pointerInside = false, pointerMoved = false, trailIndex = 0, activeUntil = 0;
  const reduced = matchMedia("(prefers-reduced-motion: reduce)");

  function render() {
    dirty = true;
    if (!frame && visible && !document.hidden && available && width && height) frame = requestAnimationFrame(tick);
  }

  function tick(now) {
    frame = 0;
    if (!visible || document.hidden || !available || !width || !height) return;
    const running = !reduced.matches;
    const interval = 1000 / (now < activeUntil ? 60 : 30);
    if (!dirty && now - lastDraw < interval - 1) {
      if (running) frame = requestAnimationFrame(tick);
      return;
    }
    const delta = previousFrame ? Math.min((now - previousFrame) / 1000, .1) : 0;
    previousFrame = now;
    if (running) {
      uniforms.time.value += delta; // Pointer input must keep the field flowing; the mouse models' six-second pause is wrong for particles.
      uniforms.pointer.value.set(pointer.x, pointer.y,
        THREE.MathUtils.damp(uniforms.pointer.value.z, pointerInside ? 1 : 0, 12, delta));
      if (pointerMoved) {
        trail[trailIndex].set(previousPointer.x, previousPointer.y, pointer.x, pointer.y);
        trailBirth[trailIndex] = uniforms.time.value;
        trailIndex = (trailIndex + 1) % trail.length;
        previousPointer.copy(pointer);
        pointerMoved = false;
      }
    }
    renderer.render(scene, camera);
    lastDraw = now;
    dirty = false;
    if (running) frame = requestAnimationFrame(tick);
  }

  function refresh() {
    cancelAnimationFrame(frame);
    frame = 0;
    previousFrame = 0;
    if (!visible || document.hidden) clearPointer(); // A pointer left behind while switching pages must not keep an invisible interaction active.
    render();
  }

  new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    refresh();
  }).observe(hero);
  document.addEventListener("visibilitychange", refresh);
  new ResizeObserver(() => {
    width = hero.clientWidth;
    height = hero.clientHeight;
    if (!width || !height) return; // A collapsed hero cannot supply a usable camera aspect or canvas size.
    camera.aspect = width / height;
    camera.position.z = camera.aspect < 1 ? 22 : 17;
    camera.updateProjectionMatrix();
    uniforms.aspect.value = camera.aspect;
    renderer.setSize(width, height, false);
    clearPointer();
    scroll();
  }).observe(hero);

  hero.addEventListener("pointermove", event => {
    if (reduced.matches || event.pointerType === "touch" || !height) return;
    const rect = hero.getBoundingClientRect();
    pointer.set((event.clientX - rect.left - width / 2) * 2 / height,
      (height / 2 - event.clientY + rect.top) * 2 / height);
    if (!pointerInside) previousPointer.copy(pointer); // Re-entry must not draw a streak from the last exit point across the header.
    pointerInside = true;
    pointerMoved = pointer.distanceToSquared(previousPointer) > .00001;
    activeUntil = performance.now() + 1500;
  }, { passive: true }); // Listen through the hero; never intercept model dragging, speech controls, links or page scrolling.
  hero.addEventListener("pointerleave", () => { pointerInside = false; }, { passive: true });
  hero.addEventListener("pointercancel", () => { pointerInside = false; }, { passive: true });

  function clearPointer() {
    pointerInside = false;
    pointerMoved = false;
    uniforms.pointer.value.z = 0;
    trailBirth.fill(-10); // Scroll and resize move the image under a stationary cursor; discard strokes in the old screen coordinates.
  }

  function scroll() {
    if (!height) return; // Scroll can arrive before the first ResizeObserver measurement.
    uniforms.spread.value = reduced.matches ? 0 : Math.min(1, Math.max(0, -hero.getBoundingClientRect().top / height));
    clearPointer();
    render();
  }
  window.addEventListener("scroll", scroll, { passive: true });
  reduced.addEventListener("change", () => {
    scroll();
    refresh();
  });
  canvas.addEventListener("webglcontextlost", event => {
    event.preventDefault();
    available = false;
    canvas.style.visibility = "hidden";
    refresh();
  });
  canvas.addEventListener("webglcontextrestored", () => {
    available = true;
    canvas.style.visibility = "";
    clearPointer();
    refresh();
  });
}
