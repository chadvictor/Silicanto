import * as THREE from "three";
import scene from "./world.mjs";

const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setSize(1280, 720);
document.body.appendChild(renderer.domElement);
const camera = new THREE.PerspectiveCamera(53, 1280 / 720, 0.1, 420);
let elapsed = 0;
let previous = 0;
let playing = true;
window.addEventListener("keydown", (e) => {
  if (e.code === "Space" && !e.repeat) playing = !playing;
});
renderer.setAnimationLoop((time) => {
  if (playing) elapsed += time - previous;
  previous = time;
  const t = elapsed * 0.000105;
  const approach = (1 - Math.cos(t)) * 0.5;
  camera.position.set(
    -4.8 * Math.sin(t) - approach,
    4.9 - 0.9 * approach + 2.1 * Math.sin(t) * Math.sin(t) - 1.3 * Math.sin(t),
    24.9 - 24 * approach,
  );
  camera.lookAt(
    -1.2 + 0.8 * Math.sin(t),
    4.55 - 0.55 * Math.sin(t),
    -15 - 1.5 * approach,
  );
  renderer.render(scene, camera);
});
