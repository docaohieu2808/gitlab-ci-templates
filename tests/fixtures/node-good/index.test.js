const test = require("node:test");
const assert = require("node:assert");
const { add } = require("./index.js");

test("add sums two numbers", () => {
  assert.strictEqual(add(2, 3), 5);
});
