# Programming hierarchy

Caudex separates deciding **what training happens** from deciding **how an
exercise progresses**.

A program strategy receives explicit athlete, history, session, configuration,
and program-state snapshots. It produces an ordered session. Each exercise slot
has its own progression assignment. Double progression and RPE top-set/backoff
are progression methods; “methodology” remains their v0.1 compatibility name.

## State and identity

Program state belongs to the strategy. Progression state belongs to one method
and one `stateId`. That ID names a program lane, not an exercise. For example,
`block-2-primary-squat` and `block-2-secondary-squat` can both reference squat
without sharing state.

Evaluation does not use a bare exercise ID to rediscover routing. The accepted
recommendation carries the slot ID, state ID, method ID/version, config, and
input state used for each prescription.

## Mixed-method TypeScript example

```ts
const result = caudex.recommendProgram({
  schemaVersion: 1,
  asOf: "2026-08-10T12:00:00Z",
  catalog,
  program: {
    strategy: {
      id: "caudex.fixed-session",
      versionRequirement: "0.1.0",
      configVersion: 1,
      config: {},
    },
    exercises: [
      {
        slotId: "primary-squat",
        exerciseId: "squat",
        progression: {
          stateId: "block-1-primary-squat",
          methodology: {
            id: "caudex.rpe-top-set-backoff",
            versionRequirement: "0.1.0",
            configVersion: 1,
            config: squatRpeConfig,
          },
        },
      },
      {
        slotId: "leg-extension",
        exerciseId: "leg-extension",
        progression: {
          stateId: "block-1-leg-extension",
          methodology: {
            id: "caudex.double-progression",
            versionRequirement: "0.1.0",
            configVersion: 1,
            config: legExtensionConfig,
          },
        },
      },
    ],
  },
});

const evaluation = caudex.evaluateProgram({
  schemaVersion: 1,
  asOf: completedAt,
  recommendation: result.recommendation, // persists all routing provenance
  catalog,
  completedWorkout,
});

for (const proposal of evaluation.progressionStateProposals) {
  // The host explicitly accepts/persists by proposal.stateId.
}
// evaluation.nextProgramState is separate and can be accepted independently.
```

The direct Zig API is `programming.recommendFixedSession` and
`programming.evaluateFixedSession`. Returned owned values expose `deinit()`;
neither function mutates supplied state.

## Legacy relation and current scope

`recommendSession` / `evaluatePerformance` and canonical `recommend` /
`evaluate` retain the single-methodology contract. Hosts migrate when they need
heterogeneous sessions. Discovery exposes the same implementations through the
legacy `methodologies` and clearer `progressionMethods` collections.

The fixed-session strategy is deliberately not adaptive. Recovery, volume,
scheduling, mesocycles, deloading, and exercise selection remain future strategy
behavior.
