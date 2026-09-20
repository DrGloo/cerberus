# Finding Suppression

## Purpose
Define reviewed inline exceptions without allowing a change to excuse its own defect.

## Requirements

### Requirement: An inline marker with a reason demotes a finding
A `review-ignore: <reason>` comment on the cited line or immediately above it in the base revision SHALL demote a cited finding to WARN, print the reason, and recompute the verdict.

#### Scenario: Suppressed blocker
- **WHEN** the base revision contains `review-ignore: client-only VFX` on or above a cited blocker
- **THEN** the finding is printed as WARN with the reason and a blocker-only review becomes PASS.

#### Scenario: Marker on the wrong line
- **WHEN** the marker is three lines above the cited line
- **THEN** the finding keeps its severity.

### Requirement: A marker added by the diff under review does not count
A marker absent from the base revision SHALL NOT demote a finding. The hook SHALL retain the finding severity and add a WARN explaining that the marker takes effect only after review.

#### Scenario: Defect and excuse in one commit
- **WHEN** a staged diff adds both a defect and a marker
- **THEN** the blocker remains and the unreviewed marker is warned.

#### Scenario: Excuse reviewed first
- **WHEN** the marker was committed and reviewed before a later finding
- **THEN** the later finding is demoted to WARN with the reason.

### Requirement: A marker without a reason is a finding
A bare `review-ignore` marker SHALL not suppress a finding and SHALL add a WARN requiring a reason.

#### Scenario: Bare marker
- **WHEN** a marker has no text after `review-ignore:`
- **THEN** the original finding remains and a missing-reason WARN is added.

### Requirement: The reviewer is told about the marker
The rubric SHALL describe the marker and instruct the reviewer to report the finding anyway so the hook decides suppression.
