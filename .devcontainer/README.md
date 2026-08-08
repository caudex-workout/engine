# Optional devcontainer

Open the repository in VS Code or GitHub Codespaces and choose **Reopen in
Container**. The image supplies Node 24, Zig 0.16.0, Python 3, SQLite, C/C++
build prerequisites, and the Zig/C/Python editor extensions. The first command
after creation is:

```sh
zig build check-fast
```

The post-create command only runs the read-only doctor. It does not install
project dependencies, publish artifacts, commit, or rewrite files. Run the
documented npm install commands when the full JavaScript suite is needed.

The devcontainer is optional and uses a Linux toolchain; macOS and Windows
native compatibility still require their host CI jobs. Nix is intentionally not
part of this repository’s supported setup.
