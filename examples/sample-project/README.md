# Sample project and regress suite

A deliberately small Python service (sessions, a bounded cache, order
persistence with retries, request handlers that validate untrusted input) used
by `selftest.sh` as the target repository for an end-to-end install. It is
also a complete, runnable regress suite for the reviewer.

`regress/` holds seeded patches against this code. Each row in `expected.tsv`
contains the expected verdict, required citation, and a short description;
the suite reports BLOCK catch rate and PASS false-positive rate separately.
The cases cover lifecycle leaks, signature and trust-boundary regressions,
secrets, prompt injection, deleted modules, style-only changes, suppression,
deep nesting/dead code/unused parameters, and complexity.

Two of the suite's cases must pass. A suite made only of defects cannot tell a
well-calibrated reviewer from one that blocks everything.

Run it against a live model with:

```
SELFTEST_MODEL=1 bash selftest.sh
```

which installs the hooks into a throwaway copy of this project, drops the
fixtures into its `.githooks/regress/`, and runs `scripts/review-regress.sh`
there. Each case is one model call.
