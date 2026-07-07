#!/bin/bash
set -e

# 2GiveCoin Fully Static Linux Build Script
# Builds ALL dependencies from source into depends/ for fully static, portable binaries.
#
# Dependencies built from source:
#   - OpenSSL 1.0.2u  (BN_init / BIGNUM compatibility)
#   - Boost 1.53.0   (legacy Boost.Asio API compatibility)
#   - Berkeley DB 5.3.28
#   - PCRE 8.45
#   - zlib 1.2.13
#   - Qt 4.7.4       (optional, for Qt GUI build)
#
# System packages required: build-essential, pkg-config, autoconf, libx11-dev,
#   libxext-dev, libxrender-dev, libfontconfig1-dev, libfreetype6-dev,
#   libjpeg-dev, libpng-dev, libssl-dev, zlib1g-dev, libgl1-mesa-dev,
#   libglu1-mesa-dev, libxcb1-dev, libx11-xcb-dev, libxkbcommon-dev

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== 2GiveCoin Fully Static Linux Build ==="
echo "    Target: Debian 13 (x86_64)"
echo ""

# Fix CRLF line endings in genbuild.sh if present
if [ -f share/genbuild.sh ] && grep -q $'\r' share/genbuild.sh; then
    echo "[*] Fixing line endings in share/genbuild.sh..."
    sed -i 's/\r$//' share/genbuild.sh
fi

# Check for required tools
echo "[*] Checking build tools..."
for cmd in g++ make git wget pkg-config; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: $cmd not found. Install build-essential, git, wget, pkg-config."
        exit 1
    fi
done

# Install system dependencies
echo "[*] Ensuring system dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    build-essential pkg-config autoconf \
    libx11-dev libxext-dev libxrender-dev libfontconfig1-dev \
    libfreetype6-dev libjpeg-dev libpng-dev \
    libgl1-mesa-dev libglu1-mesa-dev \
    libxcb1-dev libx11-xcb-dev libxkbcommon-dev

# Detect architecture
echo ""
echo "[*] Detecting architecture..."
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    HOST="x86_64-linux-gnu"
    HOST_TRIPLET="x86_64-unknown-linux-gnu"
else
    echo "ERROR: Only x86_64 is supported."
    exit 1
fi
echo "[+] Architecture: $ARCH ($HOST)"

# Base depends directory
DEPENDS="$SCRIPT_DIR/depends"

# ============================================================================
# OpenSSL 1.0.2u
# ============================================================================
OPENSSL_DIR="$DEPENDS/openssl"
if [ ! -f "$OPENSSL_DIR/lib/libssl.a" ]; then
    echo ""
    echo "[*] Building OpenSSL 1.0.2u (static)..."
    mkdir -p "$DEPENDS"
    cd "$DEPENDS"
    
    if [ ! -f openssl-1.0.2u.tar.gz ]; then
        echo "    Downloading..."
        wget -q https://www.openssl.org/source/openssl-1.0.2u.tar.gz
    fi
    
    echo "    Extracting..."
    tar xzf openssl-1.0.2u.tar.gz
    cd openssl-1.0.2u
    
    echo "    Configuring..."
    ./config no-shared no-async no-dso no-hw no-threads \
        --prefix="$OPENSSL_DIR" \
        --openssldir="$OPENSSL_DIR/ssl"
    
    echo "    Compiling..."
    make -j$(nproc)
    
    echo "    Installing..."
    make install_sw
    
    cd "$DEPENDS"
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
    mkdir -p "$DEPENDS"
    cd "$DEPENDS"
    
    if [ ! -f boost_1_53_0.tar.gz ]; then
        echo "    Downloading..."
        wget -q https://sourceforge.net/projects/boost/files/boost/1.53.0/boost_1_53_0.tar.gz
    fi
    
    echo "    Extracting..."
    tar xzf boost_1_53_0.tar.gz
    cd boost_1_53_0
    
    echo "    Bootstrapping..."
    ./bootstrap.sh
    
    echo "    Compiling..."
    ./b2 link=static runtime-link=static threading=multi address-model=64 \
        --with-system --with-filesystem --with-program_options \
        --with-thread --with-chrono --with-date_time --with-atomic \
        stage
    
    mkdir -p "$BOOST_DIR"
    cp -r boost "$BOOST_DIR/"
    cp -r stage "$BOOST_DIR/"
    
    cd "$DEPENDS"
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
    mkdir -p "$DEPENDS"
    cd "$DEPENDS"
    
    if [ ! -f db-5.3.28.tar.gz ]; then
        echo "    Downloading..."
        wget -q https://download.oracle.com/berkeley-db/db-5.3.28.tar.gz
    fi
    
    echo "    Extracting..."
    tar xzf db-5.3.28.tar.gz
    cd db-5.3.28/build_unix
    
    echo "    Configuring..."
    ../dist/configure \
        --prefix="$BDB_DIR" \
        --enable-cxx \
        --disable-shared \
        --enable-static \
        --with-pic
    
    echo "    Compiling..."
    make -j$(nproc)
    
    echo "    Installing..."
    make install
    
    cd "$DEPENDS"
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
    mkdir -p "$DEPENDS"
    cd "$DEPENDS"
    
    if [ ! -f pcre-8.45.tar.gz ]; then
        echo "    Downloading..."
        wget -q https://sourceforge.net/projects/pcre/files/pcre/8.45/pcre-8.45.tar.gz
    fi
    
    echo "    Extracting..."
    tar xzf pcre-8.45.tar.gz
    cd pcre-8.45
    
    echo "    Configuring..."
    ./configure \
        --prefix="$PCRE_DIR" \
        --disable-shared \
        --enable-static \
        --with-pic \
        --disable-cpp
    
    echo "    Compiling..."
    make -j$(nproc)
    
    echo "    Installing..."
    make install
    
    cd "$DEPENDS"
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
    mkdir -p "$DEPENDS"
    cd "$DEPENDS"
    
    if [ ! -f zlib-1.2.13.tar.gz ]; then
        echo "    Downloading..."
        wget -q https://zlib.net/zlib-1.2.13.tar.gz
    fi
    
    echo "    Extracting..."
    tar xzf zlib-1.2.13.tar.gz
    cd zlib-1.2.13
    
    echo "    Configuring..."
    ./configure \
        --prefix="$ZLIB_DIR" \
        --static
    
    echo "    Compiling..."
    make -j$(nproc)
    
    echo "    Installing..."
    make install
    
    cd "$DEPENDS"
    echo "[+] zlib 1.2.13 built successfully"
else
    echo "[+] Using cached zlib build"
fi
ZLIB_INCLUDE="$ZLIB_DIR/include"
ZLIB_LIB="$ZLIB_DIR/lib"

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
        mkdir -p "$DEPENDS"
        cd "$DEPENDS"
        
        if [ ! -f qt-everywhere-opensource-src-4.7.4.tar.gz ]; then
            echo "    Downloading..."
            wget -q https://download.qt.io/archive/qt/4.7/qt-everywhere-opensource-src-4.7.4.tar.gz
        fi
        
        echo "    Extracting..."
        tar xzf qt-everywhere-opensource-src-4.7.4.tar.gz
        mv qt-everywhere-opensource-src-4.7.4 qt-4.7.4
        cd qt-4.7.4
        
        echo "    Configuring..."
        chmod +x configure
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
            -system-zlib \
            -system-libpng \
            -system-libjpeg \
            -fontconfig \
            -I"$ZLIB_INCLUDE" \
            -I"$PCRE_INCLUDE" \
            -L"$ZLIB_LIB" \
            -L"$PCRE_LIB" \
            -lz \
            -lpcre \
            -nomake examples \
            -nomake demos \
            -skip qt3support \
            -skip qt3support \
            -no-opengl
        
        echo "    Compiling (this will take a while)..."
        make -j$(nproc)
        
        echo "    Installing..."
        make install
        
        cd "$DEPENDS"
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
cd src

# Clean previous build
make -f makefile.unix clean

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
    all

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
