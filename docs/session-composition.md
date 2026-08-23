# Session composition

Session composition is the deterministic boundary that turns an already
resolved program occurrence into the workout an athlete can perform today.
It preserves a strict distinction between program intent and the composed
result:

```text
program lifecycle -> planned session intent -> planning problem
                  -> resolved exercise slots -> progression prescriptions
                  -> composed session result
```

Program lifecycle owns the due role and its required and optional slots. The
planning subsystem owns exercise eligibility, ranking, global assignment,
ordering, duration feasibility, and bounded alternatives. Progression methods
own exercise-local loads, repetitions, sets, and state proposals. The composer
only orchestrates these capabilities and retains their provenance.

## Inputs

A composition request contains an immutable planned-session intent, catalog,
history snapshot, explicit `asOf` timestamp, solve bounds, and today's
constraints. Today's equipment, exclusions, required exercises, and time limit
are request facts; they never mutate the athlete profile, program definition,
or accepted program state.

Slots distinguish required from optional work and fixed from adaptive exercise
selection. Each slot carries its own progression lane, so one session may use
double progression for accessories and RPE top-set/backoff for a focus lift.
Explicit before/after edges and priority tiers control ordering without
embedding a universal training philosophy.

## Results

Composition returns a tagged result:

- `successful`: all requested slots were composed;
- `constrained`: a useful valid session was composed, but optional intent was
  omitted;
- `unsatisfiable`: a proved hard constraint cannot be met;
- `invalid`: the supplied snapshot or options are invalid; or
- `searchExhausted`: the configured deterministic search bound ended before a
  solution or infeasibility proof was established.

Successful and constrained results include both the prescribed workout and
the structural plan. The plan records required, target, optional, composed,
and omitted slot counts. This preserves what the program requested rather than
rewriting a shortened workout as the original intent.

An unavailable fixed or required exercise is never silently substituted.
Optional work may be omitted under a hard time or exercise-count limit, with
the omission and reason retained. Estimated duration is explicitly an
estimate; unknown estimates either remain unknown or make a candidate
ineligible according to the request's unknown-duration policy.

## Selection, alternatives, and explanations

The planner consumes the exercise catalog and selection requirements. It uses
typed objectives for target match, preferences, movement variety, exercise
reuse, equipment transitions, and target duration. Hard constraints are never
converted to score weights. Ties use an explicit stable-ID or seeded policy,
and candidate and complete-assignment search spaces are bounded.

Each selected adaptive slot includes bounded alternatives from the same
selector pass, including local rank, score contribution, duration estimate,
and whether it ranked lower because of score, deterministic tie-breaking, or a
global assignment tradeoff. Planner decisions and omissions use stable typed
reason codes and retain planner provenance. Exercise-local prescription
explanations remain attributed to the progression method that produced them.

## State and active workouts

Composition is pure and proposes no durable program change. Hosts may pass the
resulting multi-exercise recommendation into the existing recommendation
instantiation and active-workout lifecycle. Completion and program/progression
state acceptance remain separate explicit host decisions.

Future recovery, volume, capability, and preference-learning systems can feed
typed intent, eligibility, or objectives into the composer. They do not need
to take over exercise selection, progression prescription, or state
acceptance.
