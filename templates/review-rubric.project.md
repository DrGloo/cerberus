## Project rules: <your project>

<!--
Copy this file to .githooks/review-rubric.project.md and fill it in. It is
spliced into the generic rubric before the output contract, so the reviewer
reads it as part of the same instructions. Keep it short and concrete: name
the modules, the owners, and the exact patterns. Vague rules produce vague
findings.

Good things to put here:
- The lifecycle owner every resource must be registered with, by name.
- Which module owns persistence, what the schema migration path is, and
  which key or field names must never change.
- The validation helper and the wrapper every external entry point must go
  through, so a new endpoint without them is a BLOCKER by name.
- Conventions a linter cannot catch (indentation, guarded imports, logging
  shape, deprecated APIs and their replacements).
- Third-party or vendored directories and what changing them means.
- Severity calibrations specific to this codebase: what looks scary here but
  is a WARN, and what looks minor but is a BLOCKER.
-->

- <rule>
- <rule>
