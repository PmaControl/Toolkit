# Repository Guidelines

## Project Structure & Module Organization
The root directory hosts task-focused provisioning scripts (`install-*.sh`, `migrate-*.sh`, `upgrade-test.sh`) that can be run directly on a jump host. Shared logic, colorized logging, SSH helpers, and reusable MySQL utilities live in `lib/6t-*.sh`; lean on these instead of re-implementing flags or retry loops. Environment templates belong in `config/` (e.g., `config/pmacontrol.json`), SQL assets in `sql/`, and pmacontrol-specific installers in `pmacontrol/`. Generated passwords stay under `password/`, while import/export payloads live in `import/` and `view/`.

## Build, Test, and Development Commands
- `./build.sh install-mariadb-server.sh` — flattens `include` directives so a single self-contained script can be shipped to remote hosts.
- `./install-cluster.sh -m "10.0.0.1,10.0.0.2" -p "10.0.0.10" -o "10.0.0.50"` — provisions a Galera cluster plus proxy hosts.
- `./pmacontrol/install.sh -c config/pmacontrol.json` — bootstraps pmacontrol using the templated inventory; copy the file per environment.
- `./mysql_sniffer.sh --help` or `./mysql_sniffer_v2.sh` — diagnose live traffic and redirect output to `head/` when sharing traces.

## Coding Style & Naming Conventions
Write POSIX-compliant Bash with `#!/bin/bash`, `set -euo pipefail`, and explicit `getopts` parsing at the top of every new script. Prefer hyphenated filenames and lowerCamelCase function names (`getProxy`, `isDevMounted`). Exported variables that behave as constants should be uppercase (`HTTP_PROXY`), and keep includes (`source lib/6t-include.sh`) grouped before any logic.

## Testing Guidelines
Scenario tests live both at the root (`test-galera.sh`, `test-proxy.sh`, `test.sh`) and under `lib/test/`. Mirror the `test-<scope>.sh` naming pattern and gate long-running lab work behind explicit host lists to avoid surprises. Use the fixtures in `lib/test/test-crc32-string` for unit-style checks, then run targeted integration suites via `./test-galera.sh` or `./test-proxy.sh` once VPN access to the lab (10.68.68.0/24) is confirmed. Capture logs with `./mysql_sniffer_ascii.sh` when debugging replication issues to attach to bug reports.

## Commit & Pull Request Guidelines
Recent history favors short, imperative commit subjects ("add port for restore"). Follow that style, reference tickets when applicable, and keep each commit focused on a single tool or scenario. PRs should describe the environment tested, include the exact command invocation, and link to any pmacontrol issue or runbook page. Attach screenshots or log excerpts when touching installer flows or sniffer output formatting.

## Security & Configuration Tips
Never commit live credentials: keep redacted placeholders like `{%IP%}` and `secret_password` in `config/pmacontrol.json`. Store encrypted secrets in `password/` and share decryption steps out of band. Before running installers, export `http_proxy/https_proxy` as shown in `install-mariadb-server.sh`, and scrub generated archives from `head/` or `view/` before opening a PR.
