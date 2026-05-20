#!/usr/bin/env bash
# Fake starling CLI for tests. Branches grow per task as more commands are
# wrapped. Keep behavior deterministic — no network, no real files outside
# whatever args specify.
set -u
case "${1:-}" in
  -V|--version)
    echo "3.7.53"
    ;;
  whoami)
    echo "{\"email\":\"test@bytedance.com\",\"accessKey\":\"${STARLING_AK:-}\"}"
    ;;
  fail)
    echo "boom" 1>&2
    exit 1
    ;;
  download)
    shift
    DIST=""
    LOCALES=""
    MODE=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -d) DIST="$2"; shift 2 ;;
        -l) LOCALES="$2"; shift 2 ;;
        -m) MODE="$2"; shift 2 ;;
        -c) shift 2 ;;
        --disable-browser) shift ;;
        *) shift ;;
      esac
    done
    mkdir -p "${DIST}/common"
    IFS=',' read -ra LS <<< "${LOCALES:-zh}"
    for L in "${LS[@]}"; do
      echo "{\"hello\":\"你好\",\"world\":\"世界\"}" > "${DIST}/common/${L}.json"
    done
    echo "downloaded to ${DIST}"
    ;;
  upload)
    shift
    UPATH=""
    TGT=0
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -u) UPATH="$2"; shift 2 ;;
        -t) TGT=1; shift ;;
        -c) shift 2 ;;
        --disable-browser) shift ;;
        *) shift ;;
      esac
    done
    [ -f "$UPATH" ] || { echo "no such file $UPATH" 1>&2; exit 3; }
    echo "uploaded ${UPATH} target=${TGT}"
    ;;
  scan)
    shift
    OUT=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -o) OUT="$2"; shift 2 ;;
        --fallback|--disable-browser) shift ;;
        -c|-e|-m) shift 2 ;;
        *) shift ;;
      esac
    done
    OUT="${OUT:-./starling}"
    mkdir -p "$OUT" "$OUT/common"
    cat > "$OUT/handled.json" <<'JSON'
{"items":[{"key":"x-name","value":"姓名","raw":"","file":"src/app.tsx","line":12,"column":5},
          {"key":"x-hello","value":"你好{{user}}","raw":"","file":"src/app.tsx","line":20,"column":3}]}
JSON
    echo '{"x-name":"姓名","x-hello":"你好{{user}}"}' > "$OUT/common/zh.json"
    echo '{"x-name":"Name","x-hello":"Hello {{user}}"}' > "$OUT/common/en.json"
    echo "scan done → $OUT"
    ;;
  translate)
    TYPE="$2"
    ENTRY="$3"
    LOCALE=""
    DIST=""
    shift 3
    # Optional positional dist (next arg, only if it doesn't start with `-`).
    if [ -n "${1:-}" ] && [[ "$1" != -* ]]; then
      DIST="$1"; shift
    fi
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -l) LOCALE="$2"; shift 2 ;;
        -t|--starling) shift ;;
        --depth) shift 2 ;;
        *) shift ;;
      esac
    done
    [ -f "$ENTRY" ] || { echo "entry not found: $ENTRY" 1>&2; exit 3; }
    EXT="${ENTRY##*.}"
    BASE_NAME="$(basename "${ENTRY%.*}")"
    OUTDIR="${DIST:-$(dirname "$ENTRY")}"
    mkdir -p "$OUTDIR"
    OUT="${OUTDIR}/${BASE_NAME}-${LOCALE}.${EXT}"
    cp "$ENTRY" "$OUT"
    echo "$OUT"
    ;;
  *)
    echo "unknown $@" 1>&2
    exit 2
    ;;
esac
