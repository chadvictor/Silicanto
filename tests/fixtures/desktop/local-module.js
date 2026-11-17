window.dynamicScriptCalls++;
const childScript = document.createElement("script");
childScript.setAttribute("src", "local-child.js");
document.body.appendChild(childScript);
