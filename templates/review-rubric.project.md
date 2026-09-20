## Project rules: <your project>

<!--
Copy this file to .githooks/review-rubric.project.md and fill it in. It is
spliced into the generic rubric before the output contract, so the reviewer
reads it as part of the same instructions. Keep it short and concrete: name
the modules, the owners, and the exact patterns. Vague rules produce vague
findings.

Good things to put here:
  which key or field names must never change.
  through, so a new endpoint without them is a BLOCKER by name.
  shape, deprecated APIs and their replacements).
  is a WARN, and what looks minor but is a BLOCKER.
Write checkable rules as "flag any X that does Y" or "every X must Y". Name
the concrete module, handler, field, or resource involved and the observable
condition that makes it a finding. Keep rules to behaviour the configured
linters cannot enforce.

Examples, one for each generic BLOCKER class:
- **Leak:** flag any subscription, timer, or per-user entry that has no cleanup
  on every exit path.
- **Regression:** flag any changed function signature whose callers still use
  the old argument order or return shape.
- **Data loss:** flag any persistence write that changes a key or field without
  a migration or preserves a partial value after a failed save.
- **Unhandled failure:** flag any network, storage, or external-input call
  whose failure or invalid value reaches the success path unchecked.
- **Security:** flag any external entry point that accepts authority, price,
  quota, or reward from the caller without server-side validation.
- **Secret:** flag any source line containing a live credential, token, or
  private endpoint.

Add project-specific rules below in the same form:

- <flag any X that does Y>
- <every X must Y>
- <rule>
- <rule>
