case $USER in

  root)
    continue
    ;;

  *)
    echo "run sudo su, then run this script again"
    exit 1
    ;;
esac

read -p 'LFS partion (ex: sda1): ' partionname
export LFS=/mnt/lfs 

mkdir -pv $LFS
mount -v -t ext4 /dev/$partionname $LFS
mkdir -v $LFS/sources
chmod -v a+wt $LFS/sources
wget --input-file=deps --continue --directory-prefix=$LFS/sources
mkdir -v $LFS/tools
ln -sv $LFS/tools /
groupadd lfs
useradd -s /bin/bash -g lfs -m -k /dev/null lfs
passwd lfs
chown -v lfs $LFS/tools
chown -v lfs $LFS/sources