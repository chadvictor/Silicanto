import step from "./move.cjs";
import { width, advance } from "./state.mjs";

const canvas = document.getElementById("screen");
const context = canvas.getContext("2d");
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
