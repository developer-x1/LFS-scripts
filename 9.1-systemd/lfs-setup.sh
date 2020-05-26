var=$(dirname "$(realpath $0)")
sh  $var/.lfs-setup.sh 2>&1 | tee lfs-setup.out