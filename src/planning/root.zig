//! Stateless, deterministic exercise-selection and session-optimization kernel.
//!
//! Planning chooses exercises and preserves progression lanes. It deliberately
//! does not prescribe sets, repetitions, loads, or mutate progression state.

pub const problem = @import("problem.zig");
pub const solver = @import("solver.zig");
pub const build = @import("build.zig");

pub const PlanningProblem = problem.PlanningProblem;
pub const SolveOptions = problem.SolveOptions;
pub const SolveResult = problem.SolveResult;
pub const ResolvedSessionPlan = problem.ResolvedSessionPlan;
pub const Workspace = solver.Workspace;
pub const FixedWorkspace = solver.FixedWorkspace;

pub const solve = solver.solve;
pub const validateResolvedPlan = solver.validateResolvedPlan;

test {
    _ = problem;
    _ = solver;
    _ = build;
}
