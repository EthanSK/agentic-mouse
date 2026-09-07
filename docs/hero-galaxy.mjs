import * as THREE from "three";
import { createMouseMotion } from "./mouse-motion.mjs?v=__SITE_VERSION__";

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
  const uniforms = { time: { value: 0 }, spread: { value: 0 }, pixelRatio: { value: renderer.getPixelRatio() } };
  const material = new THREE.ShaderMaterial({
    uniforms, transparent: true, depthWrite: false, vertexColors: true, blending: THREE.AdditiveBlending,
    vertexShader: `
      attribute float size;
      uniform float time;
      uniform float spread;
      uniform float pixelRatio;
      varying vec3 starColor;
      void main() {
        float radius = length(position.xy);
        float angle = time * .035 / (1.0 + radius * .18);
        mat2 turn = mat2(cos(angle), -sin(angle), sin(angle), cos(angle));
        vec3 p = position;
        p.xy = turn * p.xy * (1.0 + spread * .45);
        p.z += sin(radius * 1.4 + time * .14) * .07 + spread * sin(radius * 3.0);
        vec4 projected = modelViewMatrix * vec4(p, 1.0);
        gl_Position = projectionMatrix * projected;
        gl_PointSize = clamp(size * pixelRatio * 18.0 / -projected.z, 1.0, 24.0);
        starColor = color * (1.0 - spread * .45);
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
  let width = 0, height = 0, available = true;
  const reduced = matchMedia("(prefers-reduced-motion: reduce)");
  const motion = createMouseMotion(hero, () => renderer.render(scene, camera), delta => {
    uniforms.time.value += delta;
  }, () => available && width > 0 && height > 0); // Reuse the mice's 30 fps, off-screen, hidden-page and reduced-motion policy.
  new ResizeObserver(() => {
    width = hero.clientWidth;
    height = hero.clientHeight;
    camera.aspect = width / height;
    camera.position.z = camera.aspect < 1 ? 22 : 17;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height, false);
    motion.render();
  }).observe(hero);
  hero.addEventListener("pointermove", event => {
    if (reduced.matches || event.pointerType === "touch") return;
    const rect = hero.getBoundingClientRect();
    stars.rotation.x = -.6 + (event.clientY - rect.top - height / 2) / height * .22;
    stars.rotation.y = .15 + (event.clientX - rect.left - width / 2) / width * .3;
    motion.render();
  }, { passive: true }); // Listen through the hero, so the decorative canvas never intercepts model dragging or clicks.
  function scroll() {
    if (!height) return; // Scroll can arrive before the first ResizeObserver measurement.
    uniforms.spread.value = reduced.matches ? 0 : Math.min(1, Math.max(0, -hero.getBoundingClientRect().top / height));
    motion.render();
  }
  window.addEventListener("scroll", scroll, { passive: true });
  reduced.addEventListener("change", () => {
    stars.rotation.set(-.6, .15, -.48);
    scroll();
  });
  canvas.addEventListener("webglcontextlost", event => {
    event.preventDefault();
    available = false;
    canvas.style.visibility = "hidden";
    motion.render();
  });
  canvas.addEventListener("webglcontextrestored", () => {
    available = true;
    canvas.style.visibility = "";
    motion.render();
  });
}
