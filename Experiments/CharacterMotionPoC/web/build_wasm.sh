#!/bin/sh
# Compiles the CatBehavior engine (unchanged sources) plus wasm/Exports.swift into web/build/catbehavior.wasm.
# Needs a Swift toolchain with the wasm32-unknown-wasi standard library (SwiftWasm 6.0.3 was used; see README).
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
SWIFTC="${SWIFTC:-swiftc}"
# WASI libc sysroot shipped with the toolchain (usr/share/wasi-sysroot next to usr/bin/swiftc)
SYSROOT="${WASI_SYSROOT:-$(cd "$(dirname "$(command -v "$SWIFTC")")/../share/wasi-sysroot" 2>/dev/null && pwd)}"
mkdir -p "$HERE/build"
"$SWIFTC" -target wasm32-unknown-wasi -sdk "$SYSROOT" -static-stdlib -parse-as-library -Osize -wmo -module-name CatBehaviorWasm \
  "$HERE"/../CatBehavior/Sources/CatBehavior/*.swift "$HERE/wasm/Exports.swift" \
  -Xclang-linker -mexec-model=reactor \
  -o "$HERE/build/catbehavior.wasm"
ls -l "$HERE/build/catbehavior.wasm"
