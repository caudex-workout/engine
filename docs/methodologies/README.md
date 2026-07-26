# Methodology guides

Caudex v0.1 contains two first-party methodologies. Neither is universally
superior; they encode different progression rules and require different input
evidence.

| Methodology | Prefer when | Required performance evidence | Primary state |
| --- | --- | --- | --- |
| [Double progression v1](double-progression-v1.md) | Repetitions should advance through a range before load increases. | Completed load, repetitions, and set status. | Current load and target repetitions per exercise. |
| [RPE top-set/backoff v1](rpe-top-set-backoff-v1.md) | A top set and its RPE/RIR should determine estimated strength and backoff work. | Completed top-set load, repetitions, and exactly one RPE or RIR value. | Estimated 1RM per exercise. |

Both methodologies are deterministic, use exact decimal measurements, reject
implicit unit conversion, return structured explanations, and propose state
without persisting it. Selection should follow the host's programming model and
available data, not a claim that one methodology is best for every athlete or
application.

