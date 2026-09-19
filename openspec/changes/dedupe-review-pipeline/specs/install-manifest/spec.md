## ADDED Requirements

### Requirement: The manifest is the only file list

`MANIFEST` SHALL list every installed path with a kind: `hook`, `lib`, `script`, `probe`, `settings`, `seed`. `install.sh` SHALL copy exactly the manifest's non-seed paths, the workflows SHALL syntax-check and exec-check from it, `selftest.sh` SHALL verify each installed path from it, and a guard probe SHALL assert every `hook`, `lib`, `script`, `probe` and `settings` path is refused as a write target. Probe suite: guard-probes, selftest.

#### Scenario: New script added
- **WHEN** a path is added to the manifest but not to the guard's protected set
- **THEN** guard-probes fails naming the path

#### Scenario: Install from the manifest
- **WHEN** a repository is installed
- **THEN** the set of files under `.githooks/` and `scripts/` equals the manifest's non-seed paths plus the created seeds

### Requirement: Installs are versioned

`VERSION` SHALL be copied to `.githooks/VERSION` on install. A second install without a flag SHALL report both versions and refuse. `--upgrade` SHALL replace manifest paths only, leave seeds, and print what changed between versions from the CHANGELOG when present. Probe suite: selftest.

#### Scenario: Older install
- **WHEN** a repository carries version 0.1.0 and the source is 0.2.0
- **THEN** the plain install refuses with both versions named and `--upgrade` succeeds
