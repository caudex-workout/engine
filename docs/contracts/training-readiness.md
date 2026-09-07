# Training readiness and fatigue

Caudex recovery state is a deterministic estimate of training readiness under
an identified policy. It is not a measurement or percentage of biological
recovery, and it is not medical advice.

## Boundary

`recovery.evaluate` consumes an explicit `as_of`, completed history, the
authoritative muscle-credit state from `volume.calculate`, exercise knowledge,
temporary observations, and a versioned policy. It never reads a clock,
mutates source history, treats prescribed work as performed work, or uses
remaining target volume as evidence of recovery.

Local state is derived independently for each represented muscle. Systemic
state is derived from completed session work and exercise systemic demand; it
is not an average of local readiness. Consequently a muscle and the athlete as
a whole can have different readiness states.

## Values and unknown state

Known readiness and fatigue use integer millionths from `0` through
`1_000_000`. Readiness means “estimated availability for additional training
under this policy and currently available evidence.” Fatigue is its bounded
complement within that policy. These values are programming heuristics, not
probabilities or physiological percentages.

When there is no usable evidence, both values are absent, status is `unknown`,
and confidence is `low`. Consumers must choose their own conservative or
permissive treatment of unknown state.

Confidence is the tier `low`, `moderate`, or `high`. It reflects evidence
coverage and consistency, not statistical certainty. Missing effort or demand
metadata and contradictory observations are preserved as structured factors.

## Baseline policy v1

`caudex.baseline-recovery` version 1 uses a seven-day evidence window by
default. Local credited contributions are transformed by explicit exercise
local-demand and observed-effort multipliers, then recover linearly over the
configured local window. Systemic cost is calculated separately per performed
set using exercise systemic demand and observed effort, then recovers over its
configured systemic window. All coefficients and windows are policy fields;
they are transparent modeling assumptions rather than universal constants.

Exercise fatigue metadata uses low/moderate/high tiers. Missing metadata uses a
neutral fallback and reduces confidence. RIR, RPE, partial work, and failed
work can alter stress; ordinary completed work with no effort observation uses
a neutral fallback. Skipped sets produce no systemic stress and do not appear
as completed volume contributions.

Soreness and fatigue observations lower readiness; subjective readiness,
sleep quality, and performance relative to expected capability can raise or
lower it. Soreness is evidence, not a prohibition. Opposing active evidence is
retained and lowers confidence. Every observation has an explicit timestamp
and validity duration; expired evidence has no effect. Future-dated evidence
is rejected.

## Provenance and replay

Results retain recovery policy identity/version, volume-policy
identity/version, `as_of`, recent training stress, last local exposure, and
structured factors that reference workout, exercise, set, or observation IDs.
The canonical source remains completed history plus observations. A derived
state can therefore be recomputed under another policy for simulation or
backtesting.

Session composition can consume a derived state through
`composeIntentWithRecovery`. The separate `RecoveryCompositionPolicy` may
prefer sufficiently ready targets or reduce a session-size constraint when
systemic readiness is low. It does not change the recovery estimate, and it
does not silently delete required program work: incompatible requirements
remain an explicit planning conflict.
