# Contributing

Packages come in through pull requests. A package is a folder in `packages/`. StableBar's user guide explains what goes inside it: [Packages and the store](https://github.com/Seb-GRAF/StableBar/blob/main/docs/packages.md) covers the manifest, settings, secrets and `"kind": "widgets"`, and [Themes](https://github.com/Seb-GRAF/StableBar/blob/main/docs/themes.md) covers making a theme.

## A package

The folder name equals the manifest `id`:

```text
packages/weather/
  package.json
  config.json
  preview.png
  scripts/weather.sh
```

Besides `id`, `name`, `version`, `entry` and `settings`, the store reads these manifest keys. All are optional:

| Key | Meaning |
| --- | --- |
| `kind` | `theme` or `widgets`. Leave it out for a package that runs commands. |
| `description` | One sentence for the store, the review and the package list in the README. |
| `author` | A person, organization or handle. |
| `repository` | The `https` URL of the package's source. |
| `screenshot` | Path inside the package to a PNG or JPEG. |
| `minimumVersion` | The oldest StableBar version that can run it, such as `0.6.0`. |
| `requires` | Command-line tools needed on the login shell's PATH, such as `jq` or `gh`. |
| `permissions` | macOS permissions: `calendars`, `automation`, `accessibility`, `bluetooth` or `location`. |
| `hosts` | Hostnames the package contacts, such as `api.github.com`. |

Declare everything the package uses. A maintainer compares `requires`, `permissions` and `hosts` with the code, and people read them in the README and in StableBar before adding a package.

CI validates packages against StableBar's `main`. If a package uses something that no stable release has yet, set `minimumVersion` so older versions refuse it instead of failing on your bar.

Add a `README.md` to the folder when the package needs setup outside StableBar, such as the hooks [Agent status](packages/agent-status/README.md) asks for.

### Preview

`screenshot` points to a preview of what the package shows in the bar. StableBar shows it in Store and on the package page, and the README shows it in the package list. Match the existing previews: 520 × 144 pixels, the widget centered on a plain background, with sample data and nothing personal.

### Files

Keep packages small and readable. Files can be at most 1 MiB. Binaries are not accepted; images must be `.png`, `.jpg` or `.jpeg`. A file other than JSON can't have a line over 300 characters, so minified code is rejected. Symlinks are rejected, and an executable file starts with a shebang. Shell scripts end in `.sh` and pass [ShellCheck](https://www.shellcheck.net), so they use `sh` or `bash`.

### Versions

Any change to a package needs a new `version`, even a fix to its description or preview. CI rejects a pull request that changes a package and keeps its version, because published versions are never replaced. A fix raises the patch version, such as 1.0.1 → 1.0.2; anything new raises the minor version, such as 1.0.2 → 1.1.0.

### The package list

The table in the [README](README.md#packages) comes from the manifests. After adding a package, or changing its name, description, preview or what it declares, run:

```sh
./scripts/update-readme.sh
```

and commit `README.md`. CI fails when the table is out of date. The script needs [jq](https://jqlang.org).

## Test on your Mac

Build StableBar with its `./scripts/build.sh`, then check the package against it:

```sh
STABLEBAR=path/to/StableBar.app/Contents/MacOS/StableBar ./scripts/check-package.sh packages/weather
```

This runs the file checks, then inspects the package, installs it into a scratch configuration and validates that configuration with the package turned on. Without `STABLEBAR`, it runs only the file checks.

To try the package on your own bar, install it from its folder in **Settings → Packages → Open a folder…**. Give any other StableBar command `--config` with a scratch file: without it, the command changes your own configuration.

## How we work

1. **One package per pull request.** Changes to CI, scripts or these guides get their own.
2. **Branch and open a pull request.** Nobody pushes to `main`, since every push to `main` publishes. Fill in the template: what the package does, what changed, the access it needs and how you tested it. Upload screenshots of the widget and its popup to the pull request.
3. **Title it in [Conventional Commits](https://www.conventionalcommits.org) and plain words,** such as `feat: add a Weather package` or `fix: keep Weather working without a location`. Link the issue it closes, if there is one.
4. **Wait for CI.** `Lint` and `Validate` must pass.
5. **Review.** Themes and widget packages merge once CI passes. A package that runs commands waits for a maintainer to read every script and command string and check them against `requires`, `permissions` and `hosts`. This holds for every new version, however small the change.

Package ideas and bugs in a package go in [issues](https://github.com/Seb-GRAF/stablebar-packages/issues/new/choose). Bugs in StableBar itself go to [StableBar's issues](https://github.com/Seb-GRAF/StableBar/issues).

## What CI checks

On every pull request and push to `main`:

- **Lint:** ShellCheck on every `.sh` file, the package list in the README, and on pull requests `scripts/check-versions.sh`, which requires a new version for every package that changed.
- **Validate:** builds the current StableBar `main` and runs `scripts/check-package.sh` on every package: the folder name matches the `id`, the file rules above, `--inspect-package`, `--install-package` into a scratch configuration, and `--validate` with the package enabled.
- **Publish:** on `main` only, after both. `scripts/build-index.sh` writes `index.json` and a `<id>-<version>.tar.gz` archive for each new version, and uploads them to the `store` prerelease. A version already in the index keeps its archive and checksum. StableBar reads the index at `https://github.com/Seb-GRAF/stablebar-packages/releases/download/store/index.json`.

## Agent skills

Skills for coding agents live in [.agents/skills](.agents/skills), and `.claude/skills` links to it for Claude Code. [AGENTS.md](AGENTS.md) holds the rest of what agents need.

| Skill | Use |
| --- | --- |
| [review-package](.agents/skills/review-package/SKILL.md) | Reads a package or a pull request the way the store's review needs: every command, what it reaches and what it declares. It reports; it never approves or merges. |

## Security

Report a harmful package privately, as described in [SECURITY.md](.github/SECURITY.md).
