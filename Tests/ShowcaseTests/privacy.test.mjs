// Checks the built showcase before Pages publication so private coding rules do not return. Run with node --test Tests/ShowcaseTests/*.test.mjs.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

test("the public showcase excludes private coding-rule exports", () => {
  const html = readFileSync(new URL("../../.build.noindex/site/index.html", import.meta.url), "utf8");
  assert.doesNotMatch(html, /aimvs-dev-skill|coding-in-typescript|AIMVS Dev Skill/i);
});
