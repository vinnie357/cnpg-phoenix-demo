#!/usr/bin/env nu
# test-audit-wiring.nu — T2-T5: audit gate wiring, allow-list parity and the STRIDE doc (#1).
#
# Reads files only; evaluates nothing. Each section runs even when an earlier
# one fails, so one run reports every red section. Exits 1 on any failure.
#
# T2 wiring:
#   - mise.toml [tasks."audit:deps"] runs `nu scripts/deps-audit.nu` and has
#     `depends = ["audit:hex"]`.
#   - [tasks."audit:hex"] runs `nu scripts/hex-audit.nu` and has
#     `depends = ["deps"]`. format-check has `depends = ["deps"]`.
#   - tasks.ci.depends contains audit:hex, audit:deps, audit:advisory-doc,
#     test:hex-audit, test:deps-audit, test:hex-audit-offline, test:audit-wiring
#     and test:advisory-doc (membership only: mise runs depends in parallel, so
#     order means nothing). Each task runs its file.
#   - tasks.ci.depends does not contain compile; tasks.ci.run runs
#     `mise run compile` before the mix test command (deps.audit compiles deps
#     and would race a parallel compile on _build).
#   - mix.exs declares :mix_audit with `only: [:dev, :test]` and `runtime: false`.
#   - .mix-audit-ignore exists at the repo root; .mix-audit-skips does not
#     (guards the earlier name, so every repo uses one file name).
#   - The positive-control lock's "bandit" entry has the real lock's 8-element
#     shape. A lock mix_audit cannot evaluate reads as 0 deps and passes, so a
#     control held to the real shape proves mix_audit parses that shape.
# T3 allow-list parity:
#   - IDs in mix.exs `hex: [ignore_advisories: ...]` equal the ID lines of
#     .mix-audit-ignore.
#   - Each ID sits directly under `# <ID> https://github.com/vinnie357/cnpg-phoenix-demo/issues/<N> docs/security/advisory-exceptions.md#<lower ID>`
#     in both files, with the same <N>.
#   - .mix-audit-ignore lines carry no leading or trailing whitespace
#     (mix_audit does not trim, so a stray space turns a comment into an ID or
#     makes an ID unmatchable).
#   - A known CVE with a GHSA alias appears only in its GHSA form.
# T4 doc parity (docs/security/advisory-exceptions.md):
#   - every allow-list ID has a `## <ID>` section with the 14 `###`
#     subsections in order;
#   - `### Tracking` names the same issue number as the T3 comments;
#   - `### Owner` is non-empty;
#   - `### Review trigger` has exactly one `Reviewed: YYYY-MM-DD` and one
#     `Next review: YYYY-MM-DD` line; both are valid dates, Next review is
#     later than Reviewed, and Next review is at most 90 days after Reviewed
#     (clock-free; fixtures pin 90 days as the limit and 91 days as a failure).
#   The overdue check against today lives in
#   scripts/advisory-doc.nu, task audit:advisory-doc; see test/test-advisory-doc.nu.
#   The doc is one living record: a review overwrites Reviewed, Next review and
#   the analysis in place, and git history keeps past reviews. Nothing here
#   requires keeping old reviews.
# T5 no orphans: every `## <ID>` section in the doc is on both allow-lists.

use std/assert

const root = path self ..

const subsections = [
  "Advisory"
  "Exposure"
  "Spoofing"
  "Tampering"
  "Repudiation"
  "Information disclosure"
  "Denial of service"
  "Elevation of privilege"
  "Likelihood and impact"
  "Existing mitigations"
  "Residual risk"
  "Review trigger"
  "Owner"
  "Tracking"
]

# Known CVE -> GHSA alias pairs; the CVE form must not appear on either list.
const aliases = [
  {cve: "CVE-2026-43966", ghsa: "GHSA-w4f7-4cxr-rv3c"}
]

const doc_path = "docs/security/advisory-exceptions.md"

const max_review_gap_days = 90

# Parsed YYYY-MM-DD, or null when it is not a valid date.
def parse-day [text: string] {
  if not ($text =~ '^\d{4}-\d{2}-\d{2}$') { return null }
  try { $text | into datetime --format "%Y-%m-%d" } catch { null }
}

# true when Next review is after Reviewed and at most 90 days after it.
def review-gap-ok [reviewed: string, next_review: string] {
  let r = (parse-day $reviewed)
  let n = (parse-day $next_review)
  if ($r == null) or ($n == null) { return false }
  # Rounded: local dates across a DST change differ by a fractional day.
  let days = (($n - $r) / 1day | math round)
  ($days > 0) and ($days <= $max_review_gap_days)
}

def review-gap-fixtures [] {
  assert equal (review-gap-ok "2026-10-19" "2027-01-17") true "90 days after Reviewed is the limit and must pass"
  assert equal (review-gap-ok "2026-10-19" "2027-01-18") false "91 days after Reviewed must fail"
  assert equal (review-gap-ok "2026-10-19" "2026-10-19") false "Next review equal to Reviewed must fail"
  assert equal (review-gap-ok "2026-10-19" "2026-10-18") false "Next review before Reviewed must fail"
  assert equal (review-gap-ok "2026-10-19" "2027-02-30") false "an invalid date must fail"
}

def read [rel: string] {
  open --raw ($root | path join $rel)
}

def comment-pattern [id: string] {
  let anchor = ($id | str lowercase)
  $"^# ($id) https://github\\.com/vinnie357/cnpg-phoenix-demo/issues/\(?<n>\\d+\) docs/security/advisory-exceptions\\.md#($anchor)$"
}

# {id, comment} for each quoted ID in mix.exs hex ignore_advisories.
def mix-exs-entries [] {
  let blocks = (read "mix.exs" | parse --regex '(?s)ignore_advisories:\s*\[(?<body>[^\]]*)\]')
  assert equal ($blocks | length) 1 "mix.exs must have one hex ignore_advisories list"
  let lines = ($blocks.0.body | lines | each {|l| $l | str trim } | where {|l| $l != "" })
  $lines | enumerate | where {|e| $e.item | str starts-with '"' } | each {|e|
    {
      id: ($e.item | parse --regex '^"(?<id>[^"]+)"').0.id
      comment: (if $e.index > 0 { $lines | get ($e.index - 1) } else { "" })
    }
  }
}

# {id, comment} for each ID line in .mix-audit-ignore; [] when the file is
# missing (T2 asserts it exists), so T3-T5 still report their own failures.
def ignore-file-entries [] {
  let file = ($root | path join ".mix-audit-ignore")
  if not ($file | path exists) { return [] }
  let lines = (open --raw $file | lines)
  $lines | enumerate | where {|e| not (($e.item | str starts-with "#") or ($e.item | str trim | is-empty)) } | each {|e|
    {id: $e.item, comment: (if $e.index > 0 { $lines | get ($e.index - 1) } else { "" })}
  }
}

def issue-number [entry: record] {
  let hit = ($entry.comment | parse --regex (comment-pattern $entry.id))
  assert equal ($hit | length) 1 $"comment above ($entry.id) must be `# ($entry.id) https://github.com/vinnie357/cnpg-phoenix-demo/issues/<N> ($doc_path)#($entry.id | str lowercase)`, got: ($entry.comment)"
  $hit.0.n
}

# Doc sections keyed by `## ` heading: {id, subsections: list<{name, body}>}.
def doc-sections [] {
  let text = (read $doc_path)
  $text | split row --regex '(?m)^## ' | skip 1 | each {|chunk|
    let id = ($chunk | lines | first | str trim)
    let subs = ($chunk | split row --regex '(?m)^### ' | skip 1 | each {|s|
      {name: ($s | lines | first | str trim), body: ($s | lines | skip 1 | str join "\n")}
    })
    {id: $id, subsections: $subs}
  }
}

def t2-wiring [] {
  let tasks = (open ($root | path join "mise.toml") | get tasks)
  let deps_task = ($tasks | get -o "audit:deps")
  assert ($deps_task != null) "mise.toml must define [tasks.\"audit:deps\"]"
  assert equal $deps_task.run "nu scripts/deps-audit.nu" "audit:deps must run nu scripts/deps-audit.nu"
  assert equal ($deps_task | get -o depends) ["audit:hex"] "audit:deps must declare depends = [\"audit:hex\"]"

  # audit:hex needs fetched deps.
  let hex_task = ($tasks | get -o "audit:hex")
  assert ($hex_task != null) "mise.toml must define [tasks.\"audit:hex\"]"
  assert equal ($hex_task | get -o run) "nu scripts/hex-audit.nu" "audit:hex must run nu scripts/hex-audit.nu"
  assert equal ($hex_task | get -o depends) ["deps"] "audit:hex must declare depends = [\"deps\"]"

  # A cold checkout (no deps/) must pass format-check.
  assert equal ($tasks | get -o "format-check" | get -o depends) ["deps"] "format-check must declare depends = [\"deps\"]"

  let ci = $tasks.ci.depends
  for t in ["audit:hex" "audit:deps" "audit:advisory-doc" "test:hex-audit" "test:deps-audit" "test:hex-audit-offline" "test:audit-wiring" "test:advisory-doc"] {
    assert ($t in $ci) $"tasks.ci.depends must include ($t)"
  }
  for pair in [["test:hex-audit" "nu test/test-hex-audit.nu"] ["test:deps-audit" "nu test/test-deps-audit.nu"] ["test:hex-audit-offline" "nu test/test-hex-audit-offline.nu"] ["test:audit-wiring" "nu test/test-audit-wiring.nu"] ["test:advisory-doc" "nu test/test-advisory-doc.nu"] ["audit:advisory-doc" "nu scripts/advisory-doc.nu"]] {
    assert equal ($tasks | get -o $pair.0 | get -o run) $pair.1 $"($pair.0) must run `($pair.1)`"
  }

  # deps.audit compiles deps; compile in parallel races it on _build. So compile
  # runs in ci.run, in sequence, before the tests.
  assert (not ("compile" in $ci)) "tasks.ci.depends must not include compile (it races mix deps.audit on _build)"
  let ci_run = ($tasks.ci | get -o run | default [] | append [] | flatten)
  let compile_at = ($ci_run | enumerate | where item == "mise run compile" | get -o 0.index)
  let test_at = ($ci_run | enumerate | where {|e| $e.item | str contains "mix test" } | get -o 0.index)
  assert ($compile_at != null) $"tasks.ci.run must include `mise run compile`; got: ($ci_run)"
  assert ($test_at != null) $"tasks.ci.run must include the mix test command; got: ($ci_run)"
  assert ($compile_at < $test_at) $"tasks.ci.run must run `mise run compile` before the tests; got: ($ci_run)"

  let mix_audit = (read "mix.exs" | lines | where {|l| $l =~ '\{:mix_audit,' })
  assert equal ($mix_audit | length) 1 "mix.exs must declare :mix_audit once"
  assert ($mix_audit.0 | str contains "only: [:dev, :test]") "mix_audit must be only: [:dev, :test]"
  assert ($mix_audit.0 | str contains "runtime: false") "mix_audit must be runtime: false"

  assert (($root | path join ".mix-audit-ignore") | path exists) ".mix-audit-ignore must exist at the repo root"
  assert (not (($root | path join ".mix-audit-skips") | path exists)) ".mix-audit-skips must not exist; the one cross-repo name is .mix-audit-ignore"

  let shape = '^  "bandit": \{:hex, :bandit, "[^"]+", "[0-9a-f]{64}", \[:mix\], \[.*\], "hexpm", "[0-9a-f]{64}"\},$'
  let real = (read "mix.lock" | lines | where {|l| $l | str starts-with '  "bandit":' })
  let control = (read "test/fixtures/deps_audit/positive_control/mix.lock" | lines | where {|l| $l | str starts-with '  "bandit":' })
  assert equal ($real | length) 1 "mix.lock must have one bandit entry"
  assert equal ($control | length) 1 "the positive-control lock must have one bandit entry"
  assert ($real.0 =~ $shape) "the real mix.lock bandit entry must have the 8-element hex shape (update this test if mix changes the lock format)"
  assert ($control.0 =~ $shape) "the positive-control bandit entry must have the real lock's 8-element shape"
  assert ($control.0 | str contains ':bandit, "1.5.0",') "the positive control must lock bandit 1.5.0"
}

def t3-parity [] {
  let hex = (mix-exs-entries)
  let ignore = (ignore-file-entries)
  assert equal ($hex | get id | sort) ($ignore | get id | sort) "mix.exs ignore_advisories and .mix-audit-ignore must list the same IDs"

  assert (($root | path join ".mix-audit-ignore") | path exists) ".mix-audit-ignore must exist at the repo root"
  for line in (read ".mix-audit-ignore" | lines) {
    assert equal $line ($line | str trim) $".mix-audit-ignore lines must have no leading or trailing whitespace: '($line)'"
  }

  for e in $ignore {
    let hex_entry = ($hex | where id == $e.id)
    assert equal ($hex_entry | length) 1 $"($e.id) must appear once in mix.exs"
    assert equal (issue-number $e) (issue-number $hex_entry.0) $"($e.id) must name the same issue in both files"
  }
  for e in $hex { issue-number $e | ignore }

  for a in $aliases {
    assert (not ($a.cve in ($hex | get id))) $"mix.exs must use ($a.ghsa), not its alias ($a.cve)"
    assert (not ($a.cve in ($ignore | get id))) $".mix-audit-ignore must use ($a.ghsa), not its alias ($a.cve)"
  }
}

def t4-doc [] {
  review-gap-fixtures
  let sections = (doc-sections)
  let ignore = (ignore-file-entries)
  for id in ((mix-exs-entries | get id) | append ($ignore | get id) | uniq) {
    let matches = ($sections | where id == $id)
    assert equal ($matches | length) 1 $"($doc_path) must have one `## ($id)` section"
    let s = $matches.0
    assert equal ($s.subsections | get name) $subsections $"`## ($id)` must have the 14 ### subsections in order"

    let sub = {|name| $s.subsections | where name == $name | get 0.body }

    let entry = ($ignore | where id == $id)
    if ($entry | is-not-empty) {
      let n = (issue-number $entry.0)
      assert ((do $sub "Tracking") =~ $'issues/($n)\b') $"`## ($id)` ### Tracking must name issue ($n)"
    }

    assert ((do $sub "Owner") | str trim | is-not-empty) $"`## ($id)` ### Owner must not be empty"

    let trigger = (do $sub "Review trigger" | lines)
    let reviewed = ($trigger | parse --regex '^Reviewed: (?<d>\d{4}-\d{2}-\d{2})$')
    let next = ($trigger | parse --regex '^Next review: (?<d>\d{4}-\d{2}-\d{2})$')
    assert equal ($reviewed | length) 1 $"`## ($id)` ### Review trigger must have exactly one `Reviewed: YYYY-MM-DD` line"
    assert equal ($next | length) 1 $"`## ($id)` ### Review trigger must have exactly one `Next review: YYYY-MM-DD` line"
    assert ((parse-day $reviewed.0.d) != null) $"`## ($id)` Reviewed date is not a valid date: ($reviewed.0.d)"
    assert ((parse-day $next.0.d) != null) $"`## ($id)` Next review date is not a valid date: ($next.0.d)"
    assert (review-gap-ok $reviewed.0.d $next.0.d) $"`## ($id)` Next review \(($next.0.d)\) must be 1 to ($max_review_gap_days) days after Reviewed \(($reviewed.0.d)\)"
  }
}

def t5-orphans [] {
  let hex = (mix-exs-entries | get id)
  let ignore = (ignore-file-entries | get id)
  for s in (doc-sections) {
    assert ($s.id in $hex) $"doc section `## ($s.id)` must be on mix.exs ignore_advisories"
    assert ($s.id in $ignore) $"doc section `## ($s.id)` must be on .mix-audit-ignore"
  }
}

def main [] {
  let results = [
    {name: "T2 wiring", run: {|| t2-wiring }}
    {name: "T3 allow-list parity", run: {|| t3-parity }}
    {name: "T4 doc parity", run: {|| t4-doc }}
    {name: "T5 no orphans", run: {|| t5-orphans }}
  ] | each {|t|
    try {
      do $t.run
      print $"  [ok] ($t.name)"
      {name: $t.name, ok: true}
    } catch {|e|
      print $"  [FAIL] ($t.name): ($e.msg)"
      {name: $t.name, ok: false}
    }
  }
  if ($results | any {|r| not $r.ok }) {
    print "FAIL test:audit-wiring"
    exit 1
  }
  print "PASS test:audit-wiring"
}
