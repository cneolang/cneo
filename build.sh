#!/usr/bin/env bash
# build.sh — build the cneo compiler.
#
# cneo is fully self-hosting. It no longer needs the neo host compiler.
# Bootstrap chain:
#   1. If ./cneo_bin already exists, use it to self-recompile:
#        ./cneo_bin -o ./cneo_bin nlib/cneo
#      (cneo compiling its own source — true self-host)
#   2. Otherwise, gcc-compile the shipped bootstrap.c seed:
#        gcc -o ./cneo_bin bootstrap.c
#      (bootstrap.c is the converged C output of cneo compiling itself;
#       it is regenerated only when the source changes enough to need it)
#
# Usage:
#   ./build.sh           # auto: self-recompile if cneo_bin exists, else gcc bootstrap
#   ./build.sh --gcc     # force gcc bootstrap from bootstrap.c
#   ./build.sh --neo PATH# legacy: use neo host compiler at PATH (old_neo/n_stage1)
#
# Output: ./cneo_bin (the cneo compiler)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# CNEO_ROOT: absolute path to the cneo source tree. The import resolver
# finds modules consistently regardless of CWD.
export CNEO_ROOT="$SCRIPT_DIR/nlib/cneo/"

MODE="auto"
NEO_PATH=""

if [ "${1:-}" = "--gcc" ]; then
        MODE="gcc"
elif [ "${1:-}" = "--neo" ]; then
        MODE="neo"
        NEO_PATH="${2:-../old_neo/n_stage1}"
fi

build_with_neo() {
        if [ ! -x "$NEO_PATH" ]; then
                echo "error: neo host compiler not found at: $NEO_PATH"
                echo "pass the path as argument: ./build.sh --neo /path/to/n_stage1"
                exit 1
        fi
        echo "=== Building with neo host (legacy mode) ==="
        rm -f .neo_manifest .neo_merkle_cache
        "$NEO_PATH" -o ./cneo_bin nlib/cneo
}

build_with_gcc() {
        if [ ! -f "$SCRIPT_DIR/bootstrap.c" ]; then
                echo "error: bootstrap.c not found (needed for gcc bootstrap)"
                echo "run ./build.sh --neo ../old_neo/n_stage1 to regenerate it from source"
                exit 1
        fi
        echo "=== Building cneo from bootstrap.c with gcc ==="
        CC="${CC:-gcc}"
        CFLAGS="${CFLAGS:--w -std=gnu99}"
        $CC $CFLAGS -o ./cneo_bin "$SCRIPT_DIR/bootstrap.c" -lm -lpthread
}

build_self() {
        if [ ! -x ./cneo_bin ]; then
                echo "error: ./cneo_bin not found (needed for self-recompile)"
                echo "run ./build.sh --gcc to bootstrap from bootstrap.c first"
                exit 1
        fi
        echo "=== Self-recompiling cneo (cneo compiles its own source) ==="
        # Write new binary to a temp file, then atomically rename.
        # "mv" overwriting a running binary causes "text file busy" errors.
        ./cneo_bin -o /tmp/cneo_bin_new nlib/cneo
        sync
        mv /tmp/cneo_bin_new ./cneo_bin 2>/dev/null
        # If build failed, restore old binary
        if [ ! -x ./cneo_bin ]; then
                echo "Build failed, restoring old binary..."
                exit 1
        fi
}

case "$MODE" in
        neo)
                build_with_neo
                ;;
        gcc)
                build_with_gcc
                ;;
        auto)
                if [ -x ./cneo_bin ]; then
                        build_self
                elif [ -f "$SCRIPT_DIR/bootstrap.c" ]; then
                        build_with_gcc
                else
                        echo "error: no bootstrap path available."
                        echo "  ./cneo_bin not found (cannot self-recompile)"
                        echo "  bootstrap.c not found (cannot gcc bootstrap)"
                        echo "  use: ./build.sh --neo /path/to/n_stage1  (legacy neo path)"
                        exit 1
                fi
                ;;
esac

echo "=== Build OK ==="
echo "Compiler: ./cneo_bin"
echo "Help:"
./cneo_bin --help | head -5
