#!/usr/bin/env bash
# test-all.sh: every Intervally test suite in one command, each on a simulator of its own.
#
#   scripts/test-all.sh                  the unit and UI suites, then the Release check
#   scripts/test-all.sh --unit-only      the watch and iPhone unit suites (both run SyncTests)
#   scripts/test-all.sh --ui-only        the iPhone UI tests, on an iPhone and on an iPad
#   scripts/test-all.sh --release-check  builds Release once; fails if a QA launch flag is in it
#   --unsigned                           with any of them: no team or certificate needed (CI)
#
# The simulators are the script's own, found by name and made when missing:
# Intervally-QA-iPhone, Intervally-QA-iPad and Intervally-QA-Watch, with their UDIDs kept in
# .qa-sims. It never touches another simulator, never shuts them all down, and keeps at most
# two of its own booted, as the Mac is shared. Tests run one at a time on one destination
# (-parallel-testing-enabled NO). Each suite's log and result bundle go to
# build/test-results/<time>/, a table at the end says how each went, and the exit status is
# 1 if any failed.
set -euo pipefail

cd "$(dirname "$0")/.."
SIMS_FILE=.qa-sims
RESULTS=build/test-results/$(date +%Y%m%d-%H%M%S)
DERIVED=build/DerivedData

usage() {
  sed -n '2,8s/^# \{0,1\}//p' "$0"
}

unit=0 ui=0 release=0 unsigned=0
for arg in "$@"; do
  case $arg in
    --unit-only) unit=1 ;;
    --ui-only) ui=1 ;;
    --release-check) release=1 ;;
    --unsigned) unsigned=1 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done
if [ $unit -eq 0 ] && [ $ui -eq 0 ] && [ $release -eq 0 ]; then
  unit=1 ui=1 release=1
fi

for tool in xcodebuild xcodegen python3 git; do
  if ! command -v $tool > /dev/null; then
    echo "test-all.sh needs $tool$([ $tool = xcodegen ] && echo ' (brew install xcodegen)')." >&2
    exit 2
  fi
done

# Signed to run locally with no team, as a simulator build is signed anyway, so a Mac without
# the team's account can build. The simulator still gets the app's entitlements, which the
# StoreKit tests need (get-task-allow), as it would not with signing turned off altogether.
SIGNING=()
if [ $unsigned -eq 1 ]; then
  SIGNING=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
fi

# MARK: - Simulators

# The script's simulators, read from `simctl list -j`: Python's json is the one parser every
# Mac with Xcode has.
#   state <udid>                                  Booted, Shutdown, ... or Missing
#   find <name> <platform> <family> <sdk> <recorded udid> <device type>...
#                                                 "use <udid>", or "create <type> <runtime>"
read -r -d '' SIMS_PY <<'PY' || true
import json, subprocess, sys

# The whole listing: `list devices runtimes` would list devices only, and read "runtimes" as
# a search term.
listing = json.loads(subprocess.run(
    ["xcrun", "simctl", "list", "-j"], check=True, capture_output=True, text=True).stdout)
devices = [dict(device, runtime=runtime) for runtime, group in listing["devices"].items() for device in group]
command, args = sys.argv[1], sys.argv[2:]

def version(text):
    return tuple(int(part) for part in text.split(".") if part.isdigit())

if command == "state":
    # Only the script's own: any other UDID reads as missing, so whatever .qa-sims holds,
    # no other simulator is ever shut down.
    print(next((device["state"] for device in devices
                if device["udid"] == args[0] and device["name"].startswith("Intervally-QA-")), "Missing"))
    sys.exit()

name, platform, family, sdk, recorded, wanted = args[0], args[1], args[2], version(args[3]), args[4], args[5:]
# Runtimes this Xcode can run: none newer than its SDK, a patch release of it aside.
runtimes = [runtime for runtime in listing["runtimes"]
            if runtime.get("platform") == platform and runtime.get("isAvailable") and version(runtime["version"])[:2] <= sdk[:2]]
usable = {runtime["identifier"] for runtime in runtimes}
mine = [device for device in devices
        if device["name"] == name and device.get("isAvailable") and device["runtime"] in usable]
mine.sort(key=lambda device: device["udid"] != recorded)
if mine:
    print("use", mine[0]["udid"])
    sys.exit()
if not runtimes:
    sys.exit(f"no {platform} simulator runtime up to {args[3]} is installed (Xcode > Settings > Components)")
runtime = max(runtimes, key=lambda runtime: version(runtime["version"]))
types = runtime.get("supportedDeviceTypes") or listing["devicetypes"]
types = [kind for kind in types if kind.get("productFamily") == family] or types
by_name = {kind["name"]: kind["identifier"] for kind in types}
kind = next((by_name[wanted_name] for wanted_name in wanted if wanted_name in by_name), types[-1]["identifier"])
print("create", kind, runtime["identifier"])
PY

sims() {
  python3 -I -c "$SIMS_PY" "$@"
}

# own <name> <platform> <family> <sdk> <device type>...: the UDID of the script's simulator
# of that name, made with the newest runtime this Xcode runs if it has none it can use, and
# kept in .qa-sims. One this Xcode can't run is left as it is.
own() {
  local name=$1 platform=$2 family=$3 sdk=$4 recorded answer udid kind runtime others
  shift 4
  recorded=$(awk -v name="$name" '$1 == name { print $2 }' "$SIMS_FILE" 2> /dev/null || true)
  answer=$(sims find "$name" "$platform" "$family" "$sdk" "${recorded:-none}" "$@") || return 1
  case $answer in
    use\ *) udid=${answer#use } ;;
    create\ *)
      read -r _ kind runtime <<< "$answer"
      echo "Making $name ($kind, $runtime)" >&2
      udid=$(xcrun simctl create "$name" "$kind" "$runtime") || return 1
      ;;
  esac
  if [ -z "${udid:-}" ]; then return 1; fi
  others=$(grep -v "^$name " "$SIMS_FILE" 2> /dev/null || true)
  if [ -n "$others" ]; then
    printf '%s\n%s %s\n' "$others" "$name" "$udid" > "$SIMS_FILE"
  else
    printf '%s %s\n' "$name" "$udid" > "$SIMS_FILE"
  fi
  echo "$udid"
}

BOOTED=""      # the simulators this run booted, shut down again at the end
XCODEBUILD=""  # the xcodebuild under way, stopped too if the script is

# How many of the script's own simulators, this run's or an earlier one's, are booted.
booted_count() {
  local count=0 udid
  for udid in $(awk '{ print $2 }' "$SIMS_FILE"); do
    if [ "$(sims state "$udid")" = Booted ]; then count=$((count + 1)); fi
  done
  echo $count
}

# boot <udid>: booted and ready, with no more than two of the script's own booted at once.
boot() {
  local udid=$1 other
  if [ "$(sims state "$udid")" = Booted ]; then return 0; fi
  for other in $(awk '{ print $2 }' "$SIMS_FILE"); do
    if [ "$(booted_count)" -lt 2 ]; then break; fi
    if [ "$other" != "$udid" ] && [ "$(sims state "$other")" = Booted ]; then
      xcrun simctl shutdown "$other"
      BOOTED=${BOOTED/ $other/}
    fi
  done
  xcrun simctl bootstatus "$udid" -b > /dev/null
  BOOTED="$BOOTED $udid"
}

cleanup() {
  local udid
  # Run in the background, xcodebuild ignores Control-C: left alone it would hold the Mac
  # and a simulator after the script had gone.
  if [ -n "$XCODEBUILD" ]; then
    pkill -P "$XCODEBUILD" 2> /dev/null || true
    kill "$XCODEBUILD" 2> /dev/null || true
  fi
  for udid in $BOOTED; do
    xcrun simctl shutdown "$udid" > /dev/null 2>&1 || true
  done
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# MARK: - xcodebuild

# How each kind of run reports: the line that ends it, and the lines that say it passed and
# failed. A unit run ends with Swift Testing's summary (its XCTest part runs first and is
# empty), a UI run with XCTest's.
FAILED_LINE="✘ Test .*(failed|recorded an issue)|Test Case .* failed|\*\* (TEST|BUILD)( EXECUTE)? FAILED \*\*|Testing failed:"
end_line() {
  case $1 in
    unit) echo "Test run with [0-9]+ tests?.* (passed|failed)|\*\* TEST (EXECUTE )?(SUCCEEDED|FAILED) \*\*|Testing failed:" ;;
    ui) echo "Test Suite '(All|Selected) tests' (passed|failed)|\*\* TEST (EXECUTE )?(SUCCEEDED|FAILED) \*\*|Testing failed:" ;;
    build) echo "\*\* BUILD (SUCCEEDED|FAILED) \*\*" ;;
  esac
}
passed_line() {
  case $1 in
    unit) echo "Test run with [0-9]+ tests?.* passed|\*\* TEST (EXECUTE )?SUCCEEDED \*\*" ;;
    ui) echo "Test Suite '(All|Selected) tests' passed|\*\* TEST (EXECUTE )?SUCCEEDED \*\*" ;;
    build) echo "\*\* BUILD SUCCEEDED \*\*" ;;
  esac
}

# xcode <kind> <log> <xcodebuild arguments>...: xcodebuild, with its output in the log. It
# is stopped once its last result is in and the log has been quiet for 30 seconds (Xcode
# 27.1 RC's test runner can hang after the last test), or after 20 minutes with no output
# at all (a build service that died under memory pressure leaves it waiting for good). Sets
# STATUS: xcodebuild's own, or what the log says when it had to be stopped.
xcode() {
  local kind=$1 log=$2 size=0 now quiet=0 stopped=""
  shift 2
  xcodebuild "$@" > "$log" 2>&1 &
  local pid=$!
  XCODEBUILD=$pid
  while kill -0 $pid 2> /dev/null; do
    sleep 5
    now=$(wc -c < "$log" | tr -d ' ')
    if [ "$now" -ne "$size" ]; then size=$now quiet=0; else quiet=$((quiet + 5)); fi
    if [ $quiet -ge 30 ] && grep -qE "$(end_line "$kind")" "$log"; then stopped=finished; fi
    if [ $quiet -ge 1200 ]; then stopped=hung; fi
    if [ -n "$stopped" ]; then
      pkill -P $pid 2> /dev/null || true
      kill $pid 2> /dev/null || true
      break
    fi
  done
  STATUS=0
  wait $pid 2> /dev/null || STATUS=$?
  XCODEBUILD=""
  case $stopped in
    finished)
      echo "(test-all.sh stopped xcodebuild, which didn't exit after its result)" >> "$log"
      if grep -qE "$(passed_line "$kind")" "$log" && ! grep -qE "$FAILED_LINE" "$log"; then STATUS=0; else STATUS=1; fi
      ;;
    hung)
      echo "(test-all.sh stopped xcodebuild after 20 minutes with no output)" >> "$log"
      STATUS=1
      ;;
  esac
}

# What the log says ran: Swift Testing's count, else XCTest's.
counted() {
  local log=$1 line
  line=$(grep -oE "Test run with [0-9]+ tests?" "$log" | tail -1 || true)
  if [ -n "$line" ] && [ "${line#Test run with 0 }" = "$line" ]; then
    echo "${line#Test run with }"
    return
  fi
  line=$(grep -E "Executed [0-9]+ tests?, with" "$log" | tail -1 || true)
  if [ -n "$line" ]; then
    echo "$line" | sed -E 's/.*Executed ([0-9]+ tests?), with (([0-9]+) tests? skipped and )?([0-9]+) failures?.*/\1, \3 skipped, \4 failed/; s/,  skipped//'
  fi
}

ROWS=()
FAILURES=0
row() {
  local status=$1 suite=$2 where=$3 detail=$4 seconds=$5 result=PASS
  if [ "$status" -ne 0 ]; then result=FAIL FAILURES=$((FAILURES + 1)); fi
  ROWS+=("$(printf '%-14s %-21s %-6s %-30s %dm%02ds' "$suite" "$where" "$result" "$detail" $((seconds / 60)) $((seconds % 60)))")
}

# suite <kind> <name> <scheme> <simulator name> <udid>
suite() {
  local kind=$1 name=$2 scheme=$3 sim=$4 udid=$5 started log key
  key=$(echo "$name" | tr ' A-Z' '-a-z')
  log=$RESULTS/$key.log
  echo "▸ $name on $sim (log: $log)"
  boot "$udid"
  started=$(date +%s)
  xcode "$kind" "$log" test -project Intervally.xcodeproj -scheme "$scheme" -destination "id=$udid" \
    -parallel-testing-enabled NO -resultBundlePath "$RESULTS/$key.xcresult" -derivedDataPath "$DERIVED" \
    ${SIGNING[@]+"${SIGNING[@]}"}
  row $STATUS "$name" "$sim" "$(counted "$log")" $(($(date +%s) - started))
  if [ $STATUS -ne 0 ]; then
    grep -E "$FAILED_LINE|error:" "$log" | head -15 | sed 's/^/    /' || true
  fi
}

# MARK: - Release check

# Swift keeps a string of 15 bytes or fewer inside the instructions that build it, not as
# text, so `strings` alone would miss "-qaPro". On arm64 those are MOVZ, MOVK or ORR runs
# into one register, rebuilt here; a longer string, a literal pool and x86_64's movabs keep
# the bytes together and are found as they are.
#   <bundle> <flag name>...   prints each binary that holds one; exits 1 if any does
read -r -d '' SCAN_PY <<'PY' || true
import os, struct, sys

FAT, FAT_64, MACHO, MACHO_64, ARM64 = 0xCAFEBABE, 0xCAFEBABF, 0xFEEDFACE, 0xFEEDFACF, 0x0100000C

def slices(data):
    magic = struct.unpack_from(">I", data)[0]
    if magic not in (FAT, FAT_64):
        yield data
        return
    for index in range(struct.unpack_from(">I", data, 4)[0]):
        if magic == FAT:
            offset, size = struct.unpack_from(">II", data, 8 + index * 20 + 8)
        else:
            offset, size = struct.unpack_from(">QQ", data, 8 + index * 32 + 8)
        yield data[offset:offset + size]

def arm64_code(macho):
    if len(macho) < 32 or struct.unpack_from("<Ii", macho) != (MACHO_64, ARM64):
        return b""
    commands, offset = struct.unpack_from("<I", macho, 16)[0], 32
    for _ in range(commands):
        command, size = struct.unpack_from("<II", macho, offset)
        if command == 0x19:  # LC_SEGMENT_64
            for index in range(struct.unpack_from("<I", macho, offset + 64)[0]):
                section = offset + 72 + index * 80
                names = macho[section:section + 16].rstrip(b"\0"), macho[section + 16:section + 32].rstrip(b"\0")
                if names == (b"__text", b"__TEXT"):
                    length, start = struct.unpack_from("<QI", macho, section + 40)
                    return macho[start:start + length]
        offset += size
    return b""

def bitmask(n, immr, imms):
    """An ORR immediate's value (the ARM ARM's DecodeBitMasks), or None."""
    length = ((n << 6) | (~imms & 0x3F)).bit_length() - 1
    if length < 1:
        return None
    size = 1 << length
    ones, rotate = (imms & (size - 1)) + 1, immr & (size - 1)
    if ones == size:
        return None
    element = (1 << ones) - 1
    element = ((element >> rotate) | (element << (size - rotate))) & ((1 << size) - 1)
    return sum(element << shift for shift in range(0, 64, size))

def immediates(code):
    """Each value a register holds after a MOVZ, MOVN, MOVK or ORR with an immediate."""
    registers = [None] * 32
    for (word,) in struct.iter_unpack("<I", code[: len(code) // 4 * 4]):
        rd, width = word & 31, (1 << 64) - 1 if word >> 31 else 0xFFFFFFFF
        if word & 0x1F800000 == 0x12800000:  # move wide
            opc, shift = (word >> 29) & 3, ((word >> 21) & 3) * 16
            chunk = ((word >> 5) & 0xFFFF) << shift
            if opc == 2:
                value = chunk
            elif opc == 0:
                value = ~chunk
            elif opc == 3 and registers[rd] is not None:
                value = (registers[rd] & ~(0xFFFF << shift)) | chunk
            else:
                registers[rd] = None
                continue
        elif word & 0x7F800000 == 0x32000000 and (word >> 5) & 31 == 31:  # ORR from zr
            value = bitmask((word >> 22) & 1, (word >> 16) & 0x3F, (word >> 10) & 0x3F)
            if value is None:
                continue
        else:
            continue
        registers[rd] = value & width
        yield registers[rd]

def first_word(text):
    return int.from_bytes(text[:8].ljust(8, b"\0"), "little")

def flags_in(data, names):
    forms = {form: name for name in names for form in (b"-" + name.encode(), name.encode())}
    words = {first_word(form): name for form, name in forms.items()}
    found = set()
    for macho in slices(data):
        found |= {name for form, name in forms.items() if form in macho or (len(form) > 8 and form[:8] in macho)}
        found |= {words[value] for value in immediates(arm64_code(macho)) if value in words}
    return sorted(found)

def is_macho(path):
    with open(path, "rb") as file:
        head = file.read(4)
    return len(head) == 4 and (struct.unpack(">I", head)[0] in (FAT, FAT_64) or struct.unpack("<I", head)[0] in (MACHO, MACHO_64))

# The scan must see both forms, or a clean result would mean nothing.
probe = struct.pack("<4I", 0xD28E25A3, 0xF2AA8C23, 0xF2CE6CA3, 0xF2E62E83)  # "-qaTest1" in x3
assert first_word(b"-qaTest1") in set(immediates(probe)), "the scan can't read MOVZ/MOVK"
assert 0x5555555555555555 in set(immediates(struct.pack("<I", 0xB200F3E0))), "the scan can't read ORR"

bundle, names = sys.argv[1], sys.argv[2:]
binaries, leaks = 0, 0
for folder, _, files in os.walk(bundle):
    for file in files:
        path = os.path.join(folder, file)
        if os.path.islink(path) or not is_macho(path):
            continue
        binaries += 1
        with open(path, "rb") as handle:
            found = flags_in(handle.read(), names)
        for name in found:
            print(f"    {os.path.relpath(path, bundle)}: -{name}")
        leaks += len(found)
if binaries == 0:
    sys.exit(f"    no binaries in {bundle}")
print(f"    {binaries} binaries, {len(names)} QA flags looked for, {leaks} found")
sys.exit(1 if leaks else 0)
PY

# The QA flags are named in the sources, so a new one is looked for without a list to keep.
release_check() {
  local log=$RESULTS/release-check.log started flags app
  echo "▸ Release check (log: $log)"
  started=$(date +%s)
  flags=$(git grep --untracked -ohE '"-?qa[A-Z][A-Za-z0-9]*"' -- '*.swift' | tr -d '"' | sed 's/^-//' | sort -u || true)
  if [ -z "$flags" ]; then
    echo "    no QA flags found in the sources: nothing to look for" | tee -a "$log"
    row 1 "Release check" "Release build" "no flags to look for" $(($(date +%s) - started))
    return
  fi
  # One arm64 slice: the instructions the scan reads, built for the simulator, which needs
  # no certificate. The code is the App Store build's: nothing in the app depends on the
  # simulator, and Release defines no DEBUG.
  xcode build "$log" build -project Intervally.xcodeproj -scheme IntervallyPhone -configuration Release \
    -destination "generic/platform=iOS Simulator" -derivedDataPath build/release-check ARCHS=arm64 \
    ${SIGNING[@]+"${SIGNING[@]}"}
  if [ $STATUS -ne 0 ]; then
    grep -E "error:" "$log" | head -15 | sed 's/^/    /' || true
    row 1 "Release check" "Release build" "build failed" $(($(date +%s) - started))
    return
  fi
  app=build/release-check/Build/Products/Release-iphonesimulator/IntervallyPhone.app
  STATUS=0
  # shellcheck disable=SC2086 # one argument per flag
  python3 -I -c "$SCAN_PY" "$app" $flags | tee -a "$log" || STATUS=$?
  local detail="no QA flags"
  if [ $STATUS -ne 0 ]; then detail="QA flags in Release"; fi
  row $STATUS "Release check" "Release build" "$detail" $(($(date +%s) - started))
}

# MARK: - Run

mkdir -p "$RESULTS"
echo "▸ xcodegen generate"
xcodegen generate --quiet

if [ $unit -eq 1 ] || [ $ui -eq 1 ]; then
  ios=$(xcrun --sdk iphonesimulator --show-sdk-version)
  if [ $unit -eq 1 ]; then
    watch_sim=$(own Intervally-QA-Watch watchOS "Apple Watch" "$(xcrun --sdk watchsimulator --show-sdk-version)" \
      "Apple Watch Series 11 (46mm)" "Apple Watch Series 10 (46mm)")
  fi
  phone_sim=$(own Intervally-QA-iPhone iOS iPhone "$ios" "iPhone 17 Pro" "iPhone 16 Pro")
  if [ $ui -eq 1 ]; then
    ipad_sim=$(own Intervally-QA-iPad iOS iPad "$ios" "iPad Pro 13-inch (M5)" "iPad Pro 13-inch (M4)")
  fi
fi

if [ $unit -eq 1 ]; then
  suite unit "watch unit" Intervally Intervally-QA-Watch "$watch_sim"
  suite unit "iPhone unit" IntervallyPhone Intervally-QA-iPhone "$phone_sim"
fi
if [ $ui -eq 1 ]; then
  suite ui "iPhone UI" IntervallyPhoneUITests Intervally-QA-iPhone "$phone_sim"
  suite ui "iPad UI" IntervallyPhoneUITests Intervally-QA-iPad "$ipad_sim"
fi
if [ $release -eq 1 ]; then
  release_check
fi

echo
printf '%-14s %-21s %-6s %-30s %s\n' Suite Where Result Tests Time
for line in ${ROWS[@]+"${ROWS[@]}"}; do
  echo "$line"
done
echo "Results: $RESULTS"
if [ $FAILURES -gt 0 ]; then
  exit 1
fi
