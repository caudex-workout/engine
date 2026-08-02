# CLI performance baseline

Run `zig build benchmark-caudex-cli` on an otherwise idle machine to record
nanosecond timings for startup, database open, catalog search, history listing,
and last-performance lookup. The script creates its own temporary database and
uses only the Zig-built CLI. Results are descriptive baselines, not pass/fail
thresholds; record the hardware, operating system, Zig version, and output when
comparing a change.
