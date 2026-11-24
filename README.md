# dotfiles

Cross-platform macOS and Linux dotfiles managed with [chezmoi](https://www.chezmoi.io/) and [Task](https://taskfile.dev/).

## Locations & Workflow

Author changes in the local development checkout, push to the remote GitHub repository, and pull updates into each machine via `chezmoi`:

1. **Local dev checkout** (`DEV_REPO_DIR`): where edits, tests, and commits happen (e.g., `~/Developer/projects/personal/dotfiles`).
2. **Remote repository** (`origin/main`): `https://github.com/<GITHUB_USERNAME>/dotfiles.git`.
3. **Machine home** (`$HOME`) & chezmoi mirror (`~/.local/share/chezmoi`): kept clean and updated from `origin/main`.

### Common Tasks

- `task diff`: Preview diffs against `$HOME` from the local dev checkout without updating `~/.local/share/chezmoi` or fetching externals.
- `task dry-run`: Run `chezmoi apply --dry-run --verbose --force` against the local dev checkout without mutating `$HOME`.
- `task render FILE=<path>`: Render a single template using templates and data from the local dev checkout.
- `task test`: Run Bats unit tests (`bats tests/unit/*.bats`).
- `task update`: Pull and apply remote updates (`chezmoi update --init`); aborts if `~/.local/share/chezmoi` is dirty.
- `task update-i`: Fast-forward pull, display `chezmoi diff`, and prompt before applying; aborts if `~/.local/share/chezmoi` is dirty.
- `task brewfile [FILE=<path>]`: Dump installed Homebrew taps, formulae, casks, MAS apps, and VS Code extensions (excluding `go`, `uv`, and `npm`).
- `task delete-snapshots DATE=<YYYY-MM-DD[/HH-MM-SS]>`: Safely remove a dotfile backup snapshot.

### New Machine Bootstrap

```bash
./install.sh -g <GITHUB_USERNAME>       # install chezmoi (to ~/.local/bin) and apply
./install.sh -g <GITHUB_USERNAME> -o    # one-shot init without keeping source checkout
```

## Package Ownership

- **Homebrew** (`home/dot_config/homebrew/Brewfile.tmpl`): OS- and system-level packages, casks, Mac App Store apps, and VS Code extensions.
- **mise** (`home/dot_config/mise/config.toml.tmpl`): Versioned developer tools and runtimes ([mise registry](https://mise.jdx.dev/registry.html), [aqua registry](https://github.com/aquaproj/aqua-registry)).

## Troubleshooting

- **Template not rendering**: Managed template files in `home/` must end with `.tmpl` (partial templates inside `home/.chezmoitemplates/` do not need `.tmpl`).
- **Update aborted due to dirty `~/.local/share/chezmoi`**: Reconcile or reset uncommitted changes in `~/.local/share/chezmoi` so it stays a clean mirror of `origin/main`.
