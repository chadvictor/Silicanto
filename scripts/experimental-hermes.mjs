import { buildNative } from "../src/native.mjs";

const [input, output, name] = process.argv.slice(2);
if (!input || !output) throw Error("experimental-hermes INPUT OUTPUT [NAME]");
await buildNative(input,output,name);
