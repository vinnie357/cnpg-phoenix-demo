#!/usr/bin/env nu
# test-otp-audit.nu: tests for scripts/otp-audit.nu, the audit:otp gate (#9).
#
# This file is RED (fails to parse: module not found) until scripts/otp-audit.nu
# exists. No network: the seam cases use literal text, and the end-to-end cases
# run the script against a fake `erl` on PATH and fixture roots under
# `mktemp -d`, passing --root. The `defaults` case reads the real repo files
# with a fake erl that prints the repo's own pin. The `real toolchain` case runs
# the script with the erl on PATH unchanged, so it needs the mise toolchain:
# run this file through `mise run test:otp-audit` (or `mise exec -- nu ...`).
# A bare `nu test/test-otp-audit.nu` with no erlang 28.5.0.8 on PATH is a known
# red, not a flake. Temp dirs are removed even when an assert fails.
#
# Floors: OTP 28.5.0.8, Elixir 1.19.6. CVE-2026-55953 is fixed in OTP 28.5.0.4
# and CVE-2026-89422 in 28.5.0.7; the floor is the pinned 28.5.0.8.
#
# Interface under test (scripts/otp-audit.nu):
#   const repo = (path self | path dirname | path dirname)
#   const otp_floor = "28.5.0.8"
#   const elixir_floor = "1.19.6"
#   export def version-below [a: string, b: string]: nothing -> bool
#       Split on ".", `into int` per component, pad the shorter with 0,
#       compare left to right. Raises on any non-numeric component ("",
#       "latest", "28.5.0.8-rc1"), in either argument.
#   export def erlang-pin [mise_toml: record]
#       tools.erlang as a string: a string value as is, a record's `version`.
#       null when tools or tools.erlang is missing, and when the value is a
#       list or any other non-string shape.
#   export def elixir-pin [mise_toml: record]
#       tools.elixir, same rules as erlang-pin ("1.19.6-otp-28" as is).
#   export def otp-version-from-file [text: string]: nothing -> string
#       First whitespace-separated token of the trimmed text
#       ("28.5.0.8 **\n" -> "28.5.0.8").
#   export def dockerfile-otp [file: string, text: string]: nothing -> record<file: string, line: int, image: string, otp: any, reason: string, elixir: any, elixir_line: int, elixir_reason: string>
#       The Dockerfile builds its builder image from ARGs:
#         ARG ELIXIR_VERSION=1.19.6
#         ARG OTP_VERSION=28.5.0.8
#         ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
#         FROM ${BUILDER_IMAGE} AS builder
#       The OTP version is the value of the single line matching
#       `^ARG OTP_VERSION=(\S+)$`, with surrounding double quotes stripped; the
#       Elixir version likewise from `^ARG ELIXIR_VERSION=(\S+)$`. One pass,
#       one def: there is no second Dockerfile parser.
#       - file: the file argument. line: 1-based line of the OTP ARG line, 0 when
#         there is not exactly one. image: the BUILDER_IMAGE ARG default with
#         quotes stripped, "" when absent. elixir_line: the same for the
#         ELIXIR_VERSION ARG.
#       - The builder link holds when an `ARG BUILDER_IMAGE=` default contains
#         `elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}` and some line is
#         `FROM ${BUILDER_IMAGE}` (optionally ` AS <stage>`). When it does not
#         hold, otp AND elixir are null, and reason and elixir_reason contain
#         `builder image does not use`.
#       - otp is the OTP value, and reason is "", only when the builder link
#         holds and there is exactly one `ARG OTP_VERSION=` line whose value
#         has no `$`. Otherwise otp is null (fail closed), reason non-empty.
#       - elixir is the Elixir value, and elixir_reason is "", only when the
#         builder link holds and there is exactly one `ARG ELIXIR_VERSION=` line
#         whose value has no `$`. Otherwise elixir is null, elixir_reason
#         non-empty. A bad ELIXIR ARG does not null otp, and vice versa.
#   export def otp-verdict [floor: string, pin, runtime, images: list]: nothing -> record<pass: bool, reasons: list<string>>
#       Never raises. pass == (reasons is empty). Reason formats (substrings):
#         pin null or non-numeric : `erlang pin missing or not numeric: <pin>`
#         pin below floor         : `pin <pin> below floor <floor>`
#         runtime null            : contains `runtime`
#         runtime non-numeric     : contains `runtime` and the value
#         runtime below floor     : `runtime <rt> below floor <floor>`
#         runtime != pin          : `runtime <rt> differs from pin <pin>`
#         image otp null          : `cannot read OTP version from <file>:<line>`
#         image otp non-numeric   : contains `<file>:<line>`
#         image below floor       : `image <file>:<line> OTP <otp> below floor <floor>`
#         image != pin            : `image <file>:<line> OTP <otp> differs from pin <pin>`
#       Equality is numeric, not string: 28.5.0.8.0 equals 28.5.0.8.
#   export def elixir-verdict [floor: string, pin, erlang_pin, images: list]: nothing -> record<pass: bool, reasons: list<string>>
#       Never raises. pass == (reasons is empty). The pin's version is the text
#       before the first `-` ("1.19.6-otp-28" -> "1.19.6"). images are
#       dockerfile-otp records (elixir, elixir_line, file are read).
#         pin null, or version non-numeric : `elixir pin missing or not numeric: <pin>`
#         pin version below floor          : `elixir pin <version> below floor <floor>`
#         pin suffix is not `-otp-<M>`, M = first component of a numeric
#         erlang_pin (checked only then)   : `elixir pin <pin> does not match erlang major <M>`
#         image elixir null                : `cannot read Elixir version from <file>:<elixir_line>`
#         image elixir below floor         : `image <file>:<elixir_line> Elixir <v> below floor <floor>`
#         image elixir != pin version      : `image <file>:<elixir_line> Elixir <v> differs from pin <version>`
#       Equality is numeric. No Elixir runtime probe: mise installs the pin.
#   def main [--floor: string, --elixir-floor: string, --root: path, --image-file: string]
#       --floor        default otp_floor. --elixir-floor default elixir_floor.
#       --root         default $repo (never the cwd). Base for <root>/mise.toml,
#                      the image file, and erl's cwd.
#       --image-file   default "Dockerfile", relative to --root. A missing file
#                      FAILs and the reason names it. Its record comes from
#                      dockerfile-otp and is judged by otp-verdict and
#                      elixir-verdict.
#       Runtime: runs `erl -noshell -eval '<eval>'` with cwd = <root>. The eval
#       reads releases/<otp_release>/OTP_VERSION under code:root_dir() and
#       halts 0, or prints the error to stderr and halts 1. Non-zero exit or
#       empty output is a null runtime, and the FAIL line carries erl's stderr.
#       A missing <root>/mise.toml FAILs.
#       Output (stdout), last non-empty line:
#         `PASS audit:otp floor=<floor> pin=<pin> runtime=<rt> images=<file>:<otp> elixir_floor=<efloor> elixir_pin=<epin> elixir_images=<file>:<elixir>`, exit 0; or
#         `FAIL audit:otp <reason>; <reason>; ...` listing every OTP and Elixir reason, exit 1.

use std/assert
use ../scripts/otp-audit.nu *

const root = path self ..
const floor = "28.5.0.8"

def last-line [text: string] {
  let ls = ($text | lines | where {|l| ($l | str trim) != "" })
  if ($ls | is-empty) { "" } else { $ls | last }
}

def any-reason [v: record, needle: string] {
  $v.reasons | any {|r| $r | str contains $needle }
}

# try/catch: the temp dir is removed whether the body passes or raises.
def with-temp-dir [body: closure] {
  let dir = (mktemp -d)
  try {
    do $body $dir | ignore
  } catch {|e|
    rm -rf $dir
    error make --unspanned {msg: $"($e.msg)\n($e.rendered)"}
  }
  rm -rf $dir
}

const builder_arg = 'ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"'

# A Dockerfile shaped like the repo's. `ARG ELIXIR_VERSION=` is on line 2,
# `ARG OTP_VERSION=` on line 3.
def dockerfile [otp: string, elixir: string = "1.19.6"] {
  [
    "# builder and runtime images are built from these ARGs"
    $"ARG ELIXIR_VERSION=($elixir)"
    $"ARG OTP_VERSION=($otp)"
    "ARG DEBIAN_VERSION=trixie-20261005-slim"
    ""
    $builder_arg
    'ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"'
    ""
    'FROM ${BUILDER_IMAGE} AS builder'
    "RUN mix release"
    ""
    'FROM ${RUNNER_IMAGE} AS final'
    "COPY --from=builder /app /app"
    ""
  ] | str join "\n"
}

# ---------------------------------------------------------------- seam cases

def version-below-cases [] {
  let table = [
    [a b below];
    ["28.5.0.10" "28.5.0.7" false]
    ["28.5.0.7" "28.5.0.7" false]
    ["28.5.0.6" "28.5.0.7" true]
    ["28.5" "28.5.0.7" true]
    ["28.3.2" "28.5.0.7" true]
    ["28.10.0.1" "28.5.0.7" false]
    ["29" "28.5.0.7" false]
    ["27.3.4.17" "28.5.0.7" true]
    ["28.5.0.7" "28.5.0.8" true]
  ]
  for r in $table {
    assert equal (version-below $r.a $r.b) $r.below $"version-below ($r.a) ($r.b) must be ($r.below)"
  }
  assert equal (version-below "28.5.0.8" "28.5.0.8.0") false "padding: 28.5.0.8 is not below 28.5.0.8.0"
  assert equal (version-below "28.5.0.8.0" "28.5.0.8") false "padding: 28.5.0.8.0 is not below 28.5.0.8"
  assert equal (version-below "28.5" "28.5.0.0") false "padding: 28.5 equals 28.5.0.0"
  assert equal (version-below "28.5.0.0" "28.5") false "padding: 28.5.0.0 equals 28.5"
  assert equal (version-below "1.19.5" "1.19.6") true "Elixir: 1.19.5 is below 1.19.6"
  assert equal (version-below "1.19.10" "1.19.6") false "Elixir: 1.19.10 is not below 1.19.6 (numeric, not string)"
  for bad in ["28.5.0.8-rc1" "latest" ""] {
    let raised = (try { version-below $bad "28.5.0.7" | ignore; false } catch { true })
    assert $raised $"version-below must raise on non-numeric a: '($bad)'"
  }
  let raised = (try { version-below "28.5.0.8" "latest" | ignore; false } catch { true })
  assert $raised "version-below must raise on non-numeric b: 'latest'"
}

def erlang-pin-cases [] {
  assert equal (erlang-pin {tools: {erlang: "28.5.0.8"}}) "28.5.0.8" "a string pin must be returned as is"
  assert equal (erlang-pin {tools: {erlang: {version: "28.5.0.8"}}}) "28.5.0.8" "a {version} record pin must return its version"
  assert equal (erlang-pin {tools: {elixir: "1.19.6-otp-28"}}) null "a missing tools.erlang must be null"
  assert equal (erlang-pin {}) null "a missing [tools] table must be null"
  assert equal (erlang-pin {tools: {erlang: ["28.5.0.8" "27"]}}) null "a list-valued pin must be null (it FAILs)"
  # Parsed from real TOML text, as main reads it.
  assert equal (erlang-pin ("[tools]\nerlang = \"28.5.0.8\"\n" | from toml)) "28.5.0.8" "string pin from TOML text"
  assert equal (erlang-pin ("[tools]\nerlang = { version = \"28.5.0.8\" }\n" | from toml)) "28.5.0.8" "record pin from TOML text"
  assert equal (erlang-pin ("[tools]\nerlang = [\"28.5.0.8\", \"27\"]\n" | from toml)) null "list pin from TOML text must be null"
  let v = (otp-verdict $floor (erlang-pin {tools: {erlang: ["28.5.0.8" "27"]}}) "28.5.0.8" [])
  assert equal $v.pass false "a list-valued pin must FAIL the verdict"
  assert (any-reason $v "erlang pin missing or not numeric") "a list-valued pin must fail as `erlang pin missing or not numeric`"
}

def otp-version-from-file-cases [] {
  assert equal (otp-version-from-file "28.5.0.8\n") "28.5.0.8" "plain OTP_VERSION"
  assert equal (otp-version-from-file "28.5.0.8 **\n") "28.5.0.8" "a patched install writes `28.5.0.8 **`; take the first token"
  assert equal (otp-version-from-file "  28.5.0.8\r\n") "28.5.0.8" "surrounding whitespace is trimmed"
}


def dockerfile-otp-cases [] {
  let r = (dockerfile-otp "Dockerfile" (dockerfile "28.5.0.8"))
  assert equal $r.file "Dockerfile" "record.file is the file argument"
  assert equal $r.line 3 "record.line is the 1-based ARG OTP_VERSION line"
  assert equal $r.otp "28.5.0.8" "the single literal ARG OTP_VERSION default is the OTP version"
  assert equal $r.reason "" "a readable OTP version has an empty reason"
  assert equal $r.image 'docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}' "record.image is the BUILDER_IMAGE default, quotes stripped"
  assert equal (dockerfile-otp "Dockerfile" (dockerfile "28.3.2")).otp "28.3.2" "a vulnerable default is read as is (the verdict fails it)"

  # The real repo Dockerfile reads as the mise pin.
  let real = (dockerfile-otp "Dockerfile" (open --raw ($root | path join "Dockerfile")))
  assert equal $real.otp (erlang-pin (open ($root | path join "mise.toml"))) "the repo Dockerfile's OTP_VERSION must read as the mise.toml erlang pin"

  # Quoted value.
  let quoted = (dockerfile "28.5.0.8" | str replace "ARG OTP_VERSION=28.5.0.8" 'ARG OTP_VERSION="28.5.0.8"')
  assert equal (dockerfile-otp "Dockerfile" $quoted).otp "28.5.0.8" "double quotes around the value are stripped"

  # Zero ARG lines.
  let zero = (dockerfile "28.5.0.8" | str replace "ARG OTP_VERSION=28.5.0.8\n" "")
  let z = (dockerfile-otp "Dockerfile" $zero)
  assert equal $z.otp null "no ARG OTP_VERSION line must be otp null (fail closed)"
  assert ($z.reason != "") "no ARG OTP_VERSION line must give a reason"
  assert equal (dockerfile-otp "Dockerfile" "").otp null "an empty file must be otp null"
  assert equal (dockerfile-otp "Dockerfile" "# ARG OTP_VERSION=28.5.0.8\n").otp null "a commented ARG line does not count"
  assert equal (dockerfile-otp "Dockerfile" ("ARG OTP_VERSION\n" + $builder_arg + "\nFROM ${BUILDER_IMAGE} AS builder\n")).otp null "an ARG without a default must be otp null"

  # Two ARG lines.
  let two = (dockerfile "28.5.0.8" | str replace "ARG OTP_VERSION=28.5.0.8" "ARG OTP_VERSION=28.5.0.8\nARG OTP_VERSION=28.3.2")
  let t = (dockerfile-otp "Dockerfile" $two)
  assert equal $t.otp null "two ARG OTP_VERSION lines must be otp null (fail closed)"
  assert ($t.reason != "") "two ARG OTP_VERSION lines must give a reason"
  let same_twice = (dockerfile "28.5.0.8" | str replace "ARG OTP_VERSION=28.5.0.8" "ARG OTP_VERSION=28.5.0.8\nARG OTP_VERSION=28.5.0.8")
  assert equal (dockerfile-otp "Dockerfile" $same_twice).otp null "two ARG lines fail closed even when they agree"

  # `$` in the value.
  for v in ['${X}' '$X' '28.5.${PATCH}'] {
    let d = (dockerfile "28.5.0.8" | str replace "ARG OTP_VERSION=28.5.0.8" $"ARG OTP_VERSION=($v)")
    assert equal (dockerfile-otp "Dockerfile" $d).otp null $"an ARG value built from another ARG must be otp null: ($v)"
  }

  # Builder image must carry ${OTP_VERSION}.
  let literal_builder = (dockerfile "28.5.0.8" | str replace $builder_arg 'ARG BUILDER_IMAGE="docker.io/hexpm/elixir:1.19.6-erlang-28.3.2-debian-trixie-20261005-slim"')
  let b = (dockerfile-otp "Dockerfile" $literal_builder)
  assert equal $b.otp null "a BUILDER_IMAGE that does not use ${OTP_VERSION} must be otp null"
  assert ($b.reason | str contains "builder image does not use") $"reason for an unlinked builder; got: ($b.reason)"
  let no_builder = (dockerfile "28.5.0.8" | str replace $"($builder_arg)\n" "")
  let nb = (dockerfile-otp "Dockerfile" $no_builder)
  assert equal $nb.otp null "a missing ARG BUILDER_IMAGE must be otp null"
  assert ($nb.reason | str contains "builder image does not use") $"reason for a missing BUILDER_IMAGE; got: ($nb.reason)"

  # Some FROM must use ${BUILDER_IMAGE}.
  let literal_from = (dockerfile "28.5.0.8" | str replace 'FROM ${BUILDER_IMAGE} AS builder' 'FROM docker.io/hexpm/elixir:1.19.6-erlang-28.3.2-debian-trixie-20261005-slim AS builder')
  let f = (dockerfile-otp "Dockerfile" $literal_from)
  assert equal $f.otp null "no `FROM ${BUILDER_IMAGE}` line must be otp null"
  assert ($f.reason | str contains "builder image does not use") $"reason for a FROM that bypasses BUILDER_IMAGE; got: ($f.reason)"
  let commented_from = (dockerfile "28.5.0.8" | str replace 'FROM ${BUILDER_IMAGE} AS builder' '# FROM ${BUILDER_IMAGE} AS builder')
  assert equal (dockerfile-otp "Dockerfile" $commented_from).otp null "a commented `# FROM ${BUILDER_IMAGE}` does not count"

  # A null record fails the verdict and names file:line.
  let v = (otp-verdict $floor $floor $floor [$z])
  assert equal $v.pass false "a Dockerfile with no OTP ARG must FAIL the verdict"
  assert (any-reason $v "Dockerfile") "the reason must name the Dockerfile"
  let v = (otp-verdict $floor $floor $floor [(dockerfile-otp "Dockerfile" (dockerfile "28.3.2"))])
  assert (any-reason $v "image Dockerfile:3 OTP 28.3.2 below floor 28.5.0.8") "a vulnerable ARG default fails at its line"
}

def elixir-pin-cases [] {
  assert equal (elixir-pin {tools: {elixir: "1.19.6-otp-28"}}) "1.19.6-otp-28" "a string elixir pin must be returned as is"
  assert equal (elixir-pin {tools: {elixir: {version: "1.19.6-otp-28"}}}) "1.19.6-otp-28" "a {version} record elixir pin must return its version"
  assert equal (elixir-pin {tools: {erlang: "28.5.0.8"}}) null "a missing tools.elixir must be null"
  assert equal (elixir-pin {}) null "a missing [tools] table must be null"
  assert equal (elixir-pin {tools: {elixir: ["1.19.6-otp-28" "1.18"]}}) null "a list-valued elixir pin must be null"
  assert equal (elixir-pin ("[tools]\nelixir = \"1.19.6-otp-28\"\n" | from toml)) "1.19.6-otp-28" "elixir pin from TOML text"
}

def dockerfile-elixir-cases [] {
  let r = (dockerfile-otp "Dockerfile" (dockerfile "28.5.0.8"))
  assert equal $r.elixir "1.19.6" "the single literal ARG ELIXIR_VERSION default is the Elixir version"
  assert equal $r.elixir_line 2 "record.elixir_line is the 1-based ARG ELIXIR_VERSION line"
  assert equal $r.elixir_reason "" "a readable Elixir version has an empty elixir_reason"

  # The real repo Dockerfile reads as the mise elixir pin's version.
  let real = (dockerfile-otp "Dockerfile" (open --raw ($root | path join "Dockerfile")))
  let pin = (elixir-pin (open ($root | path join "mise.toml")))
  assert equal $real.elixir ($pin | split row "-" | first) "the repo Dockerfile's ELIXIR_VERSION must read as the mise.toml elixir pin version"

  let quoted = (dockerfile "28.5.0.8" | str replace "ARG ELIXIR_VERSION=1.19.6" 'ARG ELIXIR_VERSION="1.19.6"')
  assert equal (dockerfile-otp "Dockerfile" $quoted).elixir "1.19.6" "double quotes around the Elixir value are stripped"

  # Zero ELIXIR ARG lines: elixir null, otp unaffected.
  let zero = (dockerfile-otp "Dockerfile" (dockerfile "28.5.0.8" | str replace "ARG ELIXIR_VERSION=1.19.6\n" ""))
  assert equal $zero.elixir null "no ARG ELIXIR_VERSION line must be elixir null (fail closed)"
  assert ($zero.elixir_reason != "") "no ARG ELIXIR_VERSION line must give an elixir_reason"
  assert equal $zero.otp "28.5.0.8" "a missing ELIXIR ARG must not null otp"

  # Two ELIXIR ARG lines.
  let two = (dockerfile-otp "Dockerfile" (dockerfile "28.5.0.8" | str replace "ARG ELIXIR_VERSION=1.19.6" "ARG ELIXIR_VERSION=1.19.6\nARG ELIXIR_VERSION=1.19.6"))
  assert equal $two.elixir null "two ARG ELIXIR_VERSION lines must be elixir null even when they agree"
  assert ($two.elixir_reason != "") "two ARG ELIXIR_VERSION lines must give an elixir_reason"

  # `$` in the value.
  for v in ['${X}' '$X' '1.19.${PATCH}'] {
    let d = (dockerfile "28.5.0.8" | str replace "ARG ELIXIR_VERSION=1.19.6" $"ARG ELIXIR_VERSION=($v)")
    let rec = (dockerfile-otp "Dockerfile" $d)
    assert equal $rec.elixir null $"an ELIXIR ARG value built from another ARG must be elixir null: ($v)"
    assert equal $rec.otp "28.5.0.8" $"a bad ELIXIR ARG must not null otp: ($v)"
  }

  # A bad OTP ARG does not null elixir.
  let no_otp = (dockerfile-otp "Dockerfile" (dockerfile "28.5.0.8" | str replace "ARG OTP_VERSION=28.5.0.8\n" ""))
  assert equal $no_otp.elixir "1.19.6" "a missing OTP ARG must not null elixir"

  # Builder image must carry elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}.
  let literal_elixir = (dockerfile "28.5.0.8" | str replace $builder_arg 'ARG BUILDER_IMAGE="docker.io/hexpm/elixir:1.18.4-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"')
  let b = (dockerfile-otp "Dockerfile" $literal_elixir)
  assert equal $b.elixir null "a BUILDER_IMAGE that does not use ${ELIXIR_VERSION} must be elixir null"
  assert equal $b.otp null "a BUILDER_IMAGE that does not use ${ELIXIR_VERSION} must also be otp null (one builder link)"
  assert ($b.elixir_reason | str contains "builder image does not use") $"elixir_reason for an unlinked builder; got: ($b.elixir_reason)"
  assert ($b.reason | str contains "builder image does not use") $"reason for an unlinked builder; got: ($b.reason)"
  let literal_from = (dockerfile-otp "Dockerfile" (dockerfile "28.5.0.8" | str replace 'FROM ${BUILDER_IMAGE} AS builder' 'FROM docker.io/hexpm/elixir:1.19.6-erlang-28.5.0.8-debian-trixie-20261005-slim AS builder'))
  assert equal $literal_from.elixir null "no `FROM ${BUILDER_IMAGE}` line must be elixir null"
}

def eimg [elixir, line: int = 2, file: string = "Dockerfile"] {
  {file: $file, line: 3, image: "fixture", otp: "28.5.0.8", reason: "", elixir: $elixir, elixir_line: $line, elixir_reason: (if $elixir == null { "fixture reason" } else { "" })}
}

const efloor = "1.19.6"
const epin = "1.19.6-otp-28"

def elixir-verdict-cases [] {
  assert equal (elixir-verdict $efloor $epin $floor [(eimg "1.19.6")]) {pass: true, reasons: []} "pin and image at the floor must pass"
  assert equal (elixir-verdict $efloor $epin $floor []) {pass: true, reasons: []} "no images must pass"
  assert equal (elixir-verdict $efloor "1.19.10-otp-28" $floor [(eimg "1.19.10")]).pass true "1.19.10 is above 1.19.6 (numeric compare)"
  assert equal (elixir-verdict $efloor $epin $floor [(eimg "1.19.6.0")]).pass true "equality is numeric: 1.19.6.0 equals 1.19.6"

  # pin
  for bad in [null "latest" "" "x.y-otp-28"] {
    let v = (elixir-verdict $efloor $bad $floor [(eimg "1.19.6")])
    assert equal $v.pass false $"elixir pin ($bad) must fail \(and not raise\)"
    assert (any-reason $v "elixir pin missing or not numeric") $"elixir pin ($bad) reason; got: ($v.reasons)"
  }
  let v = (elixir-verdict $efloor "latest" $floor [])
  assert (any-reason $v "elixir pin missing or not numeric: latest") "non-numeric elixir pin reason names the value"
  let v = (elixir-verdict $efloor "1.19.5-otp-28" $floor [])
  assert equal $v.pass false "an elixir pin below the floor must fail"
  assert (any-reason $v "elixir pin 1.19.5 below floor 1.19.6") "elixir pin-below reason"
  let v = (elixir-verdict $efloor "1.18.4-otp-28" $floor [])
  assert (any-reason $v "elixir pin 1.18.4 below floor 1.19.6") "an older minor is below the floor"

  # otp suffix must match the erlang major
  let v = (elixir-verdict $efloor "1.19.6-otp-27" $floor [(eimg "1.19.6")])
  assert equal $v.pass false "an elixir pin built for otp-27 with erlang 28 must fail"
  assert (any-reason $v "elixir pin 1.19.6-otp-27 does not match erlang major 28") "suffix-mismatch reason"
  let v = (elixir-verdict $efloor "1.19.6" $floor [(eimg "1.19.6")])
  assert equal $v.pass false "an elixir pin with no -otp-<M> suffix must fail"
  assert (any-reason $v "does not match erlang major 28") "no-suffix reason"
  let v = (elixir-verdict $efloor "1.19.6-otp-28" "29.0.1" [(eimg "1.19.6")])
  assert (any-reason $v "elixir pin 1.19.6-otp-28 does not match erlang major 29") "the major comes from the erlang pin argument"
  assert equal (elixir-verdict $efloor $epin null [(eimg "1.19.6")]).pass true "a null erlang pin skips the suffix check (otp-verdict fails it)"

  # images
  let v = (elixir-verdict $efloor $epin $floor [(eimg null 2)])
  assert equal $v.pass false "an unreadable image Elixir must fail"
  assert (any-reason $v "cannot read Elixir version from Dockerfile:2") "unreadable-image Elixir reason"
  let v = (elixir-verdict $efloor $epin $floor [(eimg "1.19.5" 4)])
  assert equal $v.pass false "an image Elixir below the floor must fail"
  assert (any-reason $v "image Dockerfile:4 Elixir 1.19.5 below floor 1.19.6") "image Elixir below reason"
  assert (any-reason $v "image Dockerfile:4 Elixir 1.19.5 differs from pin 1.19.6") "an image below the pin also differs from it"
  let v = (elixir-verdict $efloor $epin $floor [(eimg "1.19.7" 2 "Dockerfile.alt")])
  assert equal $v.pass false "an image Elixir above the floor that differs from the pin must fail"
  assert (any-reason $v "image Dockerfile.alt:2 Elixir 1.19.7 differs from pin 1.19.6") "image Elixir differs reason"
  assert (not (any-reason $v "below floor")) "an image Elixir above the floor must not report below floor"
  let v = (elixir-verdict $efloor $epin $floor [(eimg "x.y" 2)])
  assert equal $v.pass false "a non-numeric image Elixir must fail (and not raise)"
  assert (any-reason $v "Dockerfile:2") "non-numeric image Elixir reason names file:line"
  assert equal (elixir-verdict "1.19.7" $epin $floor [(eimg "1.19.6")]).pass false "the floor argument is honoured"

  # several reasons together
  let v = (elixir-verdict $efloor "1.19.5-otp-27" $floor [(eimg null 2) (eimg "1.18.0" 5 "Dockerfile.alt")])
  assert (any-reason $v "elixir pin 1.19.5 below floor 1.19.6") "several: pin"
  assert (any-reason $v "does not match erlang major 28") "several: suffix"
  assert (any-reason $v "cannot read Elixir version from Dockerfile:2") "several: unreadable"
  assert (any-reason $v "image Dockerfile.alt:5 Elixir 1.18.0 below floor 1.19.6") "several: image below"
}

def img [otp, line: int = 2, file: string = "Dockerfile"] {
  {file: $file, line: $line, image: "fixture", otp: $otp}
}

def otp-verdict-cases [] {
  let ok = (otp-verdict $floor "28.5.0.8" "28.5.0.8" [(img "28.5.0.8") (img "28.5.0.8" 1 "Dockerfile.alt")])
  assert equal $ok {pass: true, reasons: []} "all equal and at the floor must pass with no reasons"
  assert equal (otp-verdict $floor "28.5.0.8" "28.5.0.8" []) {pass: true, reasons: []} "no images must pass"
  assert equal (otp-verdict $floor "28.5.0.9" "28.5.0.9" [(img "28.5.0.9")]).pass true "above the floor and equal must pass"
  assert equal (otp-verdict $floor "28.5.0.8" "28.5.0.8.0" [(img "28.5.0.8.0")]).pass true "equality is numeric: 28.5.0.8.0 equals 28.5.0.8"

  # pin
  let v = (otp-verdict $floor null "28.5.0.8" [])
  assert equal $v.pass false "a null pin must fail"
  assert (any-reason $v "erlang pin missing or not numeric") "null pin reason"
  let v = (otp-verdict $floor "latest" "28.5.0.8" [(img "28.5.0.8")])
  assert equal $v.pass false "a non-numeric pin must fail (and not raise)"
  assert (any-reason $v "erlang pin missing or not numeric: latest") "non-numeric pin reason names the value"
  let v = (otp-verdict $floor "28.3.2" "28.3.2" [])
  assert equal $v.pass false "a pin below the floor must fail"
  assert (any-reason $v "pin 28.3.2 below floor 28.5.0.8") "pin-below reason"
  let v = (otp-verdict $floor "28.5" "28.5.0.8" [])
  assert equal $v.pass false "a fuzzy pin 28.5 must fail"
  let v = (otp-verdict $floor "29" "28.5.0.8" [])
  assert equal $v.pass false "a fuzzy pin 29 must fail: it never equals a 4-part runtime"
  assert (any-reason $v "runtime 28.5.0.8 differs from pin 29") "fuzzy pin 29 fails as runtime differs from pin"

  # runtime
  let v = (otp-verdict $floor "28.5.0.8" null [])
  assert equal $v.pass false "a null runtime must fail"
  assert (any-reason $v "runtime") "null runtime reason mentions runtime"
  let v = (otp-verdict $floor "28.5.0.8" "garbage" [])
  assert equal $v.pass false "a non-numeric runtime must fail (and not raise)"
  assert ($v.reasons | any {|r| ($r | str contains "runtime") and ($r | str contains "garbage") }) "non-numeric runtime reason names runtime and the value"
  let v = (otp-verdict $floor "28.5.0.8" "28.5.0.7" [])
  assert equal $v.pass false "a runtime below the floor must fail"
  assert (any-reason $v "runtime 28.5.0.7 below floor 28.5.0.8") "runtime-below reason"
  assert (any-reason $v "runtime 28.5.0.7 differs from pin 28.5.0.8") "a runtime below the pin also differs from it"
  let v = (otp-verdict $floor "28.5.0.8" "28.5.0.9" [])
  assert equal $v.pass false "a runtime above the floor that differs from the pin must fail"
  assert (any-reason $v "runtime 28.5.0.9 differs from pin 28.5.0.8") "runtime-differs reason"
  assert (not (any-reason $v "below floor")) "a runtime above the floor must not report below floor"

  # images
  let v = (otp-verdict $floor "28.5.0.8" "28.5.0.8" [(img null 3)])
  assert equal $v.pass false "an unparseable image must fail"
  assert (any-reason $v "cannot read OTP version from Dockerfile:3") "unparseable-image reason"
  let v = (otp-verdict $floor "28.5.0.8" "28.5.0.8" [(img "x.y" 3)])
  assert equal $v.pass false "a non-numeric image otp must fail (and not raise)"
  assert (any-reason $v "Dockerfile:3") "non-numeric image reason names file:line"
  let v = (otp-verdict $floor "28.5.0.8" "28.5.0.8" [(img "28.5.0.4" 7)])
  assert equal $v.pass false "an image below the floor must fail"
  assert (any-reason $v "image Dockerfile:7 OTP 28.5.0.4 below floor 28.5.0.8") "image-below reason"
  assert (any-reason $v "image Dockerfile:7 OTP 28.5.0.4 differs from pin 28.5.0.8") "an image below the pin also differs from it"
  let v = (otp-verdict $floor "28.5.0.8" "28.5.0.8" [(img "28.5.0.9" 1 "Dockerfile.alt")])
  assert equal $v.pass false "an image above the floor that differs from the pin must fail"
  assert (any-reason $v "image Dockerfile.alt:1 OTP 28.5.0.9 differs from pin 28.5.0.8") "image-differs reason"
  let v = (otp-verdict $floor null "28.5.0.8" [(img "28.5.0.8")])
  assert equal $v.pass false "an image with a null pin must not raise and must fail"

  # several reasons together
  let v = (otp-verdict $floor "28.5.0.8" "28.5.0.9" [(img null 3) (img "28.5.0.4" 5 "Dockerfile.alt")])
  assert equal $v.pass false "several failures must fail"
  assert (any-reason $v "runtime 28.5.0.9 differs from pin 28.5.0.8") "several: runtime reason"
  assert (any-reason $v "cannot read OTP version from Dockerfile:3") "several: unparseable reason"
  assert (any-reason $v "image Dockerfile.alt:5 OTP 28.5.0.4 below floor 28.5.0.8") "several: image-below reason"
  assert (($v.reasons | length) >= 3) $"every reason must be listed, got: ($v.reasons)"
  let v = (otp-verdict $floor "28.3.2" "28.3.2" [(img "28.3.2")])
  assert (any-reason $v "pin 28.3.2 below floor") "main-shaped: pin"
  assert (any-reason $v "runtime 28.3.2 below floor") "main-shaped: runtime"
  assert (any-reason $v "image Dockerfile:2 OTP 28.3.2 below floor") "main-shaped: image"
  assert equal (otp-verdict "28.5.0.9" "28.5.0.8" "28.5.0.8" [(img "28.5.0.8")]).pass false "the floor argument is honoured"
}

# ---------------------------------------------------------- end-to-end cases

def mise-toml [pin: string, elixir: string = "1.19.6-otp-28"] { $"[tools]\nerlang = \"($pin)\"\nelixir = \"($elixir)\"\n" }

# Fixture root: <base>/<name> with an optional mise.toml text and files.
def fixture [base: string, name: string, mise, files: record] {
  let r = ($base | path join $name)
  mkdir $r
  if $mise != null { $mise | save ($r | path join "mise.toml") }
  for f in ($files | transpose name text) {
    let p = ($r | path join $f.name)
    mkdir ($p | path dirname)
    $f.text | save $p
  }
  $r
}

def end-to-end-cases [] {
  with-temp-dir {|dir|
    let bin = ($dir | path join "bin")
    let work = ($dir | path join "cwd")
    mkdir $bin $work
    let script = ($root | path join "scripts" "otp-audit.nu")
    let nu_exe = $nu.current-exe

    # Fake erl: records its args and physical cwd, prints FAKE_OTP, or prints
    # FAKE_ERL_STDERR to stderr and exits FAKE_ERL_EXIT.
    let erl = ($bin | path join "erl")
    [
      "#!/bin/sh"
      $"D='($dir)'"
      "pwd -P > \"$D/erl-cwd\""
      "printf '%s\\n' \"$@\" > \"$D/erl-args\""
      "if [ -n \"$FAKE_ERL_EXIT\" ]; then printf '%s\\n' \"$FAKE_ERL_STDERR\" >&2; exit \"$FAKE_ERL_EXIT\"; fi"
      "printf '%s\\n' \"$FAKE_OTP\""
      "exit 0"
    ] | str join "\n" | save $erl
    ^chmod +x $erl
    let path = ($env.PATH | prepend $bin)

    let run = {|flags: list, fake: record|
      rm -f ($dir | path join "erl-cwd") ($dir | path join "erl-args")
      let r = (do {
        hide-env -i FAKE_OTP FAKE_ERL_EXIT FAKE_ERL_STDERR
        # cwd is an unrelated temp dir, so a cwd-relative default fails.
        cd $work
        with-env ({PATH: $path} | merge $fake) { ^$nu_exe -n $script ...$flags }
      } | complete)
      let cwd_file = ($dir | path join "erl-cwd")
      let args_file = ($dir | path join "erl-args")
      $r | merge {
        last: (last-line $r.stdout)
        erl_cwd: (if ($cwd_file | path exists) { open --raw $cwd_file | str trim } else { null })
        erl_args: (if ($args_file | path exists) { open --raw $args_file } else { "" })
      }
    }
    let ok8 = {FAKE_OTP: "28.5.0.8"}

    let assert_fail = {|r: record, label: string, needles: list|
      assert ($r.exit_code != 0) $"($label): must exit non-zero; stdout: ($r.stdout) stderr: ($r.stderr)"
      assert ($r.last | str starts-with "FAIL audit:otp ") $"($label): last line must start with `FAIL audit:otp `; got: ($r.last) stderr: ($r.stderr)"
      for n in $needles {
        assert ($r.last | str contains $n) $"($label): FAIL line must contain `($n)`; got: ($r.last)"
      }
    }

    # ---- E1 PASS: repo-shaped fixture, all at 28.5.0.8.
    let pass_root = (fixture $dir "pass" (mise-toml "28.5.0.8") {Dockerfile: (dockerfile "28.5.0.8")})
    let r = (do $run ["--root" $pass_root] $ok8)
    assert equal $r.exit_code 0 $"E1 pass fixture must exit 0; stdout: ($r.stdout) stderr: ($r.stderr)"
    assert equal $r.last "PASS audit:otp floor=28.5.0.8 pin=28.5.0.8 runtime=28.5.0.8 images=Dockerfile:28.5.0.8 elixir_floor=1.19.6 elixir_pin=1.19.6-otp-28 elixir_images=Dockerfile:1.19.6" "E1 PASS line"
    assert equal $r.erl_cwd ($pass_root | path expand) "erl must run with cwd = --root"
    assert ($r.erl_args | str contains "-noshell") "erl must be called with -noshell"
    assert ($r.erl_args | str contains "-eval") "erl must be called with -eval"
    assert ($r.erl_args | str contains "OTP_VERSION") "the eval must read OTP_VERSION"
    assert ($r.erl_args | str contains "halt(1)") "the eval must halt(1) on a read error"
    let r = (do $run ["--root" $pass_root] {FAKE_OTP: "28.5.0.8 **"})
    assert equal $r.exit_code 0 $"`28.5.0.8 **` must read as 28.5.0.8; stdout: ($r.stdout)"
    let rec_root = (fixture $dir "rec" "[tools]\nerlang = { version = \"28.5.0.8\" }\nelixir = \"1.19.6-otp-28\"\n" {Dockerfile: (dockerfile "28.5.0.8")})
    let r = (do $run ["--root" $rec_root] $ok8)
    assert equal $r.exit_code 0 $"a {version} record pin must pass; stdout: ($r.stdout) stderr: ($r.stderr)"

    # ---- E2 pin below floor.
    let r = (do $run ["--root" (fixture $dir "pin7" (mise-toml "28.5.0.7") {Dockerfile: (dockerfile "28.5.0.8")})] $ok8)
    do $assert_fail $r "E2 pin below floor" ["pin 28.5.0.7 below floor 28.5.0.8"]
    let old_root = (fixture $dir "old" (mise-toml "28.3.2") {Dockerfile: (dockerfile "28.3.2")})
    let r = (do $run ["--root" $old_root] {FAKE_OTP: "28.3.2"})
    do $assert_fail $r "all old" ["pin 28.3.2 below floor 28.5.0.8" "runtime 28.3.2 below floor 28.5.0.8" "image Dockerfile:3 OTP 28.3.2 below floor 28.5.0.8" "; "]

    # ---- E3 Dockerfile differs from pin.
    let r = (do $run ["--root" (fixture $dir "img7" (mise-toml "28.5.0.8") {Dockerfile: (dockerfile "28.5.0.7")})] $ok8)
    do $assert_fail $r "E3 image below and differs" ["image Dockerfile:3 OTP 28.5.0.7 below floor 28.5.0.8" "image Dockerfile:3 OTP 28.5.0.7 differs from pin 28.5.0.8"]
    let r = (do $run ["--root" (fixture $dir "img9" (mise-toml "28.5.0.8") {Dockerfile: (dockerfile "28.5.0.9")})] $ok8)
    do $assert_fail $r "image above differs" ["image Dockerfile:3 OTP 28.5.0.9 differs from pin 28.5.0.8"]
    let unlinked = (dockerfile "28.5.0.8" | str replace 'FROM ${BUILDER_IMAGE} AS builder' 'FROM docker.io/hexpm/elixir:1.19.6-erlang-28.3.2-debian-trixie-20261005-slim AS builder')
    let r = (do $run ["--root" (fixture $dir "unlinked" (mise-toml "28.5.0.8") {Dockerfile: $unlinked})] $ok8)
    do $assert_fail $r "FROM bypasses BUILDER_IMAGE" ["Dockerfile"]

    # Runtime.
    let r = (do $run ["--root" $pass_root] {FAKE_OTP: "28.5.0.9"})
    do $assert_fail $r "runtime differs" ["runtime 28.5.0.9 differs from pin 28.5.0.8"]
    let r = (do $run ["--root" $pass_root] {FAKE_OTP: "28.5.0.7"})
    do $assert_fail $r "runtime below" ["runtime 28.5.0.7 below floor 28.5.0.8"]

    # ---- E4 erl fails.
    let r = (do $run ["--root" $pass_root] {FAKE_ERL_EXIT: "1", FAKE_ERL_STDERR: "{error,enoent_fixture_marker}"})
    do $assert_fail $r "E4 erl exit 1" ["erl failed" "enoent_fixture_marker"]
    let r = (do $run ["--root" $pass_root] {FAKE_OTP: ""})
    do $assert_fail $r "erl empty output" ["runtime"]
    let r = (do {
      cd $work
      with-env {PATH: [($dir | path join "no-bin")]} { ^$nu_exe -n $script "--root" $pass_root }
    } | complete)
    assert ($r.exit_code != 0) $"E4 erl missing from PATH must exit non-zero; stdout: ($r.stdout)"
    assert ((last-line $r.stdout) | str contains "erl failed") $"E4 erl missing must report `erl failed`; got: ($r.stdout)"

    # ---- E5 missing inputs.
    let r = (do $run ["--root" (fixture $dir "nomise" null {Dockerfile: (dockerfile "28.5.0.8")})] $ok8)
    do $assert_fail $r "E5 missing mise.toml" ["mise.toml"]
    let r = (do $run ["--root" (fixture $dir "nodocker" (mise-toml "28.5.0.8") {})] $ok8)
    do $assert_fail $r "E5 missing Dockerfile" ["image file not found: Dockerfile"]
    let r = (do $run ["--root" (fixture $dir "nopin" "[tools]\nelixir = \"1.19.6-otp-28\"\n" {Dockerfile: (dockerfile "28.5.0.8")})] $ok8)
    do $assert_fail $r "missing pin" ["erlang pin missing or not numeric"]
    let r = (do $run ["--root" (fixture $dir "listpin" "[tools]\nerlang = [\"28.5.0.8\", \"27\"]\n" {Dockerfile: (dockerfile "28.5.0.8")})] $ok8)
    do $assert_fail $r "list pin" ["erlang pin missing or not numeric"]
    let r = (do $run ["--root" (fixture $dir "latestpin" (mise-toml "latest") {Dockerfile: (dockerfile "28.5.0.8")})] $ok8)
    do $assert_fail $r "latest pin" ["erlang pin missing or not numeric: latest"]

    # --image-file, relative to --root.
    let alt_root = (fixture $dir "alt" (mise-toml "28.5.0.8") {Dockerfile: (dockerfile "28.5.0.8"), "Dockerfile.alt": (dockerfile "28.3.2")})
    let r = (do $run ["--root" $alt_root "--image-file" "Dockerfile.alt"] $ok8)
    do $assert_fail $r "--image-file is read" ["image Dockerfile.alt:3 OTP 28.3.2 below floor 28.5.0.8"]
    let r = (do $run ["--root" $alt_root "--image-file" "no-such-Dockerfile"] $ok8)
    do $assert_fail $r "--image-file missing" ["no-such-Dockerfile"]

    # ---- E6 default floor pair, and --floor honoured.
    let r7 = (fixture $dir "floor7" (mise-toml "28.5.0.7") {Dockerfile: (dockerfile "28.5.0.7")})
    let r = (do $run ["--root" $r7] {FAKE_OTP: "28.5.0.7"})
    do $assert_fail $r "E6 default floor rejects 28.5.0.7" ["pin 28.5.0.7 below floor 28.5.0.8" "runtime 28.5.0.7 below floor 28.5.0.8" "image Dockerfile:3 OTP 28.5.0.7 below floor 28.5.0.8"]
    let r = (do $run ["--root" $pass_root] $ok8)
    assert equal $r.exit_code 0 "E6 default floor accepts 28.5.0.8"
    assert ($r.last | str starts-with "PASS audit:otp floor=28.5.0.8 ") $"the default floor is 28.5.0.8; got: ($r.last)"
    let r = (do $run ["--root" $pass_root "--floor" "28.5.0.9"] $ok8)
    do $assert_fail $r "--floor 28.5.0.9" ["pin 28.5.0.8 below floor 28.5.0.9" "runtime 28.5.0.8 below floor 28.5.0.9" "image Dockerfile:3 OTP 28.5.0.8 below floor 28.5.0.9"]
    let r = (do $run ["--root" $pass_root "--floor" "28.5.0.4"] $ok8)
    assert ($r.last | str starts-with "PASS audit:otp floor=28.5.0.4 ") $"--floor appears in the PASS line; got: ($r.last)"

    # ---- E8 Elixir: pins and the Dockerfile ELIXIR_VERSION ARG.
    let r = (do $run ["--root" (fixture $dir "ex-below" (mise-toml "28.5.0.8" "1.19.5-otp-28") {Dockerfile: (dockerfile "28.5.0.8" "1.19.5")})] $ok8)
    do $assert_fail $r "E8 elixir below floor" ["elixir pin 1.19.5 below floor 1.19.6" "image Dockerfile:2 Elixir 1.19.5 below floor 1.19.6"]
    let r = (do $run ["--root" (fixture $dir "ex-arg" (mise-toml "28.5.0.8") {Dockerfile: (dockerfile "28.5.0.8" "1.19.7")})] $ok8)
    do $assert_fail $r "E8 elixir ARG differs from pin" ["image Dockerfile:2 Elixir 1.19.7 differs from pin 1.19.6"]
    let r = (do $run ["--root" (fixture $dir "ex-suffix" (mise-toml "28.5.0.8" "1.19.6-otp-27") {Dockerfile: (dockerfile "28.5.0.8")})] $ok8)
    do $assert_fail $r "E8 elixir otp suffix" ["elixir pin 1.19.6-otp-27 does not match erlang major 28"]
    let r = (do $run ["--root" (fixture $dir "ex-none" (mise-toml "28.5.0.8" | str replace "elixir = \"1.19.6-otp-28\"\n" "") {Dockerfile: (dockerfile "28.5.0.8")})] $ok8)
    do $assert_fail $r "E8 elixir pin missing" ["elixir pin missing or not numeric"]
    let r = (do $run ["--root" (fixture $dir "ex-latest" (mise-toml "28.5.0.8" "latest") {Dockerfile: (dockerfile "28.5.0.8")})] $ok8)
    do $assert_fail $r "E8 elixir pin latest" ["elixir pin missing or not numeric: latest"]
    let no_ex_arg = (dockerfile "28.5.0.8" | str replace "ARG ELIXIR_VERSION=1.19.6\n" "")
    let r = (do $run ["--root" (fixture $dir "ex-noarg" (mise-toml "28.5.0.8") {Dockerfile: $no_ex_arg})] $ok8)
    do $assert_fail $r "E8 no ELIXIR_VERSION ARG" ["cannot read Elixir version from Dockerfile"]
    let r = (do $run ["--root" $pass_root "--elixir-floor" "1.19.7"] $ok8)
    do $assert_fail $r "--elixir-floor 1.19.7" ["elixir pin 1.19.6 below floor 1.19.7" "image Dockerfile:2 Elixir 1.19.6 below floor 1.19.7"]
    let r = (do $run ["--root" (fixture $dir "ex-above" (mise-toml "28.5.0.8" "1.19.10-otp-28") {Dockerfile: (dockerfile "28.5.0.8" "1.19.10")})] $ok8)
    assert equal $r.exit_code 0 $"E8 elixir 1.19.10 \(numeric above floor\) must pass; stdout: ($r.stdout) stderr: ($r.stderr)"
    assert ($r.last | str ends-with "elixir_floor=1.19.6 elixir_pin=1.19.10-otp-28 elixir_images=Dockerfile:1.19.10") $"E8 PASS line names the elixir pin; got: ($r.last)"

    # ---- defaults: no --root, no --floor; real repo files; fake erl prints the repo pin.
    let repo_pin = (erlang-pin (open ($root | path join "mise.toml")))
    assert ($repo_pin != null) "the repo mise.toml must pin erlang"
    let repo_elixir = (elixir-pin (open ($root | path join "mise.toml")))
    assert ($repo_elixir != null) "the repo mise.toml must pin elixir"
    let r = (do $run [] {FAKE_OTP: $repo_pin})
    assert equal $r.exit_code 0 $"defaults against the real repo must pass; stdout: ($r.stdout) stderr: ($r.stderr)"
    assert equal $r.last $"PASS audit:otp floor=($floor) pin=($repo_pin) runtime=($repo_pin) images=Dockerfile:($repo_pin) elixir_floor=1.19.6 elixir_pin=($repo_elixir) elixir_images=Dockerfile:($repo_elixir | split row "-" | first)" "defaults PASS line"
    assert equal $r.erl_cwd ($root | path expand) "with no --root, erl must run with cwd = the repo root, not the caller's cwd"
  }
}

# ---- E7 real toolchain: the repo passes with the erl mise installs. Needs
# `mise exec` / `mise run` (see the header).
def real-toolchain-cases [] {
  let script = ($root | path join "scripts" "otp-audit.nu")
  let r = (do { cd $root; ^$nu.current-exe -n $script } | complete)
  assert equal $r.exit_code 0 $"E7 `nu scripts/otp-audit.nu` on the repo must exit 0 under the mise toolchain; stdout: ($r.stdout) stderr: ($r.stderr)"
  assert ((last-line $r.stdout) | str starts-with $"PASS audit:otp floor=($floor) ") $"E7 PASS line; got: ($r.stdout)"
}

def main [] {
  version-below-cases
  erlang-pin-cases
  otp-version-from-file-cases
  dockerfile-otp-cases
  elixir-pin-cases
  dockerfile-elixir-cases
  otp-verdict-cases
  elixir-verdict-cases
  end-to-end-cases
  real-toolchain-cases
  print "PASS test:otp-audit"
}
