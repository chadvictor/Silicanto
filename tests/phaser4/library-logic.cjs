// A small consumer of actual upstream source with a nested dependency.
const intersects = require("./node_modules/phaser/src/geom/intersects/CircleToCircle");
const clamp = require("./node_modules/phaser/src/math/Clamp");
const EventEmitter = require("eventemitter3");
const bus = new EventEmitter();
let hits = 0;
bus.on("contact", () => { hits++; });
bus.once("contact", () => { hits += 10; });
const a = { x: 0, y: 0, radius: 1 }, b = { x: 8, y: 0, radius: 1 };
for (let i = 0; i < 4; i++) {
    b.x = clamp(b.x - 2, 0, 8);
    if (intersects(a, b)) bus.emit("contact");
    console.log(b.x, hits);
}

const seen = new Set([a,b]);
console.log(seen.has(a), seen.delete(b), seen.size);
