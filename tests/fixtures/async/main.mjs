const order = [];
async function twice(value) {
  order.push("start");
  try {
    return (await value) * 2;
  } finally {
    order.push("finally");
  }
}
async function verify() {
  const re = new RegExp("a+", "ig");
  if (
    !(re instanceof RegExp) ||
    !re.test("bAaa") ||
    re.lastIndex !== 4 ||
    !(/x/ instanceof RegExp) ||
    RegExp(re) !== re ||
    new RegExp(re) === re
  )
    throw Error("RegExp constructor and literals");
  const original = [2, 10, 1];
  if (
    original.toSorted().join() !== "1,10,2" ||
    original.toReversed().join() !== "1,10,2" ||
    original.join() !== "2,10,1"
  )
    throw Error("copying array methods");
  const descriptors = {};
  Object.defineProperties(descriptors, {
    n: { value: 7 },
    label: { get: () => "native", enumerable: true },
  });
  if (
    descriptors.n !== 7 ||
    descriptors.label !== "native" ||
    Object.keys(descriptors).join() !== "label"
  )
    throw Error("property descriptors");
  const identity = Promise.resolve(3);
  if (Promise.resolve(identity) !== identity) throw Error("promise identity");
  const pending = twice(identity);
  order.push("sync");
  if ((await pending) !== 6 || order.join(",") !== "start,sync,finally")
    throw Error("await order");
  const marker = { code: 17 };
  try {
    await twice(Promise.reject(marker));
    throw Error("expected rejection");
  } catch (e) {
    if (e !== marker) throw e;
  }
  const receiver = {
    value: 7,
    async read() {
      await 0;
      return this.value;
    },
  };
  const values = await Promise.all([
    twice(0),
    receiver.read(),
    Promise.resolve(11),
  ]);
  if (values.join(",") !== "0,7,11") throw Error("ordered native reactions");
  const race = await Promise.race([
    Promise.resolve("first"),
    Promise.resolve("second"),
  ]);
  let finished = false;
  const preserved = await Promise.resolve(4).finally(() => {
    finished = true;
  });
  if (race !== "first" || !finished || preserved !== 4)
    throw Error("race and finally");
  console.log("native async contracts passed");
}
verify().catch((e) => console.error("failed async contract", e));
