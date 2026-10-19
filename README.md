# StableBar packages

The store for [StableBar](https://github.com/Seb-GRAF/StableBar): themes and widget packages that anyone can add through a pull request. Every package is open source, reviewed here, and published by this repository's CI rather than by its author.

## How StableBar uses the store

On every push to `main`, CI publishes the `store` release of this repository. It holds an `index.json` listing each package's current version, and one `<id>-<version>.tar.gz` archive for every version ever published. StableBar reads the index at `https://github.com/Seb-GRAF/stablebar-packages/releases/download/store/index.json`, downloads an archive, checks it against the SHA-256 in the index, reviews it with the same code that reviews a local folder, and installs it. Installing never enables a package. The index also links each version's source commit.

A published id and version never change, and their archives are never deleted. The index lists only each package's current version. A version you installed stays on your Mac until you remove it, so a configuration that pins it keeps working.

## Notifications and development tools

- [Dock badges](packages/dock-badges/README.md) totals unread badges from selected running apps.
- [Agent status](packages/agent-status/README.md) shows Claude Code waiting or finishing and Codex finishing; follow its hook setup after installing.
- [Development servers](packages/dev-servers/README.md) lists your listening ports, opens localhost and stops processes.

## Add or update a package

Open a pull request that adds or changes one folder in `packages/`. The folder name equals the manifest `id`:

```text
packages/weather/
  package.json
  config.json
  screenshot.png
  scripts/weather.sh
```

`package.json` is the manifest described in StableBar's [Local widget packages](https://github.com/Seb-GRAF/StableBar#local-widget-packages) and [Themes](https://github.com/Seb-GRAF/StableBar#themes) sections. Besides `id`, `name`, `version`, `entry` and `settings`, the store reads these keys. All are optional:

| Key | Meaning |
| --- | --- |
| `kind` | `theme` or `widgets`. Leave it out for a package that runs commands. |
| `description` | One sentence for the store and the review. |
| `author` | A person, organization or handle. |
| `repository` | The `https` URL of the package's source. |
| `screenshot` | Path inside the package to a PNG or JPEG. |
| `minimumVersion` | The oldest StableBar version that can run it, such as `0.6.0`. |
| `requires` | Command-line tools needed on the login shell's PATH, such as `jq` or `gh`. |
| `permissions` | macOS permissions: `calendars`, `automation`, `accessibility`, `bluetooth` or `location`. |
| `hosts` | Hostnames the package contacts, such as `api.github.com`. |

Declare what the package needs. A maintainer compares `requires`, `permissions` and `hosts` with the code.

Any change to a package needs a new `version`, even a fix to its description or screenshot. CI rejects a pull request that changes a package and keeps its version. Published versions are never replaced.

Keep packages small and readable. Files can be at most 1 MiB. Binaries are not accepted; images must be `.png`, `.jpg` or `.jpeg`. A file other than JSON can't have a line over 300 characters, so minified code is rejected. Symlinks are rejected, and an executable file starts with a shebang. Shell scripts end in `.sh` and pass [ShellCheck](https://www.shellcheck.net), so they use `sh` or `bash`.

## Kinds and review

| Kind | Manifest | Review |
| --- | --- | --- |
| Theme | `"kind": "theme"` | CI only. A theme contains tokens and style defaults, and runs no commands. |
| Widgets | `"kind": "widgets"` | CI only. The package contains no commands, and StableBar rejects any configuration that has one. |
| Commands | no `kind` | CI, then a maintainer reads the code. This happens for each new package and each update. |

A package with commands runs code as the user who installs it. A maintainer reads every script and every command string, and checks them against `requires`, `permissions` and `hosts`, before merging. Pull requests that change such a package wait for that review, however small the change.

## Test a package locally

Build StableBar, then use its command line with a scratch configuration. Never run these commands without `--config`: they would change your own configuration. None of them starts the bar.

```sh
StableBar=path/to/StableBar.app/Contents/MacOS/StableBar
scratch=$(mktemp -d)

$StableBar --config "$scratch/config.json" --inspect-package packages/nord
$StableBar --config "$scratch/config.json" --install-package packages/nord
```

Enable the installed package in the scratch configuration and validate it. For a theme:

```sh
echo '{ "theme": { "id": "nord", "version": "1.0.0" } }' > "$scratch/config.json"
$StableBar --validate "$scratch/config.json"
```

Any other package goes in `packages`:

```sh
echo '{ "packages": [{ "id": "weather", "version": "1.0.0" }] }' > "$scratch/config.json"
$StableBar --validate "$scratch/config.json"
```

`scripts/check-package.sh` does all of this, after the file checks CI makes:

```sh
STABLEBAR=path/to/StableBar.app/Contents/MacOS/StableBar scripts/check-package.sh packages/nord
```

Without `STABLEBAR`, it runs only the file checks.

## What CI checks

On every pull request and push to `main`:

- **Lint:** ShellCheck on every `.sh` file, and on pull requests `scripts/check-versions.sh`, which requires a new version for every package that changed.
- **Validate:** builds the current StableBar `main` and runs `scripts/check-package.sh` on every package: the folder name matches the `id`, the file rules above, `--inspect-package`, `--install-package` into a scratch configuration, and `--validate` with the package enabled.
- **Publish:** on `main` only, after both. `scripts/build-index.sh` writes the index and an archive for each new version. A version already in the index keeps its archive and checksum.

## License

[MIT](LICENSE)
