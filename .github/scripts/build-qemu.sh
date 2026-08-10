#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_dir="${1:?output directory is required}"
qemu_version="${PODROID_QEMU_VERSION:?PODROID_QEMU_VERSION is required}"
ndk_root="${ANDROID_NDK_ROOT:?ANDROID_NDK_ROOT is required}"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"

llvm="$ndk_root/toolchains/llvm/prebuilt/linux-x86_64"
prefix="$work_dir/deps"
source_dir="$work_dir/src"
qemu_out="$work_dir/qemu-out"
cc="$llvm/bin/aarch64-linux-android26-clang"
ar="$llvm/bin/llvm-ar"
pkg_config_wrapper="$work_dir/aarch64-android-pkg-config"
cross_file="$work_dir/cross-android-aarch64.ini"

test -x "$cc"
mkdir -p "$prefix/lib/pkgconfig" "$prefix/include" "$source_dir" "$output_dir/qemu/keymaps"

cat > "$pkg_config_wrapper" <<EOF
#!/bin/sh
export PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig"
export PKG_CONFIG_PATH=
exec pkg-config "\$@"
EOF
chmod +x "$pkg_config_wrapper"
ln -sf "$pkg_config_wrapper" "$llvm/bin/llvm-pkg-config"
sed \
    -e "s#/opt/ndk#$ndk_root#g" \
    -e "s#/opt/deps#$prefix#g" \
    -e "s#/usr/local/bin/aarch64-android-pkg-config#$pkg_config_wrapper#g" \
    "$repo_root/build-tools/cross-android-aarch64.ini" > "$cross_file"

download() {
    local url="$1"
    local destination="$2"
    curl --fail --location --retry 3 --output "$destination" "$url"
}

cd "$source_dir"

download \
    "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.44/pcre2-10.44.tar.gz" \
    pcre2.tar.gz
tar -xf pcre2.tar.gz
(
    cd pcre2-10.44
    ./configure --host=aarch64-linux-android --prefix="$prefix" \
        --enable-static --disable-shared CC="$cc"
    make -j"$(nproc)" install
)

download \
    "https://github.com/libffi/libffi/releases/download/v3.4.6/libffi-3.4.6.tar.gz" \
    libffi.tar.gz
tar -xf libffi.tar.gz
(
    cd libffi-3.4.6
    ./configure --host=aarch64-linux-android --prefix="$prefix" \
        --enable-static --disable-shared CC="$cc"
    make -j"$(nproc)" install
)

cat > "$prefix/include/iconv.h" <<'EOF'
#ifndef PODROID_ICONV_H
#define PODROID_ICONV_H
#include <stddef.h>
typedef void *iconv_t;
iconv_t iconv_open(const char *tocode, const char *fromcode);
size_t iconv(iconv_t cd, char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft);
int iconv_close(iconv_t cd);
#endif
EOF
cat > "$work_dir/iconv_shim.c" <<'EOF'
#include <errno.h>
#include <stddef.h>
#include <string.h>
#include <iconv.h>
iconv_t iconv_open(const char *tocode, const char *fromcode) {
    if (!tocode || !fromcode) { errno = EINVAL; return (iconv_t)-1; }
    return (iconv_t)1;
}
size_t iconv(iconv_t cd, char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft) {
    (void)cd;
    if (!inbuf || !inbytesleft || !outbuf || !outbytesleft) { errno = EINVAL; return (size_t)-1; }
    if (!*inbuf || *inbytesleft == 0) return 0;
    if (!*outbuf || *outbytesleft == 0) { errno = E2BIG; return (size_t)-1; }
    size_t n = (*inbytesleft < *outbytesleft) ? *inbytesleft : *outbytesleft;
    memcpy(*outbuf, *inbuf, n);
    *inbuf += n;
    *outbuf += n;
    *inbytesleft -= n;
    *outbytesleft -= n;
    if (*inbytesleft != 0) { errno = E2BIG; return (size_t)-1; }
    return 0;
}
int iconv_close(iconv_t cd) { (void)cd; return 0; }
EOF
"$cc" --sysroot="$llvm/sysroot" -target aarch64-linux-android26 \
    -I"$prefix/include" -c "$work_dir/iconv_shim.c" -o "$work_dir/iconv_shim.o"
"$ar" rcs "$prefix/lib/libiconv.a" "$work_dir/iconv_shim.o"
cp "$prefix/lib/libiconv.a" "$llvm/sysroot/usr/lib/aarch64-linux-android/26/libiconv.a"

download "https://download.gnome.org/sources/glib/2.82/glib-2.82.5.tar.xz" glib.tar.xz
tar -xf glib.tar.xz
meson setup glib-2.82.5/_build glib-2.82.5 \
    --cross-file "$cross_file" --prefix "$prefix" --default-library static \
    -Dselinux=disabled -Dlibmount=disabled
ninja -C glib-2.82.5/_build install

download "https://cairographics.org/releases/pixman-0.44.2.tar.xz" pixman.tar.xz
tar -xf pixman.tar.xz
meson setup pixman-0.44.2/_build pixman-0.44.2 \
    --cross-file "$cross_file" --prefix "$prefix" --default-library static \
    -Da64-neon=disabled
ninja -C pixman-0.44.2/_build install

download "https://download.savannah.gnu.org/releases/attr/attr-2.5.2.tar.gz" attr.tar.gz
tar -xf attr.tar.gz
(
    cd attr-2.5.2
    ./configure --host=aarch64-linux-android --prefix="$prefix" \
        --enable-static --disable-shared CC="$cc"
    make -j"$(nproc)" install
)
cp "$prefix/lib/libattr.a" "$llvm/sysroot/usr/lib/aarch64-linux-android/26/libattr.a"

git clone --depth=1 https://github.com/kaniini/libucontext.git libucontext
make -C libucontext -j"$(nproc)" ARCH=aarch64 CC="$cc" AR="$ar" EXPORT_UNPREFIXED=yes
install -Dm644 libucontext/libucontext.a "$prefix/lib/libucontext.a"
install -Dm644 libucontext/include/libucontext/libucontext.h \
    "$prefix/include/libucontext/libucontext.h"
install -Dm644 libucontext/arch/common/include/libucontext/bits.h \
    "$prefix/include/libucontext/bits.h"
cat > "$prefix/include/ucontext.h" <<'EOF'
#ifndef PODROID_UCONTEXT_SHIM_H
#define PODROID_UCONTEXT_SHIM_H
#include_next <ucontext.h>
#include <libucontext/libucontext.h>
#define getcontext libucontext_getcontext
#define makecontext libucontext_makecontext
#define setcontext libucontext_setcontext
#define swapcontext libucontext_swapcontext
#endif
EOF

download \
    "https://github.com/libusb/libusb/releases/download/v1.0.27/libusb-1.0.27.tar.bz2" \
    libusb.tar.bz2
tar -xf libusb.tar.bz2
(
    cd libusb-1.0.27
    ./configure --host=aarch64-linux-android --prefix="$prefix" \
        --enable-static --disable-shared --disable-udev CC="$cc"
    make -j"$(nproc)" install
)

qemu_dir="qemu-${qemu_version}"
download "https://download.qemu.org/${qemu_dir}.tar.xz" qemu.tar.xz
tar -xf qemu.tar.xz
sed -i "s/rt = cc.find_library('rt', required: true)/rt = cc.find_library('rt', required: false)/" \
    "$qemu_dir/meson.build"
printf '#undef st_atime_nsec\n#undef st_mtime_nsec\n#undef st_ctime_nsec\n' | \
    cat - "$qemu_dir/fsdev/9p-marshal.h" > "$work_dir/9p-marshal.h"
mv "$work_dir/9p-marshal.h" "$qemu_dir/fsdev/9p-marshal.h"
printf '# disabled for Android Bionic\n' > "$qemu_dir/contrib/ivshmem-server/meson.build"
printf '# disabled for Android Bionic\n' > "$qemu_dir/contrib/ivshmem-client/meson.build"

cat > "$work_dir/shm_shim.h" <<'EOF'
#ifndef PODROID_SHM_SHIM_H
#define PODROID_SHM_SHIM_H
extern int shm_open(const char *, int, unsigned);
extern int shm_unlink(const char *);
#endif
EOF
cat > "$work_dir/shm_stub.c" <<'EOF'
#include <sys/syscall.h>
#include <unistd.h>
#include <errno.h>
#ifndef SYS_memfd_create
#define SYS_memfd_create 279
#endif
int shm_open(const char *n, int f, unsigned m) {
    (void)f; (void)m;
    while (*n == '/') n++;
    long fd = syscall(SYS_memfd_create, n, 0);
    if (fd < 0) { errno = (int)(-fd); return -1; }
    return (int)fd;
}
int shm_unlink(const char *n) { (void)n; return 0; }
EOF
"$cc" --sysroot="$llvm/sysroot" -target aarch64-linux-android26 \
    -c "$work_dir/shm_stub.c" -o "$work_dir/shm_stub.o"
"$ar" rcs "$prefix/lib/libshm.a" "$work_dir/shm_stub.o"

cat > "$work_dir/qemu_jmp.h" <<'EOF'
#ifndef PODROID_QEMU_JMP_H
#define PODROID_QEMU_JMP_H
#include <setjmp.h>
extern int _qemu_setjmp(sigjmp_buf);
__attribute__((noreturn)) extern void _qemu_longjmp(sigjmp_buf, int);
#endif
EOF
cat > "$work_dir/qemu_jmp.S" <<'EOF'
.text
.global _qemu_setjmp
.type _qemu_setjmp,%function
_qemu_setjmp:
stp x19,x20,[x0,#0]
stp x21,x22,[x0,#16]
stp x23,x24,[x0,#32]
stp x25,x26,[x0,#48]
stp x27,x28,[x0,#64]
stp x29,x30,[x0,#80]
mov x9,sp
str x9,[x0,#96]
stp d8,d9,[x0,#104]
stp d10,d11,[x0,#120]
stp d12,d13,[x0,#136]
stp d14,d15,[x0,#152]
mov w0,#0
ret
.size _qemu_setjmp,.-_qemu_setjmp
.global _qemu_longjmp
.type _qemu_longjmp,%function
_qemu_longjmp:
ldp x19,x20,[x0,#0]
ldp x21,x22,[x0,#16]
ldp x23,x24,[x0,#32]
ldp x25,x26,[x0,#48]
ldp x27,x28,[x0,#64]
ldp x29,x30,[x0,#80]
ldr x9,[x0,#96]
mov sp,x9
ldp d8,d9,[x0,#104]
ldp d10,d11,[x0,#120]
ldp d12,d13,[x0,#136]
ldp d14,d15,[x0,#152]
cmp w1,#0
csinc w0,w1,wzr,ne
br x30
.size _qemu_longjmp,.-_qemu_longjmp
.section .note.GNU-stack,"",%progbits
EOF
"$cc" --sysroot="$llvm/sysroot" -target aarch64-linux-android26 \
    -c "$work_dir/qemu_jmp.S" -o "$work_dir/qemu_jmp.o"
"$ar" rcs "$prefix/lib/libqemujmp.a" "$work_dir/qemu_jmp.o"

sed -i "1i#include \"$work_dir/qemu_jmp.h\"" "$qemu_dir/util/coroutine-ucontext.c"
sed -i 's/\bsigsetjmp(\([^,]*\), *0)/_qemu_setjmp(\1)/g' "$qemu_dir/util/coroutine-ucontext.c"
sed -i 's/\bsiglongjmp(/_qemu_longjmp(/g' "$qemu_dir/util/coroutine-ucontext.c"
sed -i 's@^    rc = libusb_init(&ctx);@#if defined(__ANDROID__)\n    libusb_set_option(NULL, LIBUSB_OPTION_NO_DEVICE_DISCOVERY); /* unprivileged Android: wrap passed fd only, skip enumeration */\n#endif\n    rc = libusb_init(\&ctx);@' \
    "$qemu_dir/hw/usb/host-libusb.c"
grep -q LIBUSB_OPTION_NO_DEVICE_DISCOVERY "$qemu_dir/hw/usb/host-libusb.c"

(
    cd "$qemu_dir"
    ./configure \
        --cc="$cc" \
        --cross-prefix="$llvm/bin/llvm-" \
        --extra-cflags="-fPIC -DANDROID -include $work_dir/shm_shim.h -I$prefix/include -I$prefix/include/glib-2.0 -I$prefix/lib/glib-2.0/include" \
        --extra-ldflags="-L$prefix/lib -Wl,-z,max-page-size=16384 $prefix/lib/libucontext.a $prefix/lib/libshm.a $prefix/lib/libqemujmp.a" \
        --prefix="$qemu_out" \
        --target-list=aarch64-softmmu \
        --enable-tcg --enable-slirp --enable-virtfs --enable-libusb --enable-pie \
        --disable-docs --disable-gtk --disable-sdl --disable-vnc \
        --disable-vhost-user --disable-plugins --with-coroutine=ucontext
    make -j"$(nproc)" install
)

"$cc" --sysroot="$llvm/sysroot" -target aarch64-linux-android26 \
    -fPIE -pie -Wl,-z,max-page-size=16384 \
    "$repo_root/podroid-bridge.c" -o "$qemu_out/libpodroid-bridge.so"
"$cc" --sysroot="$llvm/sysroot" -target aarch64-linux-android26 \
    -fPIE -pie -Wl,-z,max-page-size=16384 \
    "$repo_root/podroid-launcher.c" -o "$qemu_out/libpodroid-launcher.so"

cp "$qemu_out/bin/qemu-system-aarch64" "$output_dir/libqemu-system-aarch64.so"
cp "$qemu_out/lib/libslirp.so.0" "$output_dir/libslirp.so"
cp "$qemu_out/libpodroid-bridge.so" "$output_dir/libpodroid-bridge.so"
cp "$qemu_out/libpodroid-launcher.so" "$output_dir/libpodroid-launcher.so"
cp "$qemu_out/share/qemu/efi-virtio.rom" "$output_dir/qemu/efi-virtio.rom"
cp -a "$qemu_out/share/qemu/keymaps/." "$output_dir/qemu/keymaps/"
patchelf --set-soname libslirp.so "$output_dir/libslirp.so"
patchelf --replace-needed libslirp.so.0 libslirp.so "$output_dir/libqemu-system-aarch64.so"

for artifact in \
    libqemu-system-aarch64.so \
    libslirp.so \
    libpodroid-bridge.so \
    libpodroid-launcher.so; do
    test -s "$output_dir/$artifact"
done
