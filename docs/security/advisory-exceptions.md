# Advisory exceptions

This file records every security advisory that this repo's audit gates allow.

**Policy**

- Every allow-listed advisory has a section here.
- Both allow-lists link the section: `hex: [ignore_advisories: ...]` in `mix.exs` (gate `audit:hex`) and `.mix-audit-ignore` (gate `audit:deps`).
- An advisory is allow-listed only when no fixed release exists. Update the dependency instead whenever a fix ships.
- Each section names its tracking issue.
- A section begins with a level-2 heading equal to the allow-list ID. Use the GHSA ID when the advisory has one. The anchor is the lower-cased ID.
- Each section holds these level-3 subsections, in this order:
  1. Advisory
  2. Exposure
  3. Spoofing
  4. Tampering
  5. Repudiation
  6. Information disclosure
  7. Denial of service
  8. Elevation of privilege
  9. Likelihood and impact
  10. Existing mitigations
  11. Residual risk
  12. Review trigger
  13. Owner
  14. Tracking
- A STRIDE category that does not apply says "Not applicable" and gives the reason.
- The owner is the repo maintainer (vinnie357) unless the section names someone else.
- Each section carries exactly one `Reviewed: YYYY-MM-DD` line and one `Next review: YYYY-MM-DD` line, at most 90 days apart. The owner reviews each section by that date, or at any listed review trigger, whichever comes first.
- A review edits the section in place and overwrites both dates. Git history is the record of past reviews; keep no review logs or dated copies.
- CI (`mise run audit:advisory-doc`) fails once a `Next review` date has passed, so a lapsed review blocks merges until it is redone.
- Remove the section and both allow-list entries when the advisory no longer matches the lock. Both gates fail on a stale entry.

No exceptions are allow-listed.
