//! Typed application intents shared by terminal interaction and client services.
//! This boundary deliberately contains neither CLI tokens nor terminal types.

pub const Action = union(enum) {
    start_workout,
    finish_workout,
    cancel_workout,
    log_selected_set,
    add_exercise: []const u8,
    reorder_exercise: ReorderExercise,
    change_set: ChangeSet,
    move_selection: Direction,
    show_help,
    quit,
};

pub const Direction = enum { up, down };
pub const SetAction = enum { log, skip, reopen };
pub const WorkoutEndAction = enum { finish, cancel };
pub const ReorderExercise = struct { membership_id: []const u8, direction: Direction };
pub const ChangeSet = struct { set_id: []const u8, action: SetAction };

pub const Executor = struct {
    context: *anyopaque,
    execute: *const fn (*anyopaque, Action) anyerror!void,
};

pub fn dispatch(executor: Executor, action: Action) !void {
    try executor.execute(executor.context, action);
}
