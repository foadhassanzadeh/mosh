#!/bin/bash

# Mosh iOS cross compiling script
# by Linus Yang
# Licensed under GPLv3

# Error message
function fatal() {
    echo -e "\033[0;31;1mMosh built failed. Check the log for details.\033[0m"
    exit "$?"
}
trap fatal ERR

# Dependencies libraries
NOWVER="0.1"
MOSHVER="1.2.4"
MOSHBUILD="3"
SSLVER="1.0.1e"
PBVER="2.5.0"
NCVER="5.9"
ACVER="2.69"

echo "[Mosh iOS build script v$NOWVER - Linus Yang]"
LOGFILE="/dev/null"
NOWDIR="$(cd "$(dirname "$0")" && pwd)"
MOSHDIR="$(cd "$(dirname "$0")/../" && pwd)"
PLAT="iphoneos"

# Check arguments, use -v to save log
if [ ! -z "$@" ]; then
    if [[ "$@" == "-h" ]]; then
        echo  "Usage: $(basename "$0") [-v | -h]"
        exit 0
    elif [[ "$@" == "-v" ]]; then
        LOGFILE="$NOWDIR/mosh-$MOSHVER-build-$PLAT.log"
        touch "$LOGFILE"
        echo -e "\033[0;33;1mSaving log to $LOGFILE\033[0m"
    else
        echo "Error: arguments '$@' not accepted"
        fatal
    fi
fi

echo "[Mosh $MOSHVER build for $PLAT @ $(date +"%Y-%m-%d %H:%M:%S")]" >> $LOGFILE

# Variables of path
PLATDIR="$NOWDIR/$PLAT-build"
STAG="$PLATDIR/staging"
STAGLOCAL="$PLATDIR/staging-local"
BUILDDIR="$PLATDIR/build"
SRCDIR="$PLATDIR/src"
PATCHDIR="$NOWDIR/patches"

# Download necessary sources
mkdir -p "$SRCDIR"
cd "$SRCDIR"
echo -e "\033[0;34;1mDownloading sources...\033[0m"
[ ! -f ".ssl_down" ] && curl -O "http://www.openssl.org/source/openssl-$SSLVER.tar.gz" >>"$LOGFILE" 2>&1 && touch ".ssl_down"
[ ! -f ".ac_down" ] && curl -O "http://ftp.gnu.org/gnu/autoconf/autoconf-$ACVER.tar.gz" >>"$LOGFILE" 2>&1 && touch ".ac_down"
[ ! -f ".nc_down" ] && curl -O "http://ftp.gnu.org/pub/gnu/ncurses/ncurses-$NCVER.tar.gz" >>"$LOGFILE" 2>&1 && touch ".nc_down"
[ ! -f ".pb_down" ] && curl -O "https://protobuf.googlecode.com/files/protobuf-$PBVER.tar.bz2" >>"$LOGFILE" 2>&1 && touch ".pb_down"

# Make building directory
mkdir -p "$STAG"
mkdir -p "$BUILDDIR"
cd "$BUILDDIR"

echo -e "\033[0;34;1mMosh $MOSHVER build for $PLAT\033[0m"

# Build host autoconf
echo -e "\033[0;32;1mBuilding autoconf $ACVER locally...\033[0m"
if [ ! -f .acl_built ]; then
    rm -rf autoconf-"$PBVER"-local/
    tar zxf "$SRCDIR"/autoconf-"$ACVER".tar.gz
    mv autoconf-"$ACVER"/ autoconf-"$ACVER"-local/
    cd autoconf-"$ACVER"-local/
    ./configure --prefix="$STAGLOCAL" \
                --enable-static \
                $HOSTFLAG >>"$LOGFILE" 2>&1
    make >>"$LOGFILE" 2>&1
    make install >>"$LOGFILE" 2>&1
    cd "$BUILDDIR"
    touch .acl_built
fi

# Build host protobuf
echo -e "\033[0;32;1mBuilding protobuf $PBVER locally...\033[0m"
if [ ! -f .pbl_built ]; then
    rm -rf protobuf-"$PBVER"-local/
    tar jxf "$SRCDIR"/protobuf-"$PBVER".tar.bz2
    mv protobuf-"$PBVER"/ protobuf-"$PBVER"-local/
    cd protobuf-"$PBVER"-local/
    ./configure --prefix="$STAGLOCAL" \
                --enable-static \
                $HOSTFLAG >>"$LOGFILE" 2>&1
    make >>"$LOGFILE" 2>&1
    make install >>"$LOGFILE" 2>&1
    cd "$BUILDDIR"
    touch .pbl_built
fi

# Set SDK path for iOS
export PATH="$STAGLOCAL/bin:$PATH"
export DEVROOT="$("xcode-select" --print-path)/Platforms/iPhoneOS.platform/Developer"
export SDKVERSION="$(find "$DEVROOT/SDKs" -depth 1 | sed 's/.*iPhoneOS\(.\..\)\.sdk/\1/' | sort -r | head -1)"
export PLATROOT="$DEVROOT/SDKs/iPhoneOS${SDKVERSION}.sdk"
if [ -f "$("xcode-select" --print-path)/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang" ]; then
    export CC="$("xcode-select" --print-path)/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -arch armv7 -isysroot $PLATROOT"
    export CXX="$("xcode-select" --print-path)/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++ -arch armv7 -isysroot $PLATROOT"
    export CODESIGN_ALLOCATE="$("xcode-select" --print-path)/Toolchains/XcodeDefault.xctoolchain/usr/bin/codesign_allocate"
else
    export CC="$DEVROOT/usr/bin/gcc -arch armv7 -isysroot $PLATROOT"
    export CXX="$DEVROOT/usr/bin/g++ -arch armv7 -isysroot $PLATROOT"
    export CODESIGN_ALLOCATE="$DEVROOT/usr/bin/codesign_allocate"
fi
export HOSTFLAG="--host=armv7-apple-darwin"
export CPPFLAGS="-I$STAG/include -I$PLATROOT/usr/include"
export CFLAGS="-O2 $CPPFLAGS"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-L$STAG/lib -L$PLATROOT/usr/lib -isysroot $PLATROOT -miphoneos-version-min=3.0"
export CROSS_TOP="$DEVROOT"
export CROSS_SDK="iPhoneOS${SDKVERSION}.sdk"

# Build protobuf
echo -e "\033[0;32;1mBuilding protobuf $PBVER for $PLAT...\033[0m"
if [ ! -f .pb_built ]; then
    rm -rf protobuf-"$PBVER"/
    tar jxf "$SRCDIR"/protobuf-"$PBVER".tar.bz2
    cd protobuf-"$PBVER"/
    ./configure --prefix="$STAG" \
                --with-protoc="$STAGLOCAL/bin/protoc" \
                --enable-static $HOSTFLAG >>"$LOGFILE" 2>&1
    make >>"$LOGFILE" 2>&1
    make install >>"$LOGFILE" 2>&1
    cd "$BUILDDIR"
    touch .pb_built
fi

# Build libncurses
echo -e "\033[0;32;1mBuilding ncurses $NCVER...\033[0m"
if [ ! -f .nc_built ]; then
    rm -rf ncurses-"$NCVER"/
    tar zxf "$SRCDIR"/ncurses-"$NCVER".tar.gz
    cd ncurses-"$NCVER"/
    patch -p0 < "$PATCHDIR/ncurses-$NCVER-constructor-types.patch" >>"$LOGFILE" 2>&1
    ./configure --prefix="$STAG" \
                --without-debug \
                --enable-mixed-case \
                --enable-pc-files \
                --with-terminfo-dirs="/usr/share/terminfo" \
                --with-default-terminfo-dir="/usr/share/terminfo" \
                PKG_CONFIG_LIBDIR="$STAG/lib/pkgconfig" \
                $HOSTFLAG >>"$LOGFILE" 2>&1
    make >>"$LOGFILE" 2>&1
    make install >>"$LOGFILE" 2>&1
    make clean >>"$LOGFILE" 2>&1
    ./configure --prefix="$STAG" \
                --enable-widec \
                --disable-overwrite \
                --without-debug \
                --enable-mixed-case \
                --enable-pc-files \
                --with-terminfo-dirs="/usr/share/terminfo" \
                --with-default-terminfo-dir="/usr/share/terminfo" \
                PKG_CONFIG_LIBDIR="$STAG/lib/pkgconfig" \
                $HOSTFLAG >>"$LOGFILE" 2>&1
    make >>"$LOGFILE" 2>&1
    make install >>"$LOGFILE" 2>&1
    cd "$BUILDDIR"
    touch .nc_built
fi

# Build openssl
echo -e "\033[0;32;1mBuilding OpenSSL $SSLVER...\033[0m"
if [ ! -f .ssl_built ]; then
    rm -rf openssl-"${SSLVER}"/
    tar zxf "$SRCDIR"/openssl-"${SSLVER}".tar.gz
    cd openssl-"${SSLVER}"/
    SSL_CONF="Configure iphoneos-cross"
    ./$SSL_CONF --prefix="$STAG" \
                --openssldir="$STAG/openssl" >>"$LOGFILE" 2>&1
    make >>"$LOGFILE" 2>&1
    make install >>"$LOGFILE" 2>&1
    cd "$BUILDDIR"
    touch .ssl_built
fi

# Build mosh
echo -e "\033[0;32;1mBuilding Mosh $MOSHVER...\033[0m"
if [ ! -f .mosh_built ]; then
    cd "$MOSHDIR"/
    ./autogen.sh >>"$LOGFILE" 2>&1
    ./configure ac_cv_c_restrict=no \
                ac_cv_poll_pty=yes \
                PKG_CONFIG_PATH="$STAG/lib/pkgconfig" \
                protobuf_LIBS="$STAG/lib/libprotobuf.a" \
                --with-curses="$STAG" \
                --prefix="/usr" \
                $HOSTFLAG >>"$LOGFILE" 2>&1
    make clean >>"$LOGFILE" 2>&1
    make >>"$LOGFILE" 2>&1
    DESTDIR="$NOWDIR/$PLAT-build/mosh-$MOSHVER" make install >>"$LOGFILE" 2>&1
    cd "$BUILDDIR"
    touch .mosh_built
fi

echo -e "\033[0;34;1mMosh built successfully in $NOWDIR/$PLAT-build/mosh-$MOSHVER\033[0m"

# Set package path
LDID="$NOWDIR/tools/ldid"
DPKGDEB="$NOWDIR/tools/dpkg-deb"
FAKEROOT="$NOWDIR/tools/fakeroot"
DESTDIR="$PLATDIR/mosh-$MOSHVER"
DEBROOT="$DESTDIR/debroot"
LOCALEROOT="$DESTDIR/localeroot"

# Clean up
cd "$DESTDIR"
rm -rf debroot localeroot

# Package UTF-8 locales
LOCALEDIR="$LOCALEROOT/usr/share/locale"
mkdir -p "$LOCALEDIR"
cp -pLR /usr/share/locale/en_US.UTF-8 "$LOCALEDIR/"
cp -pLR /usr/share/locale/zh_CN.UTF-8 "$LOCALEDIR/"
LOCALESIZE="$(du -s -k "$LOCALEROOT" | awk '{print $1}')"
LOCALEDEBNAME="com.linusyang.localeutf8_1.0-1"
mkdir -p "$LOCALEROOT/DEBIAN"
echo -ne "Package: com.linusyang.localeutf8\nName: Locale Profiles in UTF-8\nSection: System\nDepends: profile.d\nInstalled-Size: $LOCALESIZE\nMaintainer: Linus Yang <laokongzi@gmail.com>\nArchitecture: iphoneos-arm\nVersion: 1.0-1\nDescription: UTF-8 locale files for en_US and zh_CN\nTag: purpose::console, role::hacker\n" > "$LOCALEROOT/DEBIAN/control"
cd "$DESTDIR"
"$FAKEROOT" "$DPKGDEB" -b localeroot l.deb >>"$LOGFILE" 2>&1
mv -f l.deb "$NOWDIR/$LOCALEDEBNAME"_iphoneos-arm.deb 

# Package Mosh
mkdir -p "$DEBROOT/usr"
cp -pR "$DESTDIR/usr/bin" "$DEBROOT/usr/"
find "$DEBROOT/usr/bin/" -type f -exec "$LDID" -S {} \;
MOSHSIZE="$(du -s -k "$DEBROOT" | awk '{print $1}')"
MOSHDEBNAME="com.linusyang.mosh_$MOSHVER-$MOSHBUILD"
mkdir -p "$DEBROOT/DEBIAN"
echo -ne "Package: com.linusyang.mosh\nName: Mosh\nSection: Networking\nInstalled-Size: $MOSHSIZE\nAuthor: Keith Winstein <keithw@mit.edu>\nMaintainer: Linus Yang <laokongzi@gmail.com>\nSponsor: Linus Yang <http://linusyang.com/>\nArchitecture: iphoneos-arm\nVersion: $MOSHVER-$MOSHBUILD\nDepends: ncurses, openssh, com.linusyang.localeutf8\nDescription: Mosh is a remote terminal application that supports intermittent connectivity, allows roaming, and provides speculative local echo and line editing of user keystrokes.\nHomepage: http://mosh.mit.edu/\nTag: purpose::console\n" > "$DEBROOT/DEBIAN/control"
cd "$DESTDIR"
"$FAKEROOT" "$DPKGDEB" -b debroot m.deb >>"$LOGFILE" 2>&1
mv -f m.deb "$NOWDIR/$MOSHDEBNAME"_iphoneos-arm.deb 

echo -e "\033[0;34;1mMosh packaged successfully\033[0m"
