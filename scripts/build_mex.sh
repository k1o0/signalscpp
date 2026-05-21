#!/usr/bin/env bash
set -euo pipefail

CONFIG="Release"
TARGET="signalsproxy"
RECONFIGURE=0
SKIP_INSTALL=0
BUILD_DIR="build_mex"
MATLAB_ROOT="/Applications/MATLAB_R2025a.app"

usage() {
  cat <<'EOF'
Build and install the Signals MEX layer on macOS/Linux.

Usage:
  ./scripts/build_mex.sh [options]

Options:
  --config <Release|Debug|RelWithDebInfo>  Build type (default: Release)
  --target <name>                          CMake target (default: signalsproxy)
  --matlab-root <path>                     MATLAB root path
  --build-dir <path>                       Build directory (default: build_mex)
  --reconfigure                            Force CMake reconfigure
  --skip-install                           Skip `cmake --install`
  -h, --help                               Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      CONFIG="$2"
      shift 2
      ;;
    --target)
      TARGET="$2"
      shift 2
      ;;
    --matlab-root)
      MATLAB_ROOT="$2"
      shift 2
      ;;
    --build-dir)
      BUILD_DIR="$2"
      shift 2
      ;;
    --reconfigure)
      RECONFIGURE=1
      shift
      ;;
    --skip-install)
      SKIP_INSTALL=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ABS_BUILD_DIR="${REPO_ROOT}/${BUILD_DIR}"
INSTALL_PREFIX="${REPO_ROOT}/matlab"
CACHE_FILE="${ABS_BUILD_DIR}/CMakeCache.txt"

if [[ ! -d "${MATLAB_ROOT}" ]]; then
  cat >&2 <<EOF
MATLAB not found at:
  ${MATLAB_ROOT}

Pass --matlab-root with your MATLAB app path (for example /Applications/MATLAB_R2026a.app).
EOF
  exit 1
fi

if [[ ${RECONFIGURE} -eq 1 || ! -f "${CACHE_FILE}" ]]; then
  echo "[configure]"
  cmake \
    -S "${REPO_ROOT}" \
    -B "${ABS_BUILD_DIR}" \
    -DSIGNALSCPP_BUILD_MEX=ON \
    -DMatlab_ROOT_DIR="${MATLAB_ROOT}" \
    -DCMAKE_BUILD_TYPE="${CONFIG}" \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}"
fi

echo "[build] config=${CONFIG} target=${TARGET}"
if [[ "${TARGET}" == "ALL_BUILD" ]]; then
  cmake --build "${ABS_BUILD_DIR}" --config "${CONFIG}"
else
  cmake --build "${ABS_BUILD_DIR}" --config "${CONFIG}" --target "${TARGET}"
fi

if [[ ${SKIP_INSTALL} -eq 1 ]]; then
  echo "[skip-install] Built artifacts are in ${ABS_BUILD_DIR}"
  exit 0
fi

# libmexclass_client_install() installs both the proxy library and gateway.
# Build gateway explicitly so install succeeds on a clean build tree.
if [[ "${TARGET}" != "ALL_BUILD" && "${TARGET}" != "gateway" ]]; then
  echo "[build] config=${CONFIG} target=gateway"
  cmake --build "${ABS_BUILD_DIR}" --config "${CONFIG}" --target gateway
fi

echo "[install] prefix=${INSTALL_PREFIX}"
cmake --install "${ABS_BUILD_DIR}" --config "${CONFIG}"

echo "[done] Run addSignalsPaths in MATLAB to reload binaries."
