import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

const guides = [
  {
    path: "docs/methodologies/double-progression-v1.md",
    source: "src/double_progression.zig",
    id: "caudex.double-progression",
    codes: [
      "double_progression.prescribed.initial",
      "double_progression.prescribed.state_without_history",
      "repetitions.increased.completed_target",
      "load.increased.rep_range_completed",
      "load.held.partial_completion",
      "load.regressed.partial_completion",
      "load.held.failed_completion",
      "load.regressed.failed_completion",
      "load.held.insufficient_successful_sets",
      "sets.reduced.available_time",
      "history.insufficient_evidence",
      "methodology.config_invalid",
      "methodology.state_invalid",
      "methodology.state_unsupported_version",
    ],
  },
  {
    path: "docs/methodologies/rpe-top-set-backoff-v1.md",
    source: "src/rpe_top_set_backoff.zig",
    id: "caudex.rpe-top-set-backoff",
    codes: [
      "load.selected.history_estimated_one_rep_max",
      "load.selected.state_estimated_one_rep_max",
      "load.selected.initial_estimated_one_rep_max",
      "backoff.selected.percentage_of_top_set",
      "backoff.selected.percentage_of_estimated_one_rep_max",
      "estimate.observed.completed_top_set",
      "estimate.decreased.rpe_overshoot",
      "estimate.increased.rpe_undershoot",
      "estimate.held.rpe_overshoot",
      "estimate.held.rpe_undershoot",
      "estimate.held.rpe_within_tolerance",
      "history.insufficient_evidence",
      "methodology.config_invalid",
      "methodology.state_invalid",
      "methodology.state_unsupported_version",
    ],
  },
];

for (const guide of guides) {
  const documentation = await readFile(resolve(guide.path), "utf8");
  const implementation = await readFile(resolve(guide.source), "utf8");
  for (const heading of [
    "## When to use it",
    "## Configuration",
    "## State",
    "## Explanation and warning codes",
    "## Limitations",
  ]) {
    assertContains(documentation, heading, guide.path);
  }
  assertContains(documentation, guide.id, guide.path);
  assertContains(documentation.toLowerCase(), "not universally better", guide.path);
  for (const code of guide.codes) {
    assertContains(implementation, `"${code}"`, guide.source);
    assertContains(documentation, `\`${code}\``, guide.path);
  }
}

const index = await readFile(
  resolve("docs/methodologies/README.md"),
  "utf8",
);
assertContains(index, "double-progression-v1.md", "methodology index");
assertContains(index, "rpe-top-set-backoff-v1.md", "methodology index");
assertContains(
  index.toLowerCase().replaceAll(/\s+/g, " "),
  "neither is universally superior",
  "methodology index",
);

console.log("caudex methodology guides cover both v1 implementations");

function assertContains(value, expected, subject) {
  if (!value.includes(expected)) {
    throw new Error(`${subject} is missing ${JSON.stringify(expected)}`);
  }
}
