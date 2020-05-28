case $USER in

  lfs)
    continue
    ;;

  *)
    echo "run su - lfs, then run this script again"
    exit 1
    ;;
esac

cat > ~/.bash_profile << "EOF"
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
EOF

cat > ~/.bashrc << "EOF"
set +h
umask 022
LFS=/mnt/lfs
LC_ALL=POSIX
LFS_TGT=$(uname -m)-lfs-linux-gnu
PATH=/tools/bin:/bin:/usr/bin
export LFS LC_ALL LFS_TGT PATH
EOF

source ~/.bash_profile

alias unpack="tar -xf"
export MAKEFLAGS="-j $(grep -c ^processor /proc/cpuinfo)"

# Binutils pass 1
cd $LFS/sources -v
unpack binutils-2.34.tar.xz -v
cd binutils-2.34
mkdir -v build
cd build
../configure --prefix=/tools            \
             --with-sysroot=$LFS        \
             --with-lib-path=/tools/lib \
             --target=$LFS_TGT          \
             --disable-nls              \
             --disable-werror
make 
case $(uname -m) in
  x86_64) mkdir -v /tools/lib && ln -sv lib /tools/lib64 ;;
esac
make install

# GCC pass 1 
cd $LFS/sources -v
unpack gcc-9.2.0.tar.xz -v
cd gcc-9.2.0/
unpack ../mpfr-4.0.2.tar.xz -v
mv -v mpfr-4.0.2 mpfr
unpack ../gmp-6.2.0.tar.xz -v
mv -v gmp-6.2.0 gmp
unpack ../mpc-1.1.0.tar.gz -v
mv -v mpc-1.1.0 mpc
for file in gcc/config/{linux,i386/linux{,64}}.h
do
  cp -uv $file{,.orig}
  sed -e 's@/lib\(64\)\?\(32\)\?/ld@/tools&@g' \
      -e 's@/usr@/tools@g' $file.orig > $file
  echo '
#undef STANDARD_STARTFILE_PREFIX_1
#undef STANDARD_STARTFILE_PREFIX_2
#define STANDARD_STARTFILE_PREFIX_1 "/tools/lib/"
#define STANDARD_STARTFILE_PREFIX_2 ""' >> $file
  touch $file.orig
done
case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
 ;;
esac
mkdir -v build
cd       build
../configure                                       \
    --target=$LFS_TGT                              \
    --prefix=/tools                                \
    --with-glibc-version=2.11                      \
    --with-sysroot=$LFS                            \
    --with-newlib                                  \
    --without-headers                              \
    --with-local-prefix=/tools                     \
    --with-native-system-header-dir=/tools/include \
    --disable-nls                                  \
    --disable-shared                               \
    --disable-multilib                             \
    --disable-decimal-float                        \
    --disable-threads                              \
    --disable-libatomic                            \
    --disable-libgomp                              \
    --disable-libquadmath                          \
    --disable-libssp                               \
    --disable-libvtv                               \
    --disable-libstdcxx                            \
    --enable-languages=c,c++
make
make install

# Linux API headers
cd $LFS/sources -v
unpack linux-5.5.3.tar.xz -v
cd linux-5.5.3/
make mrproper
make headers
cp -rv usr/include/* /tools/include

# Glibc 
cd $LFS/sources -v
unpack glibc-2.31.tar.xz 
cd glibc-2.31/
mkdir -v build
cd build
../configure                             \
      --prefix=/tools                    \
      --host=$LFS_TGT                    \
      --build=$(../scripts/config.guess) \
      --enable-kernel=3.2                \
      --with-headers=/tools/include
make 
make install
 
# Libstdc++
cd $LFS/sources -v
cd gcc-9.2.0
mkdir build-libstdc++
cd build-libstdc++
../libstdc++-v3/configure           \
    --host=$LFS_TGT                 \
    --prefix=/tools                 \
    --disable-multilib              \
    --disable-nls                   \
    --disable-libstdcxx-threads     \
    --disable-libstdcxx-pch         \
    --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/9.2.0
make
make install

# Binutils pass 2
cd $LFS/sources -v
cd binutils-2.34
mkdir build2
cd build2
CC=$LFS_TGT-gcc                \
AR=$LFS_TGT-ar                 \
RANLIB=$LFS_TGT-ranlib         \
../configure                   \
    --prefix=/tools            \
    --disable-nls              \
    --disable-werror           \
    --with-lib-path=/tools/lib \
    --with-sysroot
make 
make install 
make -C ld clean
make -C ld LIB_PATH=/usr/lib:/lib
cp -v ld/ld-new /tools/bin

# GCC pass 2
cd $LFS/sources -v
cd gcc-9.2.0/
cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
  `dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/include-fixed/limits.h
for file in gcc/config/{linux,i386/linux{,64}}.h
do
  cp -uv $file{,.orig}
  sed -e 's@/lib\(64\)\?\(32\)\?/ld@/tools&@g' \
      -e 's@/usr@/tools@g' $file.orig > $file
  echo '
#undef STANDARD_STARTFILE_PREFIX_1
#undef STANDARD_STARTFILE_PREFIX_2
#define STANDARD_STARTFILE_PREFIX_1 "/tools/lib/"
#define STANDARD_STARTFILE_PREFIX_2 ""' >> $file
  touch $file.orig
done
case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
  ;;
esac
sed -e '1161 s|^|//|' \
    -i libsanitizer/sanitizer_common/sanitizer_platform_limits_posix.cc
mkdir build2
cd build2
CC=$LFS_TGT-gcc                                    \
CXX=$LFS_TGT-g++                                   \
AR=$LFS_TGT-ar                                     \
RANLIB=$LFS_TGT-ranlib                             \
../configure                                       \
    --prefix=/tools                                \
    --with-local-prefix=/tools                     \
    --with-native-system-header-dir=/tools/include \
    --enable-languages=c,c++                       \
    --disable-libstdcxx-pch                        \
    --disable-multilib                             \
    --disable-bootstrap                            \
    --disable-libgomp
make
make install
ln -sv gcc /tools/bin/cc

# Tcl
cd $LFS/sources -v
unpack tcl8.6.10-src.tar.gz
cd tcl8.6.10/
cd unix
./configure --prefix=/tools
make
make install
chmod -v u+w /tools/lib/libtcl8.6.so
make install-private-headers
ln -sv tclsh8.6 /tools/bin/tclsh

# Expect
cd $LFS/sources -v
unpack expect5.45.4.tar.gz
cd expect5.45.4/
cp -v configure{,.orig}
sed 's:/usr/local/bin:/bin:' configure.orig > configure
./configure --prefix=/tools       \
            --with-tcl=/tools/lib \
            --with-tclinclude=/tools/include
make
make SCRIPTS="" install

# DejaGNU
cd $LFS/sources -v
unpack dejagnu-1.6.2.tar.gz
cd dejagnu-1.6.2/
./configure --prefix=/tools
make install

# M4
cd $LFS/sources -v
unpack m4-1.4.18.tar.xz 
cd m4-1.4.18/
sed -i 's/IO_ftrylockfile/IO_EOF_SEEN/' lib/*.c
echo "#define _IO_IN_BACKUP 0x100" >> lib/stdio-impl.h
./configure --prefix=/tools
make
make install

# Ncurses
cd $LFS/sources -v
unpack ncurses-6.2.tar.gz 
cd ncurses-6.2/
sed -i s/mawk// configure
./configure --prefix=/tools \
            --with-shared   \
            --without-debug \
            --without-ada   \
            --enable-widec  \
            --enable-overwrite
make
make install
ln -s libncursesw.so /tools/lib/libncurses.so

# Bash
cd $LFS/sources -v
unpack bash-5.0.tar.gz 
cd bash-5.0/
./configure --prefix=/tools --without-bash-malloc
make
make install
ln -sv bash /tools/bin/sh

# Bison
cd $LFS/sources -v
unpack bison-3.5.2.tar.xz 
cd bison-3.5.2/
./configure --prefix=/tools 
make
make install

# Bzip2
cd $LFS/sources -v
unpack bzip2-1.0.8.tar.gz 
cd bzip2-1.0.8/
make -f Makefile-libbz2_so
make clean
make
make PREFIX=/tools install
cp -v bzip2-shared /tools/bin/bzip2
cp -av libbz2.so* /tools/lib
ln -sv libbz2.so.1.0 /tools/lib/libbz2.so

# Coreutils
cd $LFS/sources -v
unpack coreutils-8.31.tar.xz 
cd coreutils-8.31/
./configure --prefix=/tools --enable-install-program=hostname
make
make install

# Diffutils
cd $LFS/sources -v
unpack diffutils-3.7.tar.xz 
cd diffutils-3.7/
./configure --prefix=/tools 
make
make install

# File
cd $LFS/sources -v
unpack file-5.38.tar.gz 
cd file-5.38/
./configure --prefix=/tools 
make
make install

# Findutils
cd $LFS/sources -v
unpack findutils-4.7.0.tar.xz 
cd findutils-4.7.0/
./configure --prefix=/tools 
make
make install

# Gawk
cd $LFS/sources -v
unpack gawk-5.0.1.tar.xz 
cd gawk-5.0.1/
./configure --prefix=/tools 
make
make install

# Gettext
cd $LFS/sources -v
unpack gettext-0.20.1.tar.xz 
cd gettext-0.20.1/
./configure --disable-shared
make
cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /tools/bin

# Grep
cd $LFS/sources -v
unpack grep-3.4.tar.xz 
cd grep-3.4/
./configure --prefix=/tools 
make
make install

# Gzip
cd $LFS/sources -v
unpack gzip-1.10.tar.xz 
cd gzip-1.10/
./configure --prefix=/tools 
make
make install

# Make
cd $LFS/sources -v
unpack make-4.3.tar.gz 
cd make-4.3/
./configure --prefix=/tools --without-guile
make
make install

# Patch
cd $LFS/sources -v
unpack patch-2.7.6.tar.xz 
cd patch-2.7.6/
./configure --prefix=/tools 
make
make install

# Perl
cd $LFS/sources -v
unpack perl-5.30.1.tar.xz 
cd perl-5.30.1/
sh Configure -des -Dprefix=/tools -Dlibs=-lm -Uloclibpth -Ulocincpth
make
cp -v perl cpan/podlators/scripts/pod2man /tools/bin
mkdir -pv /tools/lib/perl5/5.30.1
cp -Rv lib/* /tools/lib/perl5/5.30.1

# Python
cd $LFS/sources -v
unpack Python-3.8.1.tar.xz 
cd Python-3.8.1/
./configure --prefix=/tools --without-ensurepip
make
make install

# Sed
cd $LFS/sources -v
unpack sed-4.8.tar.xz 
cd sed-4.8/
./configure --prefix=/tools 
make
make install

# Tar
cd $LFS/sources -v
unpack tar-1.32.tar.xz 
cd tar-1.32/
./configure --prefix=/tools 
make
make install

# Texinfo
cd $LFS/sources -v
unpack texinfo-6.7.tar.xz 
cd texinfo-6.7/
./configure --prefix=/tools 
make
make install

# Utils-linux
cd $LFS/sources -v
unpack util-linux-2.35.1.tar.xz 
cd util-linux-2.35.1/
./configure --prefix=/tools                \
            --without-python               \
            --disable-makeinstall-chown    \
            --without-systemdsystemunitdir \
            --without-ncurses              \
            PKG_CONFIG=""
make
make install

# Xz
cd $LFS/sources -v
unpack xz-5.2.4.tar.xz 
cd xz-5.2.4/
./configure --prefix=/tools 
make
make install

# Clean up
strip --strip-debug /tools/lib/*
/usr/bin/strip --strip-unneeded /tools/{,s}bin/*
rm -rf /tools/{,share}/{info,man,doc}
find /tools/{lib,libexec} -name \*.la -delete

chown -R root:root $LFS/tools