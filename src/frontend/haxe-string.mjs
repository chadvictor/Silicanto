// Haxe and JSON share most string escapes. Match complete escape tokens so
// a literal backslash followed by "b" or "f" keeps its original value.
export function haxeString(value) {
  return JSON.stringify(String(value)).replace(/\\[\\bf]/g, (token) => {
    if (token === "\\b") return "\\x08";
    if (token === "\\f") return "\\x0c";
    return token;
  });
}
