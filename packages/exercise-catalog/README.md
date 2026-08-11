# `@caudex-workout/exercise-catalog`

Optional first-party textual exercise data for Caudex applications. The package
contains 873 deterministically ordered records generated from the pinned
free-exercise-db revision in `source-manifest.json`. It has no runtime
dependencies and the core engine does not depend on it.

```ts
import { search, project, version, fingerprint } from "@caudex-workout/exercise-catalog";

const [record] = search({ text: "incline dumbbell curl", limit: 1 });
const engineExercise = project(record);
```

Records retain source IDs, textual instructions, nullable taxonomy fields, and
per-record provenance. Images and upstream image paths/URLs are intentionally
excluded because their individual provenance was not sufficiently verified for
first-party redistribution. Exercise IDs do not depend on image choices, so a
separately licensed media package can be added later.

Representative records include a typed, versioned `knowledge` projection.
Use `projectKnowledge`, `projectCapabilities`,
`supportsProgressionCapability`, and `relationships` to consume it. Taxonomy
refs retain source values/IDs and expose Caudex-owned `normalizedId` values;
search and core projection use those normalized IDs.
