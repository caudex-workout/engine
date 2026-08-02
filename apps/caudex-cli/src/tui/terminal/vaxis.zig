const vaxis = @import("vaxis");
const terminal = @import("../terminal.zig");
pub fn driver() type { _ = vaxis; return terminal.Driver; }
