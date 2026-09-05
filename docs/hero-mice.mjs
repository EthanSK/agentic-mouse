import * as THREE from "three";
import { createMouseModel, lightStudio } from "./mouse-model.mjs?v=__SITE_VERSION__";

/** Keep the hero and control chapter on the same photographed hardware geometry. */
export async function createHeroMouse(figure, source, onCell, labelForCell) {
  const hand = figure.dataset.mouse;
  const canvas = figure.querySelector("canvas");
  const speech = figure.querySelector(".speech-callout");
  const line = figure.querySelector(".speech-leader path");
  const dot = figure.querySelector(".speech-leader circle");
  const pose = { x: .70, y: hand === "razer" ? -1.04 : 1.04, z: hand === "razer" ? .20 : -.20 };
  let width = 0, height = 0, renderModel, modelReady = false, visible = true;

  /** Join the label edge to the real projected top button, including the photograph fallback. */
  function connect(x, y, show = true) {
    const rect = figure.getBoundingClientRect();
    const label = speech.getBoundingClientRect();
    const startX = label.left + label.width / 2 - rect.left;
    const startY = (y > label.bottom - rect.top ? label.bottom : label.top) - rect.top;
    const elbowY = startY + (y > startY ? 16 : -16);
    line.setAttribute("d", `M ${startX} ${startY} V ${elbowY} L ${x} ${y}`);
    dot.setAttribute("cx", x);
    dot.setAttribute("cy", y);
    figure.querySelector(".speech-leader").style.opacity = show ? "1" : "0";
  }

  function render() {
    if (!visible || !width || !height) return;
    if (modelReady) renderModel();
    else {
      const rect = figure.getBoundingClientRect();
      const photo = figure.querySelector("img").getBoundingClientRect();
      connect(photo.left - rect.left + photo.width * (hand === "razer" ? .495 : .507), photo.top - rect.top + photo.height * (hand === "razer" ? .317 : .22));
    }
  }
  const resize = new ResizeObserver(() => {
    width = figure.clientWidth;
    height = figure.clientHeight;
    figure.querySelector(".speech-leader").setAttribute("viewBox", `0 0 ${width} ${height}`);
    render();
  });
  resize.observe(figure);
  resize.observe(speech);
  const observer = new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; render(); }, { rootMargin: "100px" });
  observer.observe(figure);
  figure.querySelector("img").addEventListener("load", render);

  try {
    const renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: true });
    renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
    const scene = new THREE.Scene();
    lightStudio(renderer, scene, 1); // The hero and control chapter photograph the same hardware under the same studio rig.
    const camera = new THREE.PerspectiveCamera(32, 1, .1, 40);
    camera.position.set(0, 0, 13);
    const model = await createMouseModel(hand, source);
    scene.add(model.group);
    const raycaster = new THREE.Raycaster();
    const point = new THREE.Vector3();
    const hint = document.createElement("span");
    hint.className = "hero-button-hint";
    hint.hidden = true;
    figure.append(hint);
    function hitAt(event) {
      const rect = canvas.getBoundingClientRect();
      raycaster.setFromCamera(new THREE.Vector2((event.clientX - rect.left) / rect.width * 2 - 1, -(event.clientY - rect.top) / rect.height * 2 + 1), camera);
      return raycaster.intersectObjects(model.pickables, false)[0]?.object.userData;
    }
    let renderWidth = 0, renderHeight = 0;

    renderModel = () => {
      if (renderWidth !== width || renderHeight !== height) {
        camera.aspect = width / height;
        camera.position.z = camera.aspect < .9 ? 13 * .9 / camera.aspect : 13;
        camera.updateProjectionMatrix();
        renderer.setSize(width, height, false);
        renderWidth = width;
        renderHeight = height;
      }
      model.group.rotation.set(pose.x, pose.y, pose.z, "ZXY");
      model.group.position.y = -.1;
      camera.updateMatrixWorld();
      model.group.updateMatrixWorld(true);
      point.set(0, .052, 0).applyMatrix4(model.speech.matrixWorld).project(camera);
      raycaster.setFromCamera(new THREE.Vector2(point.x, point.y), camera);
      const hit = raycaster.intersectObjects(model.pickables, false)[0];
      connect((point.x * .5 + .5) * width, (-point.y * .5 + .5) * height, !!hit?.object.userData.speech);
      renderer.render(scene, camera);
    };
    let drag, moved = false, frame = 0;
    canvas.addEventListener("pointerdown", (event) => {
      if (event.button !== 0) return;
      moved = false;
      drag = { id: event.pointerId, x: event.clientX, y: event.clientY, pitch: pose.x, yaw: pose.y, touch: event.pointerType === "touch" };
    });
    canvas.addEventListener("pointermove", (event) => {
      if (!drag) {
        const hit = hitAt(event);
        const label = hit?.speech ? speech.textContent.trim() : hit?.cell ? labelForCell(hand, hit.cell) : "";
        hint.textContent = label;
        hint.hidden = !label;
        canvas.classList.toggle("is-action", !!label);
        return;
      }
      if (event.pointerId !== drag.id) return;
      hint.hidden = true;
      const x = event.clientX - drag.x, y = event.clientY - drag.y;
      if (!moved && Math.hypot(x, y) < 7) return;
      if (!moved && drag.touch && Math.abs(y) > Math.abs(x)) { drag = null; return; }
      moved = true;
      figure.classList.add("model-rotated");
      canvas.setPointerCapture(event.pointerId);
      canvas.classList.add("is-dragging");
      pose.y = drag.yaw + x * .01;
      pose.x = Math.max(-1.5, Math.min(1.5, drag.pitch + (drag.touch ? 0 : y * .008)));
      if (!frame) frame = requestAnimationFrame(() => { frame = 0; render(); });
    });
    function release(event) {
      if (!drag || event.pointerId !== drag.id) return;
      drag = null;
      canvas.classList.remove("is-dragging");
      if (canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
      if (moved || event.type === "pointercancel") return;
      const hit = hitAt(event);
      if (hit?.speech) speech.click();
      if (hit?.cell) onCell(hand, hit.cell);
    }
    canvas.addEventListener("pointerup", release);
    canvas.addEventListener("pointercancel", release);
    canvas.addEventListener("pointerleave", () => { hint.hidden = true; });
    function reset() {
      pose.x = .70;
      pose.y = hand === "razer" ? -1.04 : 1.04;
      pose.z = hand === "razer" ? .20 : -.20;
      figure.classList.remove("model-rotated");
      render();
    }
    figure.querySelector(".hero-reset").addEventListener("click", reset);
    canvas.addEventListener("keydown", (event) => {
      if (!["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Home"].includes(event.key)) return;
      event.preventDefault();
      if (event.key === "Home") reset();
      else {
        figure.classList.add("model-rotated");
        if (event.key === "ArrowLeft") pose.y -= .16;
        if (event.key === "ArrowRight") pose.y += .16;
        if (event.key === "ArrowUp") pose.x = Math.max(-1.5, pose.x - .16);
        if (event.key === "ArrowDown") pose.x = Math.min(1.5, pose.x + .16);
        render();
      }
    });
    canvas.addEventListener("webglcontextlost", (event) => {
      event.preventDefault();
      modelReady = false;
      figure.classList.remove("model-ready");
      render();
    });
    canvas.addEventListener("webglcontextrestored", () => {
      modelReady = true;
      figure.classList.add("model-ready");
      render();
    });
    modelReady = true;
    figure.classList.add("model-ready");
    document.fonts.ready.then(render);
  } catch (error) {
    console.warn("The mouse model is unavailable; its product photograph remains visible.", error);
  }
  render();
}
