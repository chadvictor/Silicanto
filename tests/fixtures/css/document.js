const xhr = new XMLHttpRequest();
xhr.open("GET", "document.json", false);
xhr.send();
if (xhr.status !== 200) throw Error("Missing WPT document");
const page = JSON.parse(xhr.responseText);
for (const tag of ["html", "head", "body"]) {
  const el = tag === "html" ? document.documentElement : document[tag];
  for (const pair of page[tag].attrs) el.setAttribute(pair.name, pair.value);
  if (tag !== "html") el.innerHTML = page[tag].html;
}
