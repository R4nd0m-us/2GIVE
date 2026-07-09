#!/bin/bash

# 2GiveCoin Fully Static Linux Build Script
# Builds ALL dependencies from source into depends/ for fully static, portable binaries.
#
# Dependencies built from source:
#   - OpenSSL 1.0.2u  (BN_init / BIGNUM compatibility)
#   - Boost 1.53.0   (legacy Boost.Asio API compatibility)
#   - Berkeley DB 5.3.28
#   - PCRE 8.45
#   - zlib 1.2.13
#   - expat 2.5.0    (fontconfig dependency)
#   - FreeType 2.13.2
#   - libpng 1.6.43
#   - libjpeg-turbo 2.1.5.1
#   - fontconfig 2.13.1
#   - Qt 4.7.4       (optional, for Qt GUI build)
#
# Minimal system packages required: build-essential, pkg-config, autoconf, cmake,
#   libx11-dev, libxext-dev, libxrender-dev, libfontconfig1-dev,
#   libgl1-mesa-dev, libglu1-mesa-dev, libxcb1-dev, libx11-xcb-dev, libxkbcommon-dev

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || { echo "ERROR: Cannot cd to $SCRIPT_DIR"; exit 1; }

echo "=== 2GiveCoin Fully Static Linux Build ==="
echo "    Target: Ubuntu 18.04.6 (x86_64)"
echo ""

# Error handling helper: reports the failing step and exits
fail() {
    echo "ERROR: $1"
    echo "Build failed at step: $2"
    exit 1
}

# Validate a tarball is actually a gzip archive, not HTML/corrupt
validate_tarball() {
    local file="$1"
    local name="$2"
    if [ ! -f "$file" ]; then
        fail "$name tarball not found: $file" "tarball check"
    fi
    if ! file "$file" | grep -q 'gzip\|Zip\|tar\|compress'; then
        echo "    [!] $name tarball appears corrupt (not a valid archive). Removing and re-downloading..."
        rm -f "$file"
        return 1
    fi
    return 0
}

# Download with retry and clear error reporting
download() {
    local url="$1"
    local out="$2"
    local tries=3
    local i=1
    while [ $i -le $tries ]; do
        echo "    Downloading (attempt $i/$tries): $url"
        if wget -q --timeout=30 --tries=1 -O "$out" "$url"; then
            if validate_tarball "$out" "$(basename "$out")"; then
                echo "    [+] Download successful"
                return 0
            fi
        fi
        i=$((i + 1))
        sleep 2
    done
    fail "Failed to download $url after $tries attempts" "download"
}

# Fix CRLF line endings in genbuild.sh if present
if [ -f share/genbuild.sh ] && grep -q $'\r' share/genbuild.sh; then
    echo "[*] Fixing line endings in share/genbuild.sh..."
    sed -i 's/\r$//' share/genbuild.sh || fail "sed failed on share/genbuild.sh" "CRLF fix"
fi

# Check for required tools
echo "[*] Checking build tools..."
missing_tools=""
for cmd in g++ make git wget pkg-config cmake gperf; do
    if ! command -v "$cmd" &> /dev/null; then
        missing_tools="$missing_tools $cmd"
    fi
done

if [ -n "$missing_tools" ]; then
    echo "[!] Missing tools:$missing_tools"
    echo "[*] Installing system dependencies..."
    sudo apt-get update -qq || fail "apt-get update failed" "system deps"
    sudo apt-get install -y -qq \
        build-essential pkg-config autoconf cmake gperf \
        libx11-dev libxext-dev libxrender-dev \
        libgl1-mesa-dev libglu1-mesa-dev \
        libxcb1-dev libx11-xcb-dev libxkbcommon-dev || fail "apt-get install failed" "system deps"
    echo "[+] System dependencies installed"
    
    # Re-check tools
    echo "[*] Re-checking build tools..."
    for cmd in g++ make git wget pkg-config cmake gperf; do
        if ! command -v "$cmd" &> /dev/null; then
            fail "$cmd still not found after installing build-essential" "tool check"
        fi
    done
    echo "[+] All build tools found"
else
    echo "[+] All build tools found"
fi

# Install minimal system dependencies
echo "[*] Ensuring system dependencies..."
sudo apt-get update -qq || fail "apt-get update failed" "system deps"
sudo apt-get install -y -qq \
    build-essential pkg-config autoconf cmake \
    libx11-dev libxext-dev libxrender-dev \
    libgl1-mesa-dev libglu1-mesa-dev \
    libxcb1-dev libx11-xcb-dev libxkbcommon-dev \
    uuid-dev || fail "apt-get install failed" "system deps"
echo "[+] System dependencies installed"

# Detect architecture
echo ""
echo "[*] Detecting architecture..."
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    HOST="x86_64-linux-gnu"
    HOST_TRIPLET="x86_64-unknown-linux-gnu"
else
    fail "Only x86_64 is supported. Detected: $ARCH" "arch detect"
fi
echo "[+] Architecture: $ARCH ($HOST)"

echo ""
echo "[*] Compiler: $(g++ --version | head -n1)"
echo "[*] Make: $(make --version | head -n1)"

# Base depends directory
DEPENDS="$SCRIPT_DIR/depends"

# ============================================================================
# OpenSSL 1.0.2u
# ============================================================================
OPENSSL_DIR="$DEPENDS/openssl"
if [ ! -f "$OPENSSL_DIR/lib/libssl.a" ]; then
    echo ""
    echo "[*] Building OpenSSL 1.0.2u (static)..."
    mkdir -p "$DEPENDS" || fail "Cannot mkdir $DEPENDS" "OpenSSL prep"
    cd "$DEPENDS" || fail "Cannot cd to $DEPENDS" "OpenSSL prep"
    
    if [ ! -f openssl-1.0.2u.tar.gz ]; then
        download "https://www.openssl.org/source/openssl-1.0.2u.tar.gz" "openssl-1.0.2u.tar.gz"
    fi
    
    echo "    Validating tarball..."
    validate_tarball openssl-1.0.2u.tar.gz "OpenSSL" || fail "OpenSSL tarball is corrupt" "OpenSSL validation"
    
    echo "    Extracting..."
    tar xzf openssl-1.0.2u.tar.gz || fail "tar failed for OpenSSL" "OpenSSL extract"
    cd openssl-1.0.2u || fail "Cannot cd to openssl-1.0.2u" "OpenSSL extract"
    
    echo "    Configuring..."
    CC=gcc CXX=g++ \
    ./config no-shared no-async no-dso no-hw no-threads \
        --prefix="$OPENSSL_DIR" \
        --openssldir="$OPENSSL_DIR/ssl" || fail "./config failed for OpenSSL" "OpenSSL configure"
    
    echo "    Compiling..."
    make -j$(nproc) || fail "make failed for OpenSSL" "OpenSSL compile"
    
    echo "    Installing..."
    make install_sw || fail "make install failed for OpenSSL" "OpenSSL install"
    
    cd "$DEPENDS" || fail "Cannot cd back to $DEPENDS" "OpenSSL cleanup"
    echo "[+] OpenSSL 1.0.2u built successfully"
else
    echo "[+] Using cached OpenSSL build"
fi
OPENSSL_INCLUDE="$OPENSSL_DIR/include"
OPENSSL_LIB="$OPENSSL_DIR/lib"

# ============================================================================
# Boost 1.53.0
# ============================================================================
BOOST_DIR="$DEPENDS/boost"
if [ ! -f "$BOOST_DIR/stage/lib/libboost_system.a" ]; then
    echo ""
    echo "[*] Building Boost 1.53.0 (static)..."
    mkdir -p "$DEPENDS" || fail "Cannot mkdir $DEPENDS" "Boost prep"
    cd "$DEPENDS" || fail "Cannot cd to $DEPENDS" "Boost prep"
    
    if [ ! -f boost_1_53_0.tar.gz ]; then
        download "https://sourceforge.net/projects/boost/files/boost/1.53.0/boost_1_53_0.tar.gz" "boost_1_53_0.tar.gz"
    fi
    
    echo "    Validating tarball..."
    validate_tarball boost_1_53_0.tar.gz "Boost" || fail "Boost tarball is corrupt" "Boost validation"
    
    echo "    Extracting..."
    tar xzf boost_1_53_0.tar.gz || fail "tar failed for Boost" "Boost extract"
    cd boost_1_53_0 || fail "Cannot cd to boost_1_53_0" "Boost extract"
    
    echo "    Bootstrapping..."
    ./bootstrap.sh || fail "./bootstrap.sh failed for Boost" "Boost bootstrap"
    
    echo "    Compiling..."
    ./b2 link=static runtime-link=static threading=multi address-model=64 \
        threadapi=pthread \
        cxxflags="-std=c++11 -pthread -fPIC" \
        linkflags="-pthread -std=c++11" \
        --with-system --with-filesystem --with-program_options \
        --with-thread --with-chrono --with-date_time --with-atomic \
        -j1 \
        --layout=system \
        stage 2>&1 | tee boost-build.log || fail "b2 build failed for Boost (see boost-build.log)" "Boost compile"
    
    mkdir -p "$BOOST_DIR" || fail "Cannot mkdir $BOOST_DIR" "Boost install"
    cp -r boost "$BOOST_DIR/" || fail "Cannot copy boost headers" "Boost install"
    cp -r stage "$BOOST_DIR/" || fail "Cannot copy boost stage libs" "Boost install"
    
    echo "    Verifying Boost libraries..."
    for lib in "$BOOST_DIR/stage/lib/libboost_system.a" \
              "$BOOST_DIR/stage/lib/libboost_filesystem.a" \
              "$BOOST_DIR/stage/lib/libboost_program_options.a" \
              "$BOOST_DIR/stage/lib/libboost_thread.a" \
              "$BOOST_DIR/stage/lib/libboost_chrono.a" \
              "$BOOST_DIR/stage/lib/libboost_date_time.a"; do
        if [ ! -f "$lib" ]; then
            fail "Boost library missing after build: $lib" "Boost verify"
        fi
    done
    echo "    [+] Core Boost libraries verified"
    
    cd "$DEPENDS" || fail "Cannot cd back to $DEPENDS" "Boost cleanup"
    echo "[+] Boost 1.53.0 built successfully"
else
    echo "[+] Using cached Boost build"
fi
BOOST_INCLUDE="$BOOST_DIR"
BOOST_LIB="$BOOST_DIR/stage/lib"

# ============================================================================
# Berkeley DB 5.3.28
# ============================================================================
BDB_DIR="$DEPENDS/db"
if [ ! -f "$BDB_DIR/lib/libdb_cxx.a" ]; then
    echo ""
    echo "[*] Building Berkeley DB 5.3.28 (static)..."
    mkdir -p "$DEPENDS" || fail "Cannot mkdir $DEPENDS" "BDB prep"
    cd "$DEPENDS" || fail "Cannot cd to $DEPENDS" "BDB prep"
    
    if [ ! -f db-5.3.28.tar.gz ] || ! validate_tarball db-5.3.28.tar.gz "Berkeley DB"; then
        echo "    Downloading Berkeley DB 5.3.28..."
        # Try multiple mirrors since Oracle requires auth now
        download "https://github.com/berkeleydb/libdb/releases/download/v5.3.28/db-5.3.28.tar.gz" "db-5.3.28.tar.gz" || \
        download "https://sourceforge.net/projects/boost-db/files/berkeley-db-5.3.28.tar.gz" "db-5.3.28.tar.gz" || \
        fail "Failed to download Berkeley DB from all mirrors. Manually download db-5.3.28.tar.gz and place in depends/ directory." "BDB download"
    fi
    
    echo "    Validating tarball..."
    validate_tarball db-5.3.28.tar.gz "Berkeley DB" || fail "Berkeley DB tarball is corrupt and re-download failed" "BDB validation"
    
    echo "    Extracting..."
    tar xzf db-5.3.28.tar.gz || fail "tar failed for Berkeley DB" "BDB extract"
    cd db-5.3.28/build_unix || fail "Cannot cd to db-5.3.28/build_unix" "BDB extract"
    
    echo "    Configuring..."
    CC=gcc CXX=g++ \
    ../dist/configure \
        --prefix="$BDB_DIR" \
        --enable-cxx \
        --disable-shared \
        --enable-static \
        --with-pic || fail "./configure failed for Berkeley DB" "BDB configure"
    
    echo "    Compiling..."
    make -j$(nproc) || fail "make failed for Berkeley DB" "BDB compile"
    
    echo "    Installing..."
    make install || fail "make install failed for Berkeley DB" "BDB install"
    
    cd "$DEPENDS" || fail "Cannot cd back to $DEPENDS" "BDB cleanup"
    echo "[+] Berkeley DB 5.3.28 built successfully"
else
    echo "[+] Using cached Berkeley DB build"
fi
BDB_INCLUDE="$BDB_DIR/include"
BDB_LIB="$BDB_DIR/lib"
BDB_LIB_SUFFIX=""

# ============================================================================
# PCRE 8.45
# ============================================================================
PCRE_DIR="$DEPENDS/pcre"
if [ ! -f "$PCRE_DIR/lib/libpcre.a" ]; then
    echo ""
    echo "[*] Building PCRE 8.45 (static)..."
    mkdir -p "$DEPENDS" || fail "Cannot mkdir $DEPENDS" "PCRE prep"
    cd "$DEPENDS" || fail "Cannot cd to $DEPENDS" "PCRE prep"
    
    if [ ! -f pcre-8.45.tar.gz ]; then
        download "https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.gz" "pcre-8.45.tar.gz"
    fi
    
    echo "    Validating tarball..."
    validate_tarball pcre-8.45.tar.gz "PCRE" || fail "PCRE tarball is corrupt" "PCRE validation"
    
    echo "    Extracting..."
    tar xzf pcre-8.45.tar.gz || fail "tar failed for PCRE" "PCRE extract"
    cd pcre-8.45 || fail "Cannot cd to pcre-8.45" "PCRE extract"
    
    echo "    Configuring..."
    CC=gcc CXX=g++ \
    ./configure \
        --prefix="$PCRE_DIR" \
        --disable-shared \
        --enable-static \
        --with-pic \
        --disable-cpp || fail "./configure failed for PCRE" "PCRE configure"
    
    echo "    Compiling..."
    make -j$(nproc) || fail "make failed for PCRE" "PCRE compile"
    
    echo "    Installing..."
    make install || fail "make install failed for PCRE" "PCRE install"
    
    cd "$DEPENDS" || fail "Cannot cd back to $DEPENDS" "PCRE cleanup"
    echo "[+] PCRE 8.45 built successfully"
else
    echo "[+] Using cached PCRE build"
fi
PCRE_INCLUDE="$PCRE_DIR/include"
PCRE_LIB="$PCRE_DIR/lib"

# ============================================================================
# zlib 1.2.13
# ============================================================================
ZLIB_DIR="$DEPENDS/zlib"
if [ ! -f "$ZLIB_DIR/lib/libz.a" ]; then
    echo ""
    echo "[*] Building zlib 1.2.13 (static)..."
    mkdir -p "$DEPENDS" || fail "Cannot mkdir $DEPENDS" "zlib prep"
    cd "$DEPENDS" || fail "Cannot cd to $DEPENDS" "zlib prep"
    
    if [ ! -f zlib-1.2.13.tar.gz ]; then
        download "https://github.com/madler/zlib/releases/download/v1.2.13/zlib-1.2.13.tar.gz" "zlib-1.2.13.tar.gz"
    fi
    
    echo "    Validating tarball..."
    validate_tarball zlib-1.2.13.tar.gz "zlib" || fail "zlib tarball is corrupt" "zlib validation"
    
    echo "    Extracting..."
    tar xzf zlib-1.2.13.tar.gz || fail "tar failed for zlib" "zlib extract"
    cd zlib-1.2.13 || fail "Cannot cd to zlib-1.2.13" "zlib extract"
    
    echo "    Configuring..."
    CC=gcc CXX=g++ \
    ./configure \
        --prefix="$ZLIB_DIR" \
        --static || fail "./configure failed for zlib" "zlib configure"
    
    echo "    Compiling..."
    make -j$(nproc) || fail "make failed for zlib" "zlib compile"
    
    echo "    Installing..."
    make install || fail "make install failed for zlib" "zlib install"
    
    cd "$DEPENDS" || fail "Cannot cd back to $DEPENDS" "zlib cleanup"
    echo "[+] zlib 1.2.13 built successfully"
else
    echo "[+] Using cached zlib build"
fi
ZLIB_INCLUDE="$ZLIB_DIR/include"
ZLIB_LIB="$ZLIB_DIR/lib"

# ============================================================================
# expat 2.5.0 (fontconfig dependency)
# ============================================================================
EXPAT_DIR="$DEPENDS/expat"
if [ ! -f "$EXPAT_DIR/lib/libexpat.a" ]; then
    echo ""
    echo "[*] Building expat 2.5.0 (static)..."
    mkdir -p "$DEPENDS" || fail "Cannot mkdir $DEPENDS" "expat prep"
    cd "$DEPENDS" || fail "Cannot cd to $DEPENDS" "expat prep"
    
    if [ ! -f expat-2.5.0.tar.gz ]; then
        download "https://github.com/libexpat/libexpat/releases/download/R_2_5_0/expat-2.5.0.tar.gz" "expat-2.5.0.tar.gz"
    fi
    
    echo "    Validating tarball..."
    validate_tarball expat-2.5.0.tar.gz "expat" || fail "expat tarball is corrupt" "expat validation"
    
    echo "    Extracting..."
    tar xzf expat-2.5.0.tar.gz || fail "tar failed for expat" "expat extract"
    cd expat-2.5.0 || fail "Cannot cd to expat-2.5.0" "expat extract"
    
    echo "    Configuring..."
    CC=gcc CXX=g++ \
    ./configure \
        --prefix="$EXPAT_DIR" \
        --disable-shared \
        --enable-static \
        --with-pic || fail "./configure failed for expat" "expat configure"
    
    echo "    Compiling..."
    make -j$(nproc) || fail "make failed for expat" "expat compile"
    
    echo "    Installing..."
    make install || fail "make install failed for expat" "expat install"
    
    cd "$DEPENDS" || fail "Cannot cd back to $DEPENDS" "expat cleanup"
    echo "[+] expat 2.5.0 built successfully"
else
    echo "[+] Using cached expat build"
fi
EXPAT_INCLUDE="$EXPAT_DIR/include"
EXPAT_LIB="$EXPAT_DIR/lib"

# ============================================================================
# FreeType 2.13.2
# ============================================================================
FREETYPE_DIR="$DEPENDS/freetype"
if [ ! -f "$FREETYPE_DIR/lib/libfreetype.a" ]; then
    echo ""
    echo "[*] Building FreeType 2.13.2 (static)..."
    mkdir -p "$DEPENDS" || fail "Cannot mkdir $DEPENDS" "FreeType prep"
    cd "$DEPENDS" || fail "Cannot cd to $DEPENDS" "FreeType prep"
    
    if [ ! -f freetype-2.13.2.tar.gz ]; then
        download "https://downloads.sourceforge.net/freetype/freetype-2.13.2.tar.gz" "freetype-2.13.2.tar.gz"
    fi
    
    echo "    Validating tarball..."
    validate_tarball freetype-2.13.2.tar.gz "FreeType" || fail "FreeType tarball is corrupt" "FreeType validation"
    
    echo "    Extracting..."
    tar xzf freetype-2.13.2.tar.gz || fail "tar failed for FreeType" "FreeType extract"
    cd freetype-2.13.2 || fail "Cannot cd to freetype-2.13.2" "FreeType extract"
    
    echo "    Configuring..."
    CC=gcc CXX=g++ \
    CPPFLAGS="-I$ZLIB_INCLUDE" LDFLAGS="-L$ZLIB_LIB" \
    ./configure \
        --prefix="$FREETYPE_DIR" \
        --disable-shared \
        --enable-static \
        --with-pic \
        --without-harfbuzz \
        --with-zlib="$ZLIB_DIR" || fail "./configure failed for FreeType" "FreeType configure"
    
    echo "    Compiling..."
    make -j$(nproc) || fail "make failed for FreeType" "FreeType compile"
    
    echo "    Installing..."
    make install || fail "make install failed for FreeType" "FreeType install"
    
    cd "$DEPENDS" || fail "Cannot cd back to $DEPENDS" "FreeType cleanup"
    echo "[+] FreeType 2.13.2 built successfully"
else
    echo "[+] Using cached FreeType build"
fi
FREETYPE_INCLUDE="$FREETYPE_DIR/include"
FREETYPE_LIB="$FREETYPE_DIR/lib"

# ============================================================================
# libpng 1.6.43
# ============================================================================
PNG_DIR="$DEPENDS/libpng"
if [ ! -f "$PNG_DIR/lib/libpng.a" ]; then
    echo ""
    echo "[*] Building libpng 1.6.43 (static)..."
    mkdir -p "$DEPENDS" || fail "Cannot mkdir $DEPENDS" "libpng prep"
    cd "$DEPENDS" || fail "Cannot cd to $DEPENDS" "libpng prep"
    
    if [ ! -f libpng-1.6.43.tar.gz ]; then
        download "https://downloads.sourceforge.net/libpng/libpng-1.6.43.tar.gz" "libpng-1.6.43.tar.gz"
    fi
    
    echo "    Validating tarball..."
    validate_tarball libpng-1.6.43.tar.gz "libpng" || fail "libpng tarball is corrupt" "libpng validation"
    
    echo "    Extracting..."
    tar xzf libpng-1.6.43.tar.gz || fail "tar failed for libpng" "libpng extract"
    cd libpng-1.6.43 || fail "Cannot cd to libpng-1.6.43" "libpng extract"
    
    echo "    Configuring..."
    CC=gcc CXX=g++ \
    CPPFLAGS="-I$ZLIB_INCLUDE" LDFLAGS="-L$ZLIB_LIB" \
    ./configure \
        --prefix="$PNG_DIR" \
        --disable-shared \
        --enable-static \
        --with-pic \
        --with-zlib="$ZLIB_DIR" || fail "./configure failed for libpng" "libpng configure"
    
    echo "    Compiling..."
    make -j$(nproc) || fail "make failed for libpng" "libpng compile"
    
    echo "    Installing..."
    make install || fail "make install failed for libpng" "libpng install"
    
    cd "$DEPENDS" || fail "Cannot cd back to $DEPENDS" "libpng cleanup"
    echo "[+] libpng 1.6.43 built successfully"
else
    echo "[+] Using cached libpng build"
fi
PNG_INCLUDE="$PNG_DIR/include"
PNG_LIB="$PNG_DIR/lib"

# ============================================================================
# libjpeg-turbo 2.1.5.1
# ============================================================================
JPEG_DIR="$DEPENDS/libjpeg-turbo"
if [ ! -f "$JPEG_DIR/lib/libjpeg.a" ]; then
    echo ""
    echo "[*] Building libjpeg-turbo 2.1.5.1 (static)..."
    mkdir -p "$DEPENDS" || fail "Cannot mkdir $DEPENDS" "libjpeg prep"
    cd "$DEPENDS" || fail "Cannot cd to $DEPENDS" "libjpeg prep"
    
    if [ ! -f libjpeg-turbo-2.1.5.1.tar.gz ]; then
        download "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/2.1.5.1/libjpeg-turbo-2.1.5.1.tar.gz" "libjpeg-turbo-2.1.5.1.tar.gz"
    fi
    
    echo "    Validating tarball..."
    validate_tarball libjpeg-turbo-2.1.5.1.tar.gz "libjpeg-turbo" || fail "libjpeg-turbo tarball is corrupt" "libjpeg validation"
    
    echo "    Extracting..."
    tar xzf libjpeg-turbo-2.1.5.1.tar.gz || fail "tar failed for libjpeg-turbo" "libjpeg extract"
    cd libjpeg-turbo-2.1.5.1 || fail "Cannot cd to libjpeg-turbo-2.1.5.1" "libjpeg extract"
    
    echo "    Configuring..."
    mkdir -p build && cd build && \
    cmake .. \
        -DCMAKE_INSTALL_PREFIX="$JPEG_DIR" \
        -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_SHARED=OFF \
        -DENABLE_STATIC=ON || fail "cmake configure failed for libjpeg-turbo" "libjpeg configure"
    
    echo "    Compiling..."
    cmake --build . -- -j$(nproc) || fail "cmake build failed for libjpeg-turbo" "libjpeg compile"
    
    echo "    Installing..."
    cmake --install . || fail "cmake install failed for libjpeg-turbo" "libjpeg install"
    
    # Ensure library is in the expected location
    JPEG_SRC_DIR="$DEPENDS/libjpeg-turbo-2.1.5.1"
    JPEG_BUILD_DIR="$JPEG_SRC_DIR/build"
    if [ ! -f "$JPEG_DIR/lib/libjpeg.a" ]; then
        echo "    [i] cmake install may not have placed libjpeg.a in expected location"
        echo "    [i] Checking in: $JPEG_BUILD_DIR/"
        if [ -f "$JPEG_BUILD_DIR/libjpeg.a" ]; then
            echo "    [i] Found libjpeg.a, copying to $JPEG_DIR/lib/"
            mkdir -p "$JPEG_DIR/lib"
            cp -f "$JPEG_BUILD_DIR/libjpeg.a" "$JPEG_DIR/lib/"
        elif [ -f "$JPEG_BUILD_DIR/lib/libjpeg.a" ]; then
            echo "    [i] Found libjpeg.a in build/lib/, copying to $JPEG_DIR/lib/"
            mkdir -p "$JPEG_DIR/lib"
            cp -f "$JPEG_BUILD_DIR/lib/libjpeg.a" "$JPEG_DIR/lib/"
        elif [ -f "$JPEG_BUILD_DIR/libjpeg-static.a" ]; then
            echo "    [i] Found libjpeg-static.a, copying to $JPEG_DIR/lib/libjpeg.a"
            mkdir -p "$JPEG_DIR/lib"
            cp -f "$JPEG_BUILD_DIR/libjpeg-static.a" "$JPEG_DIR/lib/libjpeg.a"
        else
            echo "    [i] Contents of $JPEG_BUILD_DIR/:"
            ls -la "$JPEG_BUILD_DIR/" 2>/dev/null || echo "    [i] Directory does not exist"
            fail "libjpeg.a not found after cmake install" "libjpeg install"
        fi
    fi
    fi
    
    cd "$DEPENDS" || fail "Cannot cd back to $DEPENDS" "libjpeg cleanup"
    echo "[+] libjpeg-turbo 2.1.5.1 built successfully"
else
    echo "[+] Using cached libjpeg-turbo build"
fi
JPEG_INCLUDE="$JPEG_DIR/include"
JPEG_LIB="$JPEG_DIR/lib"

# ============================================================================
# fontconfig 2.13.1
# ============================================================================
FONTCONFIG_DIR="$DEPENDS/fontconfig"
if [ ! -f "$FONTCONFIG_DIR/lib/libfontconfig.a" ]; then
    echo ""
    echo "[*] Building fontconfig 2.13.1 (static)..."
    mkdir -p "$DEPENDS" || fail "Cannot mkdir $DEPENDS" "fontconfig prep"
    cd "$DEPENDS" || fail "Cannot cd to $DEPENDS" "fontconfig prep"
    
    if [ ! -f fontconfig-2.13.1.tar.gz ]; then
        download "https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.13.1.tar.gz" "fontconfig-2.13.1.tar.gz" || \
        download "https://gitlab.freedesktop.org/fontconfig/fontconfig/-/archive/2.13.1/fontconfig-2.13.1.tar.gz" "fontconfig-2.13.1.tar.gz" || \
        fail "Failed to download fontconfig from all mirrors" "fontconfig download"
    fi
    
    echo "    Validating tarball..."
    validate_tarball fontconfig-2.13.1.tar.gz "fontconfig" || fail "fontconfig tarball is corrupt" "fontconfig validation"
    
    echo "    Extracting..."
    tar xzf fontconfig-2.13.1.tar.gz || fail "tar failed for fontconfig" "fontconfig extract"
    cd fontconfig-2.13.1 || fail "Cannot cd to fontconfig-2.13.1" "fontconfig extract"
    
    echo "    Preparing build system..."
    if [ ! -f configure ]; then
        echo "    No configure script found, running autoreconf..."
        autoreconf -fi || fail "autoreconf failed for fontconfig" "fontconfig autotools"
    fi
    
    echo "    Configuring..."
    export CC=gcc CXX=g++
    export PATH="$FREETYPE_DIR/bin:$PATH"
    export PKG_CONFIG_PATH="$FREETYPE_DIR/lib/pkgconfig:$EXPAT_LIB/pkgconfig"
    export CPPFLAGS="-I$ZLIB_INCLUDE -I$FREETYPE_INCLUDE -I$FREETYPE_INCLUDE/freetype2 -I$EXPAT_INCLUDE"
    export LDFLAGS="-L$ZLIB_LIB -L$FREETYPE_LIB -L$EXPAT_LIB"
    ./configure \
        --prefix="$FONTCONFIG_DIR" \
        --disable-shared \
        --enable-static \
        --with-expat="$EXPAT_DIR" \
        --with-freetype-prefix="$FREETYPE_DIR" \
        --with-freetype-config="$FREETYPE_DIR/bin/freetype-config" \
        FREETYPE_CFLAGS="-I$FREETYPE_INCLUDE -I$FREETYPE_INCLUDE/freetype2" \
        FREETYPE_LIBS="-L$FREETYPE_LIB -lfreetype" \
        --disable-docs || fail "./configure failed for fontconfig" "fontconfig configure"
    
    echo "    Compiling..."
    make -j$(nproc) -C src || fail "make failed for fontconfig library" "fontconfig compile"
    
    echo "    Installing..."
    make install -C src || fail "make install failed for fontconfig" "fontconfig install"
    
    cd "$DEPENDS" || fail "Cannot cd back to $DEPENDS" "fontconfig cleanup"
    echo "[+] fontconfig 2.13.1 built successfully"
else
    echo "[+] Using cached fontconfig build"
fi
FONTCONFIG_INCLUDE="$FONTCONFIG_DIR/include"
FONTCONFIG_LIB="$FONTCONFIG_DIR/lib"

# ============================================================================
# Verify all dependencies are present
# ============================================================================
echo ""
echo "[*] Verifying all dependencies were built..."
missing=0

check_lib() {
    local path="$1"
    local name="$2"
    if [ ! -f "$path" ]; then
        echo "    MISSING: $path"
        missing=$((missing + 1))
    else
        echo "    [+] $name: $path"
    fi
}

check_lib "$OPENSSL_DIR/lib/libssl.a" "OpenSSL"
check_lib "$BOOST_DIR/stage/lib/libboost_system.a" "Boost system"
check_lib "$BOOST_DIR/stage/lib/libboost_filesystem.a" "Boost filesystem"
check_lib "$BOOST_DIR/stage/lib/libboost_program_options.a" "Boost program_options"
check_lib "$BOOST_DIR/stage/lib/libboost_thread.a" "Boost thread"
check_lib "$BOOST_DIR/stage/lib/libboost_chrono.a" "Boost chrono"
check_lib "$BOOST_DIR/stage/lib/libboost_date_time.a" "Boost date_time"
check_lib "$BDB_DIR/lib/libdb_cxx.a" "Berkeley DB"
check_lib "$PCRE_DIR/lib/libpcre.a" "PCRE"
check_lib "$ZLIB_DIR/lib/libz.a" "zlib"
check_lib "$EXPAT_DIR/lib/libexpat.a" "expat"
check_lib "$FREETYPE_DIR/lib/libfreetype.a" "FreeType"
check_lib "$PNG_DIR/lib/libpng.a" "libpng"

# libjpeg-turbo may install as libjpeg.a or libjpeg-static.a
if [ ! -f "$JPEG_DIR/lib/libjpeg.a" ] && [ ! -f "$JPEG_DIR/lib/libjpeg-static.a" ]; then
    echo "    MISSING: $JPEG_DIR/lib/libjpeg.a (or libjpeg-static.a)"
    missing=$((missing + 1))
else
    if [ ! -f "$JPEG_DIR/lib/libjpeg.a" ] && [ -f "$JPEG_DIR/lib/libjpeg-static.a" ]; then
        echo "    [i] libjpeg-static.a found, creating symlink as libjpeg.a"
        ln -sf libjpeg-static.a "$JPEG_DIR/lib/libjpeg.a"
    fi
    echo "    [+] libjpeg: $JPEG_DIR/lib/libjpeg.a"
fi

check_lib "$FONTCONFIG_DIR/lib/libfontconfig.a" "fontconfig"

if [ $missing -gt 0 ]; then
    fail "$missing dependencies are missing after build" "verification"
fi
echo "[+] All dependencies verified (0 missing)"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "=== Dependencies Ready ==="
echo "  OpenSSL:     $OPENSSL_DIR"
echo "  Boost:       $BOOST_DIR"
echo "  Berkeley DB: $BDB_DIR"
echo "  PCRE:        $PCRE_DIR"
echo "  zlib:        $ZLIB_DIR"
echo "  expat:       $EXPAT_DIR"
echo "  FreeType:    $FREETYPE_DIR"
echo "  libpng:      $PNG_DIR"
echo "  libjpeg:     $JPEG_DIR"
echo "  fontconfig:  $FONTCONFIG_DIR"
echo ""
echo "All dependencies are built in: $DEPENDS/"
echo ""
echo "These paths are used by the build:"
echo "  BOOST_INCLUDE_PATH=$BOOST_INCLUDE"
echo "  BOOST_LIB_PATH=$BOOST_LIB"
echo "  BDB_INCLUDE_PATH=$BDB_INCLUDE"
echo "  BDB_LIB_PATH=$BDB_LIB"
echo "  OPENSSL_INCLUDE_PATH=$OPENSSL_INCLUDE"
echo "  OPENSSL_LIB_PATH=$OPENSSL_LIB"
echo "  PCRE_INCLUDE_PATH=$PCRE_INCLUDE"
echo "  PCRE_LIB_PATH=$PCRE_LIB"
echo "  ZLIB_INCLUDE_PATH=$ZLIB_INCLUDE"
echo "  ZLIB_LIB_PATH=$ZLIB_LIB"
echo ""

# ============================================================================
# Qt 4.7.4 (optional, for Qt GUI build)
# ============================================================================
BUILD_QT="${BUILD_QT:-0}"
if [ "$BUILD_QT" = "1" ]; then
    QT_DIR="$DEPENDS/qt"
    if [ ! -f "$QT_DIR/lib/libQtCore.a" ]; then
        echo ""
        echo "[*] Building Qt 4.7.4 (static)..."
        mkdir -p "$DEPENDS" || fail "Cannot mkdir $DEPENDS" "Qt prep"
        cd "$DEPENDS" || fail "Cannot cd to $DEPENDS" "Qt prep"
        
        if [ ! -f qt-everywhere-opensource-src-4.7.4.tar.gz ]; then
            download "https://download.qt.io/archive/qt/4.7/qt-everywhere-opensource-src-4.7.4.tar.gz" "qt-everywhere-opensource-src-4.7.4.tar.gz"
        fi
        
        echo "    Validating tarball..."
        validate_tarball qt-everywhere-opensource-src-4.7.4.tar.gz "Qt" || fail "Qt tarball is corrupt" "Qt validation"
        
        echo "    Extracting..."
        tar xzf qt-everywhere-opensource-src-4.7.4.tar.gz || fail "tar failed for Qt" "Qt extract"
        mv qt-everywhere-opensource-src-4.7.4 qt-4.7.4 || fail "Cannot rename Qt dir" "Qt extract"
        cd qt-4.7.4 || fail "Cannot cd to qt-4.7.4" "Qt extract"
        
        echo "    Configuring..."
        chmod +x configure || fail "Cannot chmod configure" "Qt configure"
        ./configure \
            -prefix "$QT_DIR" \
            -static \
            -release \
            -no-shared \
            -opensource \
            -confirm-license \
            -no-phonon \
            -no-qt3support \
            -no-scripttools \
            -no-multimedia \
            -no-declarative \
            -no-webkit \
            -no-sql-sqlite \
            -no-sql-mysql \
            -no-sql-psql \
            -no-sql-oci \
            -no-sql-tds \
            -no-sql-db2 \
            -no-sql-ibase \
            -no-sql-sqlite2 \
            -no-sql-odbc \
            -no-sql-nacl \
            -no-xinput \
            -no-xrandr \
            -no-xinerama \
            -no-xfixes \
            -no-xkb \
            -no-sm \
            -no-openvg \
            -no-egl \
            -no-glib \
            -no-pulseaudio \
            -no-alsa \
            -no-cups \
            -no-dbus \
            -no-gif \
            -no-libtiff \
            -no-mng \
            -no-opengl \
            -I"$ZLIB_INCLUDE" \
            -I"$PNG_INCLUDE" \
            -I"$JPEG_INCLUDE" \
            -I"$FREETYPE_INCLUDE" \
            -I"$FONTCONFIG_INCLUDE" \
            -L"$ZLIB_LIB" \
            -L"$PNG_LIB" \
            -L"$JPEG_LIB" \
            -L"$FREETYPE_LIB" \
            -L"$FONTCONFIG_LIB" \
            -lz \
            -lpng16 \
            -ljpeg \
            -lfreetype \
            -lfontconfig \
            -nomake examples \
            -nomake demos || fail "./configure failed for Qt" "Qt configure"
        
        echo "    Compiling (this will take a while)..."
        make -j$(nproc) || fail "make failed for Qt" "Qt compile"
        
        echo "    Installing..."
        make install || fail "make install failed for Qt" "Qt install"
        
        cd "$DEPENDS" || fail "Cannot cd back to $DEPENDS" "Qt cleanup"
        echo "[+] Qt 4.7.4 built successfully"
    else
        echo "[+] Using cached Qt build"
    fi
    QT_INCLUDE="$QT_DIR/include"
    QT_LIB="$QT_DIR/lib"
    echo "[+] Qt 4.7.4 ready at $QT_DIR"
    echo "    Qt include path: $QT_INCLUDE"
    echo "    Qt lib path: $QT_LIB"
else
    echo ""
    echo "[i] Qt build skipped (set BUILD_QT=1 to enable)"
fi

# ============================================================================
# Build 2GiveCoind and 2GiveCoin-cli
# ============================================================================
echo ""
echo "[*] Building 2GiveCoind and 2GiveCoin-cli (fully static)..."
cd src || fail "Cannot cd to src" "project build"

# Clean previous build
make -f makefile.unix clean || fail "make clean failed" "project build"

# Build with static linking against all depends/ libraries
make -f makefile.unix \
    STATIC=all \
    USE_SSE2=1 \
    BOOST_INCLUDE_PATH="$BOOST_INCLUDE" \
    BOOST_LIB_PATH="$BOOST_LIB" \
    BDB_INCLUDE_PATH="$BDB_INCLUDE" \
    BDB_LIB_PATH="$BDB_LIB" \
    OPENSSL_INCLUDE_PATH="$OPENSSL_INCLUDE" \
    OPENSSL_LIB_PATH="$OPENSSL_LIB" \
    PCRE_INCLUDE_PATH="$PCRE_INCLUDE" \
    PCRE_LIB_PATH="$PCRE_LIB" \
    ZLIB_INCLUDE_PATH="$ZLIB_INCLUDE" \
    ZLIB_LIB_PATH="$ZLIB_LIB" \
    BOOST_LIB_SUFFIX="" \
    BDB_LIB_SUFFIX="$BDB_LIB_SUFFIX" \
    DEBUGFLAGS="-g" \
    CXXFLAGS="-std=gnu++11" \
    all || fail "make failed for 2GiveCoin" "project build"

cd ..

echo ""
echo "=== Build Complete ==="
echo "Binaries:"
if [ -f src/2GiveCoind ]; then
    echo "  - src/2GiveCoind (daemon)"
    echo "    Size: $(du -h src/2GiveCoind | cut -f1)"
    echo "    Type: $(file src/2GiveCoind)"
fi
if [ -f src/2GiveCoin-cli ]; then
    echo "  - src/2GiveCoin-cli (CLI)"
    echo "    Size: $(du -h src/2GiveCoin-cli | cut -f1)"
    echo "    Type: $(file src/2GiveCoin-cli)"
fi
echo ""
echo "Static linkage check:"
if [ -f src/2GiveCoind ]; then
    ldd src/2GiveCoind 2>/dev/null || echo "  (fully static or ldd not available)"
fi
if [ -f src/2GiveCoin-cli ]; then
    ldd src/2GiveCoin-cli 2>/dev/null || echo "  (fully static or ldd not available)"
fi
echo ""
echo "To test:"
echo "  ./src/2GiveCoind -?        (show help)"
echo "  ./src/2GiveCoin-cli -?     (show help)"
