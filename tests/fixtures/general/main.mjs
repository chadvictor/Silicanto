import step from "./move.cjs";
import { width, advance } from "./state.mjs";

const canvas = document.getElementById("screen");
const context = canvas.getContext("2d");

// Consume the live source once, left to right. A target or default may
// mutate the next element. The expression returns the original iterable.
const tuple = [undefined, 2, [3], 4, undefined];
let head, nested, tail, receiver = {}, original = receiver;
if (([receiver.x = (receiver = {}, tuple[1] = 7), head, [nested], ...tail] = tuple) !== tuple ||
    original.x !== 7 || receiver.x !== undefined || head !== 7 || nested !== 3 ||
    tail.length !== 2 || tail[0] !== 4 || tail[1] !== undefined)
  throw Error("array assignment order");
const set = new Set([undefined, 2]);
[head = (set.delete(2), set.add(9), 1), nested] = set;
if (head !== 1 || nested !== 9) throw Error("live collection destructuring");
for ([, head, ...tail] of [new Uint8Array([4, 5, 6])]) {
  if (head !== 5 || tail.join() !== "6") throw Error("loop assignment");
}
const [planet, ...letters] = "🌎ab";
if (planet !== "🌎" || letters.join("") !== "ab") throw Error("string code points");
let typeError = false;
try { [] = { length: 0 }; } catch (error) { typeError = error instanceof TypeError; }
if (!typeError) throw Error("non-iterable array assignment");
const controls = "\b\f\\b\\f";
if (controls.length !== 6 || controls.charCodeAt(0) !== 8 ||
    controls.charCodeAt(1) !== 12 || controls.slice(2) !== "\\b\\f")
  throw Error("Haxe string escaping");
if ((2).constructor !== Number || false.constructor.name !== "Boolean" ||
    "".constructor !== String || [].constructor !== Array ||
    ({}).constructor !== Object || new Uint8Array(0).constructor.name !== "Uint8Array")
  throw Error("built-in constructor identity");
const types = { Bytes: Uint8Array };
if (eval("new types.Bytes(new ArrayBuffer(2 * 3)).length") !== 6 ||
    eval("new types['Bytes']().length") !== 0 ||
    !(eval("new types.Bytes") instanceof Uint8Array))
  throw Error("native eval constructor calls");
const sprite = new Image();
function draw(time) {
  context.fillStyle = "#232b39";
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.fillStyle = tileColor;
  context.fillRect(step(time), 3, width, 6);
  context.drawImage(sprite, 1, 1);
  advance();
  requestAnimationFrame(draw);
}
const resource = new XMLHttpRequest();
resource.open("GET", "tile.png");
resource.responseType = "blob";
resource.onload = () => {
  const url = URL.createObjectURL(resource.response);
  sprite.onload = () => {
    URL.revokeObjectURL(url);
    requestAnimationFrame(draw);
  };
  sprite.src = url;
};
resource.send();

const events = [];
events.beforeUpdate = ["step"];
if (
  events.length !== 0 ||
  events.beforeUpdate[0] !== "step" ||
  !("beforeUpdate" in events) ||
  !Object.hasOwn(events, "beforeUpdate") ||
  Object.keys(events).join(",") !== "beforeUpdate"
)
  throw new Error("named array properties");
delete events.beforeUpdate;
if (events.beforeUpdate !== undefined || Object.keys(events).length !== 0)
  throw new Error("delete named array property");

const uriText = "Nácar 🌎/#";
if (
  decodeURIComponent(encodeURIComponent(uriText)) !== uriText ||
  encodeURI(uriText) !== "N%C3%A1car%20%F0%9F%8C%8E/#"
)
  throw new Error("native Unicode URI codec");
