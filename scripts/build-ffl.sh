#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# Activate Emscripten 4.0.10 first (source /path/to/emsdk/emsdk_env.sh).
cmake_bin="${CMAKE_BIN:-cmake}"
build_dir="${FFL_BUILD_DIR:-$PWD/.build/FFLWasm}"
emcmake "$cmake_bin" -S ThirdParty/ffl-native -B "$build_dir" \
  -DFFL_WITH_RIO="$PWD/ThirdParty/rio" \
  -DFFL_WITH_NINTEXUTILS="$PWD/ThirdParty/ninTexUtils" \
  -DCMAKE_BUILD_TYPE=Release -DFFL_BUILD_EMSCRIPTEN_MODULE=ON \
  -DFFL_NO_NINTEXUTILS=OFF
"$cmake_bin" --build "$build_dir" -j 4
cp "$build_dir/ffl-emscripten.js" Sources/MacPlaza/Resources/FFL/vendor/
cp "$build_dir/ffl-emscripten.wasm" Sources/MacPlaza/Resources/FFL/vendor/
echo "FFL rebuilt with Wii U GX2 texture support."
