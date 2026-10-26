const test = require("node:test");
const assert = require("node:assert");
const { add } = require("./index.js");

// Deliberately wrong: the pipeline must go red on this.
test("add sums two numbers", () => {
  assert.strictEqual(add(2, 3), 6);
});
