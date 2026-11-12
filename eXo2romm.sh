#!/usr/bin/env bash
#
# eXo2romm.sh — repackage eXoDOS zips with a corrected dosbox.conf
#
# For each zip given on the command line:
#   1. Determine the single top-level directory the zip unzips into (e.g. "Abmisthe").
#   2. Find "$DOS_DIR/<top>/dosbox.conf" (the !dos template tree).
#   3. Edit a COPY of that conf: on @?mount / @?imgmount / @?boot lines, rewrite
#        .\eXoDOS\<top>\...   ->   .\...        (strip the game-dir component)
#        .\eXoDOS\            ->   .\           (bare mount of the pack root)
#      Comments (#/rem) and tokens pointing at a different directory are left alone.
#   4. Copy the zip to OUTPUT_DIR (never touching the original) and add the edited
#      conf inside it as "<top>/dosbox.conf".
#   5. Remove temp files; problems are warned on stderr and appended to ERROR_LOG.
#
# Portability: bash + coreutils + unzip/zip only. Set the three variables below
# (or override via environment) for the machine the script actually runs on.

set -u

# ------- configuration: adjust these on the target machine -------------------
DOS_DIR="${DOS_DIR:-/data/eXoDOS/Content/eXo/eXoDOS/!dos}"   # !dos template tree
OUTPUT_DIR="${OUTPUT_DIR:-/var/lib/romm/library/roms/dos}"                 # repackaged zips land here
ERROR_LOG="${ERROR_LOG:-$OUTPUT_DIR/eXo2romm-errors.log}"            # warnings log
# -----------------------------------------------------------------------------

usage() { echo "Usage: $0 <zipfile> [zipfile ...]" >&2; exit 2; }
[ $# -ge 1 ] || usage

[ -d "$DOS_DIR" ] || { echo "ERROR: DOS_DIR does not exist: $DOS_DIR" >&2; exit 1; }
mkdir -p "$OUTPUT_DIR" || exit 1

warn() {
    printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$ERROR_LOG" >&2
}

# Rewrite .\eXoDOS\ tokens on keyword lines. Literal (non-regex) matching:
# needle/top are compared lowercased via index(); no metachar risk in dir names.
rewrite_conf() {
    local conf="$1" top="$2"
    TOP="$top" awk '
        BEGIN {
            top    = ENVIRON["TOP"]
            ltop   = tolower(top)
            needle = ".\\exodos\\"          # lowercase token we search for
            nlen   = length(needle)
        }
        {
            line = $0
            # keyword-line probe: optional leading blanks, optional @, then
            # mount/imgmount/boot as the first word (case-insensitive)
            probe = tolower(line)
            sub(/^[ \t]*@[ \t]*/, "", probe)
            if (probe !~ /^(mount|imgmount|boot)([ \t]|$)/) { print; next }

            out = ""; rest = line; lc = tolower(rest)
            while ((p = index(lc, needle)) > 0) {
                pre    = substr(rest, 1, p - 1)
                after  = substr(rest, p + nlen)          # text after the token
                cafter = substr(lc,    p + nlen)
                cut    = -1
                if (substr(cafter, 1, length(ltop)) == ltop) {
                    nxt = substr(cafter, length(ltop) + 1, 1)
                    if (nxt == "\\")                          cut = length(ltop) + 1
                    else if (nxt == "" || nxt == " " || nxt == "\t" ||
                             nxt == "\"" || nxt == "\r")      cut = length(ltop)
                }
                if (cut >= 0) {                            # .\eXoDOS\<top>...  ->  .\...
                    out  = out pre ".\\"
                    rest = substr(after, cut + 1)
                    lc   = tolower(rest)
                } else {
                    nxt2 = substr(cafter, 1, 1)
                    if (nxt2 == "" || nxt2 == " " || nxt2 == "\t" ||
                        nxt2 == "\"" || nxt2 == "\r") {     # bare .\eXoDOS\  ->  .\
                        out  = out pre ".\\"
                        rest = after
                        lc   = tolower(rest)
                    } else {                                 # some other dir: keep
                        out  = out pre substr(rest, p, nlen)
                        rest = substr(rest, p + nlen)
                        lc   = tolower(rest)
                    }
                }
            }
            print out rest
        }
    ' "$conf" > "$conf.new" && mv "$conf.new" "$conf"
}

processed=0; skipped=0

for zip in "$@"; do
    tag="$(basename -- "$zip")"

    if [ ! -f "$zip" ]; then
        warn "SKIP [$tag]: file not found: $zip"; skipped=$((skipped+1)); continue
    fi

    # --- 1. single top-level directory the zip unzips into -------------------
    listing="$(unzip -Z1 -- "$zip" 2>/dev/null)" || { warn "SKIP [$tag]: unreadable zip"; skipped=$((skipped+1)); continue; }
    [ -n "$listing" ] || { warn "SKIP [$tag]: empty zip"; skipped=$((skipped+1)); continue; }
    tops="$(printf '%s\n' "$listing" | awk -F/ '{print $1}' | grep -v '^$' | sort -u)"
    if [ "$(printf '%s\n' "$tops" | wc -l)" -ne 1 ]; then
        warn "SKIP [$tag]: zip does not unzip into a single top-level directory"; skipped=$((skipped+1)); continue
    fi
    top="$tops"
    if ! printf '%s\n' "$listing" | grep -q '/'; then
        warn "SKIP [$tag]: files sit at the zip root (no subdirectory)"; skipped=$((skipped+1)); continue
    fi

    # --- 2. matching dosbox.conf template ------------------------------------
    src_conf="$DOS_DIR/$top/dosbox.conf"
    if [ ! -f "$src_conf" ]; then
        warn "SKIP [$tag]: no dosbox.conf found in \"$DOS_DIR/$top\""; skipped=$((skipped+1)); continue
    fi

    # --- 3+4. edit a copy, clone the zip, graft the conf in ------------------
    out_zip="$OUTPUT_DIR/$(basename -- "$zip")"
    if [ -e "$out_zip" ]; then
        echo "SKIP [$tag]: output already exists: $out_zip (left untouched)"
        skipped=$((skipped+1)); continue
    fi

    tmpdir="$(mktemp -d)" || { warn "SKIP [$tag]: mktemp failed"; skipped=$((skipped+1)); continue; }

    mkdir -p "$tmpdir/$top"
    if ! cp -- "$src_conf" "$tmpdir/$top/dosbox.conf" || ! rewrite_conf "$tmpdir/$top/dosbox.conf" "$top"; then
        warn "SKIP [$tag]: could not prepare edited dosbox.conf"
        rm -rf "$tmpdir"; skipped=$((skipped+1)); continue
    fi

    if ! cp -- "$zip" "$out_zip" || ! ( cd "$tmpdir" && zip -q "$out_zip" "$top/dosbox.conf" ); then
        warn "SKIP [$tag]: failed to write output zip"
        rm -f -- "$out_zip"; rm -rf "$tmpdir"; skipped=$((skipped+1)); continue
    fi
    rm -rf "$tmpdir"

    echo "OK  [$tag]  ->  $out_zip  (conf from $top/)"
    processed=$((processed+1))
done

echo "----  $processed processed, $skipped skipped  (log: $ERROR_LOG)"
[ "$skipped" -eq 0 ]
