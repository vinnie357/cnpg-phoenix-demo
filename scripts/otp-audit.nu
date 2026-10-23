#!/usr/bin/env nu
# otp-audit.nu: gate the Erlang/OTP and Elixir versions (task audit:otp; #9).
#
# Fails when any of these is below the OTP floor, or differs from the mise.toml erlang pin:
#   - the mise.toml `[tools] erlang` pin (must be a numeric string; a list or `latest` FAILs);
#   - the running ERTS, read from releases/<otp_release>/OTP_VERSION under code:root_dir()
#     (otp_release alone is the major, "28", and cannot see the patch level);
#   - the release image's OTP, read from the Dockerfile's `ARG OTP_VERSION=` default.
# Also fails when the mise.toml `[tools] elixir` pin or the Dockerfile `ARG ELIXIR_VERSION=`
# default is below the Elixir floor or they disagree, or when the elixir pin's `-otp-<M>` suffix
# does not match the erlang pin's major. There is no Elixir runtime probe: mise installs the pin.
#
# Why the ARG default is trusted: the Dockerfile builds from `FROM ${BUILDER_IMAGE}`, and
# BUILDER_IMAGE embeds `elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}`. A --build-arg could override that default, but
# .github/workflows/release.yml is the only image build path and its build-args pass none of
# OTP_VERSION, ELIXIR_VERSION, DEBIAN_VERSION, BUILDER_IMAGE or RUNNER_IMAGE (asserted by T6 in
# test/test-audit-wiring.nu). So the default is what ships.
# Fails closed: an unreadable pin or runtime, zero or several `ARG OTP_VERSION=` lines, a value
# built from another `$ARG`, or a builder image / FROM line that does not use OTP_VERSION is a FAIL.
# Every reason is listed in one FAIL line. Comparison is numeric per component, never by string.
#
# Tests: test/test-otp-audit.nu (decision defs and main, with a fake erl on PATH).

const repo = (path self | path dirname | path dirname)
# CVE-2026-55953 is fixed in OTP 28.5.0.4 and CVE-2026-89422 in OTP 28.5.0.7.
# The floor is the pinned 28.5.0.8 (#9). Raising it is a one-line change here.
const otp_floor = "28.5.0.8"
# The Elixir floor is the pinned 1.19.6 (#9).
const elixir_floor = "1.19.6"
const erl_eval = 'F = filename:join([code:root_dir(), "releases", erlang:system_info(otp_release), "OTP_VERSION"]), case file:read_file(F) of {ok, B} -> io:put_chars(B), halt(0); E -> io:format(standard_error, "~p~n", [E]), halt(1) end.'

def version-parts [version: string]: nothing -> list<int> {
  $version | split row "." | each {|part| $part | into int }
}

# true when version a is below version b, comparing components as integers.
# Raises on any non-numeric component, in either argument.
export def version-below [a: string, b: string]: nothing -> bool {
  let pa = (version-parts $a)
  let pb = (version-parts $b)
  let width = ([($pa | length) ($pb | length)] | math max)
  for i in 0..<$width {
    let x = ($pa | get -o $i | default 0)
    let y = ($pb | get -o $i | default 0)
    if $x < $y { return true }
    if $x > $y { return false }
  }
  false
}

# tools.erlang from a parsed mise.toml: a string as is, a record's `version`; null otherwise.
export def erlang-pin [mise_toml: record] {
  let value = ($mise_toml | get -o tools | default {} | get -o erlang)
  match ($value | describe) {
    "string" => $value
    $t if ($t | str starts-with "record") => {
      let version = ($value | get -o version)
      if ($version | describe) == "string" { $version } else { null }
    }
    _ => null
  }
}

# tools.elixir from a parsed mise.toml, same rules as erlang-pin ("1.19.6-otp-28" as is).
export def elixir-pin [mise_toml: record] {
  let value = ($mise_toml | get -o tools | default {} | get -o elixir)
  match ($value | describe) {
    "string" => $value
    $t if ($t | str starts-with "record") => {
      let version = ($value | get -o version)
      if ($version | describe) == "string" { $version } else { null }
    }
    _ => null
  }
}

# First whitespace-separated token of an OTP_VERSION file ("28.5.0.8 **\n" -> "28.5.0.8").
export def otp-version-from-file [text: string]: nothing -> string {
  let trimmed = ($text | str trim)
  if $trimmed == "" { "" } else { $trimmed | split row --regex '\s+' | first }
}

def strip-quotes [value: string]: nothing -> string {
  $value | str trim --char '"'
}

# Non-comment lines with their 1-based numbers.
def code-lines [text: string]: nothing -> list<record<line: int, text: string>> {
  $text | lines | enumerate | each {|e| {line: ($e.index + 1), text: ($e.item | str trim)} }
    | where {|l| not ($l.text | str starts-with "#") }
}

# One literal `ARG <name>=` default: {line, v, reason}. v is null (fail closed) and reason says
# why unless exactly one such line exists and its value has no `$`. line is 0 unless exactly one.
def single-arg [code: list, name: string]: nothing -> record {
  let args = ($code | each {|l|
    let m = ($l.text | parse --regex $"^ARG ($name)=\(?<v>\\S+\)$")
    if ($m | is-empty) { null } else { {line: $l.line, v: (strip-quotes $m.0.v)} }
  } | compact)
  let n = ($args | length)
  if $n != 1 {
    return {line: 0, v: null, reason: $"expected exactly one ARG ($name)= line, found ($n)"}
  }
  let arg = $args.0
  if ($arg.v | str contains "$") {
    return {line: $arg.line, v: null, reason: $"ARG ($name) value is built from another ARG: ($arg.v)"}
  }
  {line: $arg.line, v: $arg.v, reason: ""}
}

# The release image's OTP and Elixir from the single `ARG OTP_VERSION=` and `ARG ELIXIR_VERSION=`
# defaults. Both are null (fail closed) unless BUILDER_IMAGE's default embeds
# `elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}` and a `FROM ${BUILDER_IMAGE}` line exists.
# Otherwise each is null, with its reason, unless its own ARG is exactly one literal default.
export def dockerfile-otp [file: string, text: string]: nothing -> record<file: string, line: int, image: string, otp: any, reason: string, elixir: any, elixir_line: int, elixir_reason: string> {
  let code = (code-lines $text)
  let builder = ($code | each {|l|
    let m = ($l.text | parse --regex '^ARG BUILDER_IMAGE=(?<v>\S+)$')
    if ($m | is-empty) { null } else { strip-quotes $m.0.v }
  } | compact)
  let image = ($builder | get -o 0 | default "")
  let otp = (single-arg $code "OTP_VERSION")
  let elixir = (single-arg $code "ELIXIR_VERSION")
  let from = ($code | any {|l| $l.text =~ '(?i)^FROM\s+\$\{BUILDER_IMAGE\}(\s|$)' })
  let link = if not ($image | str contains 'elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}') {
    'builder image does not use OTP_VERSION/ELIXIR_VERSION: BUILDER_IMAGE default lacks elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}'
  } else if not $from {
    "builder image does not use OTP_VERSION/ELIXIR_VERSION: no FROM ${BUILDER_IMAGE} line"
  } else {
    ""
  }
  let base = {file: $file, line: $otp.line, image: $image, elixir_line: $elixir.line}
  if $link != "" {
    return ($base | merge {otp: null, reason: $link, elixir: null, elixir_reason: $link})
  }
  $base | merge {otp: $otp.v, reason: $otp.reason, elixir: $elixir.v, elixir_reason: $elixir.reason}
}

def numeric [value]: nothing -> bool {
  if ($value | describe) != "string" { return false }
  try { version-below $value $value | ignore; true } catch { false }
}

# Reasons for one numeric version against the floor and (when numeric) the pin.
# subject names the version in the reason, e.g. "runtime 28.3.2".
def version-reasons [subject: string, version: string, floor: string, pin, pin_ok: bool]: nothing -> list<string> {
  let below = if (version-below $version $floor) { [$"($subject) below floor ($floor)"] } else { [] }
  let differs = if $pin_ok and ((version-below $version $pin) or (version-below $pin $version)) {
    [$"($subject) differs from pin ($pin)"]
  } else {
    []
  }
  $below | append $differs
}

# Decision for one audit. Never raises; pass is true exactly when reasons is empty.
export def otp-verdict [floor: string, pin, runtime, images: list]: nothing -> record<pass: bool, reasons: list<string>> {
  if not (numeric $floor) {
    return {pass: false, reasons: [$"floor not numeric: ($floor)"]}
  }
  let pin_ok = (numeric $pin)
  let pin_reasons = if not $pin_ok {
    [$"erlang pin missing or not numeric: ($pin)"]
  } else if (version-below $pin $floor) {
    [$"pin ($pin) below floor ($floor)"]
  } else {
    []
  }
  let runtime_reasons = if $runtime == null {
    ["runtime OTP version unreadable"]
  } else if not (numeric $runtime) {
    [$"runtime ($runtime) not numeric"]
  } else {
    version-reasons $"runtime ($runtime)" $runtime $floor $pin $pin_ok
  }
  let image_reasons = ($images | each {|i|
    let loc = $"($i.file):($i.line)"
    if $i.otp == null {
      let why = ($i | get -o reason | default "")
      if $why == "" { [$"cannot read OTP version from ($loc)"] } else { [$"cannot read OTP version from ($loc): ($why)"] }
    } else if not (numeric $i.otp) {
      [$"image ($loc) OTP ($i.otp) not numeric"]
    } else {
      version-reasons $"image ($loc) OTP ($i.otp)" $i.otp $floor $pin $pin_ok
    }
  } | flatten)
  let reasons = ($pin_reasons | append $runtime_reasons | append $image_reasons)
  {pass: ($reasons | is-empty), reasons: $reasons}
}

# Elixir decision. Never raises; pass is true exactly when reasons is empty.
# The pin's version is the text before the first `-` ("1.19.6-otp-28" -> "1.19.6").
export def elixir-verdict [floor: string, pin, erlang_pin, images: list]: nothing -> record<pass: bool, reasons: list<string>> {
  if not (numeric $floor) {
    return {pass: false, reasons: [$"elixir floor not numeric: ($floor)"]}
  }
  let version = if ($pin | describe) == "string" { $pin | split row "-" | first } else { null }
  let pin_ok = (numeric $version)
  let pin_reasons = if not $pin_ok {
    [$"elixir pin missing or not numeric: ($pin)"]
  } else if (version-below $version $floor) {
    [$"elixir pin ($version) below floor ($floor)"]
  } else {
    []
  }
  let suffix_reasons = if $pin_ok and (numeric $erlang_pin) {
    let major = ($erlang_pin | split row "." | first)
    if ($pin | str ends-with $"-otp-($major)") { [] } else { [$"elixir pin ($pin) does not match erlang major ($major)"] }
  } else {
    []
  }
  let image_reasons = ($images | each {|i|
    let loc = $"($i.file):($i.elixir_line)"
    if $i.elixir == null {
      let why = ($i | get -o elixir_reason | default "")
      if $why == "" { [$"cannot read Elixir version from ($loc)"] } else { [$"cannot read Elixir version from ($loc): ($why)"] }
    } else if not (numeric $i.elixir) {
      [$"image ($loc) Elixir ($i.elixir) not numeric"]
    } else {
      version-reasons $"image ($loc) Elixir ($i.elixir)" $i.elixir $floor $version $pin_ok
    }
  } | flatten)
  let reasons = ($pin_reasons | append $suffix_reasons | append $image_reasons)
  {pass: ($reasons | is-empty), reasons: $reasons}
}

def elixir-floor-default [] { $elixir_floor }

def main [--floor: string, --elixir-floor: string, --root: path, --image-file: string = "Dockerfile"] {
  let floor = ($floor | default $otp_floor)
  let efloor = ($elixir_floor | default (elixir-floor-default))
  let root = ($root | default $repo | path expand)

  let mise_file = ($root | path join "mise.toml")
  let mise_missing = not ($mise_file | path exists)
  let mise = if $mise_missing { null } else { try { open $mise_file } catch { null } }
  let pin = if $mise == null { null } else { erlang-pin $mise }
  let epin = if $mise == null { null } else { elixir-pin $mise }

  let image_path = if ($image_file | str starts-with "/") { $image_file } else { $root | path join $image_file }
  let image_found = ($image_path | path exists)
  let missing_files = if $image_found { [] } else { [$"image file not found: ($image_file)"] }
  let images = if $image_found { [(dockerfile-otp $image_file (open --raw $image_path))] } else { [] }

  let erl = (try {
    do { cd $root; ^erl -noshell -eval $erl_eval } | complete
  } catch {|e|
    {exit_code: 127, stdout: "", stderr: $e.msg}
  })
  let runtime = if $erl.exit_code == 0 and ($erl.stdout | str trim) != "" { otp-version-from-file $erl.stdout } else { null }
  let erl_reasons = if $runtime == null { [$"erl failed \(exit ($erl.exit_code)\): ($erl.stderr | str trim)"] } else { [] }
  let mise_reasons = if $mise_missing { [$"mise.toml not found: ($mise_file)"] } else { [] }

  let verdict = (otp-verdict $floor $pin $runtime $images)
  let everdict = (elixir-verdict $efloor $epin $pin $images)
  let reasons = ($mise_reasons | append $verdict.reasons | append $everdict.reasons | append $missing_files | append $erl_reasons)
  if ($reasons | is-empty) {
    let shown = if ($images | is-empty) { "none" } else { $images | each {|i| $"($i.file):($i.otp)" } | str join "," }
    let eshown = if ($images | is-empty) { "none" } else { $images | each {|i| $"($i.file):($i.elixir)" } | str join "," }
    print $"PASS audit:otp floor=($floor) pin=($pin) runtime=($runtime) images=($shown) elixir_floor=($efloor) elixir_pin=($epin) elixir_images=($eshown)"
  } else {
    print $"FAIL audit:otp ($reasons | str join '; ')"
    exit 1
  }
}
