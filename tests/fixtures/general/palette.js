var tileColor = '#47a86e';
<!-- A line comment in a classic script.
var legacyBytes = "\211PNG\032\8";
--> The closing marker can also start a line comment.
if (legacyBytes !== "\x89PNG\x1a8" ||
    document.getElementById("marker").textContent !== "literal <!-- marker")
  throw Error("classic script and data block");
