#!/bin/bash
set -euo pipefail

# OpenSSL iOS/visionOS/Mac Catalyst build script
# Builds from upstream OpenSSL source checkout (out-of-tree builds)
# Produces libssl.xcframework and libcrypto.xcframework

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENSSL_SOURCE="${OPENSSL_SOURCE_DIR:-${SCRIPT_DIR}/../openssl}"
BUILD_DIR="${SCRIPT_DIR}/.build"
NCPU=$(sysctl -n hw.ncpu)

# Deployment targets
IOS_MIN_VERSION="18.0"
VISIONOS_MIN_VERSION="2.0"
CATALYST_MIN_VERSION="14.0"

# ── Validation ──────────────────────────────────────────────────────────────

if [ ! -f "${OPENSSL_SOURCE}/Configure" ]; then
    echo "ERROR: OpenSSL source not found at ${OPENSSL_SOURCE}"
    echo "Expected upstream checkout at ../openssl (relative to this script)"
    exit 1
fi

OPENSSL_VERSION=$(grep -m1 'OPENSSL_VERSION_STR' "${OPENSSL_SOURCE}/VERSION.dat" 2>/dev/null | cut -d= -f2 || echo "unknown")
echo "OpenSSL source: ${OPENSSL_SOURCE}"
echo "OpenSSL version: ${OPENSSL_VERSION}"
echo "Build directory: ${BUILD_DIR}"
echo "Parallel jobs: ${NCPU}"
echo ""

# ── Target definitions ──────────────────────────────────────────────────────
#
# Each target: dir_name | openssl_target | sdk | needs_cross_env
# "needs_cross_env" means we set CROSS_COMPILE/CROSS_TOP/CROSS_SDK
# (required for cross-compile targets, not for xcrun targets)

TARGETS=(
    "ios-arm64|ios64-xcrun|iphoneos|no"
    "ios-arm64-simulator|iossimulator-arm64-xcrun|iphonesimulator|no"
    "visionos-arm64|visionos64-cross-arm64|xros|yes"
    "visionos-arm64-simulator|visionos-sim-cross-arm64|xrsimulator|yes"
    "catalyst-arm64|maccatalyst-xcrun-arm64|macosx|no"
    "catalyst-x86_64|maccatalyst-xcrun-x86_64|macosx|no"
)

DEVELOPER=$(xcode-select -print-path)

# ── Helper functions ────────────────────────────────────────────────────────

sdk_path() {
    xcrun --sdk "$1" --show-sdk-path
}

sdk_version() {
    xcrun --sdk "$1" --show-sdk-version
}

platform_for_sdk() {
    case "$1" in
        iphoneos)       echo "iPhoneOS" ;;
        iphonesimulator) echo "iPhoneSimulator" ;;
        xros)           echo "XROS" ;;
        xrsimulator)    echo "XRSimulator" ;;
        macosx)         echo "MacOSX" ;;
    esac
}

# ── Clean previous build ───────────────────────────────────────────────────

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/targets"

# ── Build each target ──────────────────────────────────────────────────────

for entry in "${TARGETS[@]}"; do
    IFS='|' read -r dir_name openssl_target sdk needs_cross <<< "$entry"

    # Check SDK availability
    if ! xcrun --sdk "$sdk" --show-sdk-path &>/dev/null; then
        echo "SKIP: ${dir_name} (SDK '${sdk}' not available)"
        echo ""
        continue
    fi

    SDK_PATH=$(sdk_path "$sdk")
    SDK_VER=$(sdk_version "$sdk")
    PLATFORM=$(platform_for_sdk "$sdk")

    echo "── Building: ${dir_name} ──"
    echo "   Target: ${openssl_target}"
    echo "   SDK: ${sdk} ${SDK_VER}"

    TARGET_DIR="${BUILD_DIR}/targets/${dir_name}"
    mkdir -p "${TARGET_DIR}"

    # Set up environment
    export OPENSSL_LOCAL_CONFIG_DIR="${SCRIPT_DIR}/config"

    if [ "$needs_cross" = "yes" ]; then
        export CROSS_COMPILE="${DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/bin/"
        export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
        export CROSS_SDK="${PLATFORM}${SDK_VER}.sdk"
    else
        unset CROSS_COMPILE 2>/dev/null || true
        unset CROSS_TOP 2>/dev/null || true
        unset CROSS_SDK 2>/dev/null || true
    fi

    # Configure (out-of-tree build)
    cd "${TARGET_DIR}"
    echo "   Configuring..."
    "${OPENSSL_SOURCE}/Configure" "${openssl_target}" \
        --prefix="${TARGET_DIR}/install" \
        --openssldir="${TARGET_DIR}/install/ssl" \
        no-async no-shared no-tests \
        > "${TARGET_DIR}/configure.log" 2>&1

    # Build
    echo "   Building (${NCPU} jobs)..."
    make -j"${NCPU}" build_sw >> "${TARGET_DIR}/build.log" 2>&1

    # Install headers + libs
    echo "   Installing..."
    make install_dev >> "${TARGET_DIR}/install.log" 2>&1

    # Verify output
    if [ ! -f "${TARGET_DIR}/install/lib/libssl.a" ] || [ ! -f "${TARGET_DIR}/install/lib/libcrypto.a" ]; then
        echo "   ERROR: Build output missing!"
        exit 1
    fi

    SSL_SIZE=$(du -h "${TARGET_DIR}/install/lib/libssl.a" | cut -f1)
    CRYPTO_SIZE=$(du -h "${TARGET_DIR}/install/lib/libcrypto.a" | cut -f1)
    echo "   Done: libssl.a (${SSL_SIZE}), libcrypto.a (${CRYPTO_SIZE})"
    echo ""

    cd "${SCRIPT_DIR}"
done

# ── Create Catalyst universal binary ───────────────────────────────────────

echo "── Creating Catalyst universal binary ──"

CATALYST_UNI="${BUILD_DIR}/catalyst-universal"
mkdir -p "${CATALYST_UNI}/lib" "${CATALYST_UNI}/include"

CATALYST_ARM64="${BUILD_DIR}/targets/catalyst-arm64/install"
CATALYST_X86="${BUILD_DIR}/targets/catalyst-x86_64/install"

if [ ! -d "${CATALYST_ARM64}" ] || [ ! -d "${CATALYST_X86}" ]; then
    echo "ERROR: Both Catalyst architectures required for universal binary"
    exit 1
fi

# lipo static libraries
lipo -create \
    "${CATALYST_ARM64}/lib/libssl.a" \
    "${CATALYST_X86}/lib/libssl.a" \
    -output "${CATALYST_UNI}/lib/libssl.a"

lipo -create \
    "${CATALYST_ARM64}/lib/libcrypto.a" \
    "${CATALYST_X86}/lib/libcrypto.a" \
    -output "${CATALYST_UNI}/lib/libcrypto.a"

# Copy headers from arm64 (they're identical except opensslconf.h)
cp -R "${CATALYST_ARM64}/include/" "${CATALYST_UNI}/include/"

# Replace opensslconf.h with multi-arch shim
cp "${CATALYST_ARM64}/include/openssl/opensslconf.h" \
   "${CATALYST_UNI}/include/openssl/opensslconf_arm64.h"
cp "${CATALYST_X86}/include/openssl/opensslconf.h" \
   "${CATALYST_UNI}/include/openssl/opensslconf_x86_64.h"
cp "${SCRIPT_DIR}/config/opensslconf-catalyst.h" \
   "${CATALYST_UNI}/include/openssl/opensslconf.h"

echo "   Done"
echo ""

# ── Create XCFrameworks ────────────────────────────────────────────────────

echo "── Creating xcframeworks ──"

for lib in libssl libcrypto; do
    echo "   ${lib}.xcframework..."

    XCFW_ARGS=()

    # iOS device
    if [ -f "${BUILD_DIR}/targets/ios-arm64/install/lib/${lib}.a" ]; then
        XCFW_ARGS+=(-library "${BUILD_DIR}/targets/ios-arm64/install/lib/${lib}.a"
                    -headers "${BUILD_DIR}/targets/ios-arm64/install/include")
    fi

    # iOS simulator
    if [ -f "${BUILD_DIR}/targets/ios-arm64-simulator/install/lib/${lib}.a" ]; then
        XCFW_ARGS+=(-library "${BUILD_DIR}/targets/ios-arm64-simulator/install/lib/${lib}.a"
                    -headers "${BUILD_DIR}/targets/ios-arm64-simulator/install/include")
    fi

    # visionOS device
    if [ -f "${BUILD_DIR}/targets/visionos-arm64/install/lib/${lib}.a" ]; then
        XCFW_ARGS+=(-library "${BUILD_DIR}/targets/visionos-arm64/install/lib/${lib}.a"
                    -headers "${BUILD_DIR}/targets/visionos-arm64/install/include")
    fi

    # visionOS simulator
    if [ -f "${BUILD_DIR}/targets/visionos-arm64-simulator/install/lib/${lib}.a" ]; then
        XCFW_ARGS+=(-library "${BUILD_DIR}/targets/visionos-arm64-simulator/install/lib/${lib}.a"
                    -headers "${BUILD_DIR}/targets/visionos-arm64-simulator/install/include")
    fi

    # Mac Catalyst (universal)
    if [ -f "${CATALYST_UNI}/lib/${lib}.a" ]; then
        XCFW_ARGS+=(-library "${CATALYST_UNI}/lib/${lib}.a"
                    -headers "${CATALYST_UNI}/include")
    fi

    rm -rf "${BUILD_DIR}/${lib}.xcframework"
    xcodebuild -create-xcframework \
        "${XCFW_ARGS[@]}" \
        -output "${BUILD_DIR}/${lib}.xcframework"
done

echo ""
echo "── Build complete ──"
echo ""
echo "Output:"
echo "  ${BUILD_DIR}/libssl.xcframework"
echo "  ${BUILD_DIR}/libcrypto.xcframework"
echo ""

# Show slice summary
echo "Slices:"
for lib in libssl libcrypto; do
    echo "  ${lib}.xcframework:"
    ls -d "${BUILD_DIR}/${lib}.xcframework"/*/ 2>/dev/null | while read -r d; do
        echo "    $(basename "$d")"
    done
done
