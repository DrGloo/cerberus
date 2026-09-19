## ADDED Requirements

### Requirement: An inline marker with a reason demotes a finding

A comment containing `review-ignore: <reason>` with a non-empty reason, on the cited line or the line immediately above it **in the base revision** (HEAD for a staged diff, the range base for a range), SHALL demote any finding citing that line to WARN. The hook SHALL perform this after the reviewer answers, print the finding with the reason appended, and recompute the verdict. A BLOCK whose only blockers are demoted SHALL become a PASS. Probe suite: core-probes.

#### Scenario: Suppressed blocker
- **WHEN** the reviewer reports a BLOCKER at `a.lua:40`, and line 39 of `a.lua` in HEAD contains `-- review-ignore: client-only VFX, no server effect`
- **THEN** the finding is printed as a WARN with the reason, and the commit passes

#### Scenario: Marker on the wrong line
- **WHEN** the marker is three lines above the cited line
- **THEN** the finding keeps its severity

### Requirement: A marker added by the diff under review does not count

A marker that is not present in the base revision SHALL NOT demote any finding, even when the diff adds it on the cited line. The hook SHALL keep the finding's severity and add a WARN at the marker's line saying it takes effect only after it has been reviewed in. Probe suite: core-probes.

#### Scenario: Defect and excuse in one commit
- **WHEN** a staged diff adds a leaking connection and, on the line above, `-- review-ignore: intentional`
- **THEN** the BLOCKER stands, the commit is blocked, and a WARN names the unreviewed marker

#### Scenario: Excuse reviewed first
- **WHEN** the marker was committed and reviewed earlier, and a later diff triggers a finding on that line
- **THEN** the finding is demoted to WARN with the reason

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
