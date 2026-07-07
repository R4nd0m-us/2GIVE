#!/bin/bash
set -e

# 2GiveCoin Static Linux Build Script
# Produces fully static binaries for 2GiveCoind and 2GiveCoin-cli
# that can run on multiple Linux distributions.
#
# Builds from source in depends/:
# - OpenSSL 1.0.2u (for BN_init / BIGNUM inheritance compatibility)
# - Boost 1.53.0 (for legacy Asio API compatibility)
#
# Uses system static libraries for:
# - Berkeley DB, PCRE, zlib

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== 2GiveCoin Static Linux Build ==="
echo ""

# Fix CRLF line endings in genbuild.sh if present
if [ -f share/genbuild.sh ] && grep -q $'\r' share/genbuild.sh; then
    echo "[*] Fixing line endings in share/genbuild.sh..."
    sed -i 's/\r$//' share/genbuild.sh
fi

# Check for required tools
echo "[*] Checking build tools..."
for cmd in g++ make git wget; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ERROR: $cmd not found. Install build-essential, git, wget."
        exit 1
    fi
done

# Install system dependencies
echo "[*] Ensuring system dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq libdb-dev libpcre3-dev zlib1g-dev pkg-config autoconf

# Detect library paths
echo ""
echo "[*] Detecting libraries..."

ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    LIBDIR="x86_64-linux-gnu"
else
    LIBDIR="$ARCH-linux-gnu"
fi

# Berkeley DB static libs
BDB_LIB_SUFFIX=""
if ls /usr/lib/$LIBDIR/libdb_cxx.a &> /dev/null; then
    echo "[+] Found static Berkeley DB library"
    BDB_LIB_SUFFIX=""
elif ls /usr/lib/$LIBDIR/libdb_cxx-*.a &> /dev/null; then
    echo "[+] Found static Berkeley DB library with suffix"
    BDB_LIB_SUFFIX=$(ls /usr/lib/$LIBDIR/libdb_cxx-*.a | sed 's/.*libdb_cxx\.so//;s/^/-/' | head -c 10)
else
    echo "[-] Berkeley DB static library not found"
    exit 1
fi

# PCRE static lib
if ls /usr/lib/$LIBDIR/libpcre.a &> /dev/null; then
    echo "[+] Found static PCRE library"
else
    echo "[-] Static PCRE library not found"
    exit 1
fi

# zlib static lib
if ls /usr/lib/$LIBDIR/libz.a &> /dev/null; then
    echo "[+] Found static zlib"
else
    echo "[-] Static zlib not found"
    exit 1
fi

# Build OpenSSL 1.0.2u from source (for BN_init and BIGNUM inheritance compatibility)
OPENSSL_DIR="$SCRIPT_DIR/depends/openssl"
if [ ! -f "$OPENSSL_DIR/lib/libssl.a" ]; then
    echo ""
    echo "[*] Building OpenSSL 1.0.2u (static)..."
    mkdir -p "$SCRIPT_DIR/depends"
    cd "$SCRIPT_DIR/depends"
    
    if [ ! -f openssl-1.0.2u.tar.gz ]; then
        echo "    Downloading OpenSSL 1.0.2u..."
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
    
    cd "$SCRIPT_DIR"
    echo "[+] OpenSSL 1.0.2u built successfully"
else
    echo "[+] Using cached OpenSSL build"
fi

OPENSSL_INCLUDE="$OPENSSL_DIR/include"
OPENSSL_LIB="$OPENSSL_DIR/lib"

echo "[+] OpenSSL 1.0.2u ready at $OPENSSL_DIR"

# Build Boost 1.53.0 from source (for legacy Boost.Asio API compatibility)
BOOST_DIR="$SCRIPT_DIR/depends/boost"
if [ ! -f "$BOOST_DIR/stage/lib/libboost_system.a" ]; then
    echo ""
    echo "[*] Building Boost 1.53.0 (static)..."
    mkdir -p "$SCRIPT_DIR/depends"
    cd "$SCRIPT_DIR/depends"
    
    if [ ! -f boost_1_53_0.tar.gz ]; then
        echo "    Downloading Boost 1.53.0..."
        wget -q https://sourceforge.net/projects/boost/files/boost/1.53.0/boost_1_53_0.tar.gz
    fi
    
    echo "    Extracting..."
    tar xzf boost_1_53_0.tar.gz
    cd boost_1_53_0
    
    echo "    Bootstrapping..."
    ./bootstrap.sh
    
    echo "    Compiling (system, filesystem, program_options, thread, chrono, date_time, atomic)..."
    ./b2 link=static runtime-link=static threading=multi address-model=64 \
        --with-system --with-filesystem --with-program_options \
        --with-thread --with-chrono --with-date_time --with-atomic \
        stage
    
    mkdir -p "$BOOST_DIR"
    cp -r boost "$BOOST_DIR/"
    cp -r stage "$BOOST_DIR/"
    
    cd "$SCRIPT_DIR"
    echo "[+] Boost 1.53.0 built successfully"
else
    echo "[+] Using cached Boost build"
fi

BOOST_INCLUDE="$BOOST_DIR"
BOOST_LIB="$BOOST_DIR/stage/lib"

echo "[+] Boost 1.53.0 ready at $BOOST_DIR"

# Create obj directory
mkdir -p src/obj

# Generate build.h
echo ""
echo "[*] Generating build.h..."
if [ -f share/genbuild.sh ]; then
    /bin/sh share/genbuild.sh src/obj/build.h || true
fi

# Build
echo ""
echo "[*] Building 2GiveCoind and 2GiveCoin-cli (static)..."
cd src

# Clean previous build
make -f makefile.unix clean

# Build with static linking against our depends/ libraries
make -f makefile.unix \
    STATIC=all \
    USE_SSE2=1 \
    BOOST_INCLUDE_PATH="$BOOST_INCLUDE" \
    BOOST_LIB_PATH="$BOOST_LIB" \
    BDB_INCLUDE_PATH=/usr/include \
    BDB_LIB_PATH="/usr/lib/$LIBDIR" \
    OPENSSL_INCLUDE_PATH="$OPENSSL_INCLUDE" \
    OPENSSL_LIB_PATH="$OPENSSL_LIB" \
    BOOST_LIB_SUFFIX="" \
    BDB_LIB_SUFFIX="$BDB_LIB_SUFFIX" \
    DEBUGFLAGS="-g" \
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
