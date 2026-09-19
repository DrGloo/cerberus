## ADDED Requirements

### Requirement: An inline marker with a reason demotes a finding

A comment containing `review-ignore: <reason>` with a non-empty reason, on the cited line or the line immediately above it in the tree under review, SHALL demote any finding citing that line to WARN. The hook SHALL perform this after the reviewer answers, print the finding with the reason appended, and recompute the verdict. A BLOCK whose only blockers are demoted SHALL become a PASS. Probe suite: core-probes.

#### Scenario: Suppressed blocker
- **WHEN** the reviewer reports a BLOCKER at `a.lua:40` and line 39 contains `-- review-ignore: client-only VFX, no server effect`
- **THEN** the finding is printed as a WARN with the reason, and the commit passes

#### Scenario: Marker on the wrong line
- **WHEN** the marker is three lines above the cited line
- **THEN** the finding keeps its severity

### Requirement: A marker without a reason is a finding

A `review-ignore` marker with an empty reason SHALL NOT demote anything, and the hook SHALL add a WARN at that line saying a reason is required. Probe suite: core-probes.

#### Scenario: Bare marker
- **WHEN** a line reads `// review-ignore:` with nothing after it
- **THEN** the original finding stands and a WARN about the missing reason is added

### Requirement: The reviewer is told about the marker

The rubric SHALL describe the marker and instruct the reviewer to still report the finding, so the hook, not the model, decides. Probe suite: regress.

#### Scenario: Model sees a marker
- **WHEN** a fixture contains a suppressed defect
- **THEN** the expected verdict is PASS and the expected output contains the reason text
