#!/bin/sh

readonly build_directory=/var/lib/repro
readonly config_dir=/home/fox/Git/prosjekter/Bash/devtools-repro
readonly bootstrap_mirror=https://mirror.archlinux.no/iso/latest
readonly bootstrap_img=archlinux-bootstrap-"$(date +%Y.%m)".01-"$(uname -m)".tar.gz

exec_nspawn(){
    local container=$1
    systemd-nspawn -q --as-pid2 -D "$build_directory/$container" "${@:2}"
}

set -e

if [ ! -f "$bootstrap_img" ]; then
    curl -O "$bootstrap_mirror/$bootstrap_img"
fi

if [ ! -d "$build_directory" ]; then
    mkdir -p $build_directory
fi

# Prepare root chroot
if [ ! -d "$build_directory"/root ]; then
    echo "Extracting image into container..."
    btrfs subvolume create "$build_directory/root"
    tar xvf "$bootstrap_img" -C "$build_directory/root" --strip-components=1 &> /dev/null

    # host_mirror=$(curl -s 'https://www.archlinux.org/mirrorlist/?protocol=https' | awk '/^#Server/ {print $3; exit}')
    ## Hardcoded until further notice
    host_mirror="http://mirror.neuf.no/archlinux/\$repo/os/\$arch"

    printf 'Server = %s\n' "$host_mirror" > "$build_directory"/root/etc/pacman.d/mirrorlist
    printf '%s.UTF-8 UTF-8\n' en_US de_DE > "$build_directory"/root/etc/locale.gen
    printf 'LANG=en_US.UTF-8\n' > "$build_directory"/root/etc/locale.conf

    cp $config_dir/makepkg.conf "$build_directory"/root/etc/makepkg.conf
    cp $config_dir/pacman.conf "$build_directory"/root/etc/pacman.conf

    systemd-machine-id-setup --root="$build_directory"/root
    echo "Setting up keyring..."
    exec_nspawn root pacman-key --init &> /dev/null
    exec_nspawn root pacman-key --populate archlinux &> /dev/null
    exec_nspawn root pacman-key --refresh &> /dev/bull
    
    echo "Updating and installing base & base-devel"
    exec_nspawn root pacman -Syu --noconfirm --ignore linux
    exec_nspawn root pacman -S base base-devel --noconfirm
    exec_nspawn root locale-gen

    printf 'build ALL = NOPASSWD: /usr/bin/pacman\n' > "$build_directory"/root/etc/sudoers.d/build-pacman
    exec_nspawn root useradd -m -G wheel -s /bin/bash build

    echo "Installing pacman-git"
    mkdir -p "$build_directory"/root/home/build/pacman

    curl -o "$build_directory"/root/home/build/pacman/PKGBUILD https://raw.githubusercontent.com/Earnestly/pkgbuilds/master/pacman-git/PKGBUILD

    exec_nspawn root chown -R build:build /home/build/pacman
    exec_nspawn root sudo -iu build bash -c 'cd pacman && makepkg --noconfirm -csrf'
    exec_nspawn root bash -c "yes | pacman -U /home/build/pacman/pacman-git*"
    cp $config_dir/makepkg.conf "$build_directory"/root/etc/makepkg.conf
    cp $config_dir/pacman.conf "$build_directory"/root/etc/pacman.conf
fi

SOURCE_DATE_EPOCH=$(date +%s)
echo "Using SOURCE_DATE_EPOCH: $SOURCE_DATE_EPOCH"

# Build 1
exec_nspawn root pacman -Syu --noconfirm
echo "Create snapshot for build1..."
btrfs subvolume snapshot "$build_directory/root" "$build_directory/build1"
touch "$build_directory/build1"
exec_nspawn build1 \
    --bind="$PWD:/startdir" \
    --bind="$PWD:/srcdest" \
    bash <<-__END__
set -e
mkdir -p /pkgdest
chown build:build /pkgdest
mkdir -p /srcpkgdest
chown build:build /srcpkgdest
cd /startdir
sudo -u build SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH PKGDEST=/pkgdest SRCPKGDEST=/srcpkgdest makepkg --syncdeps --noconfirm --skipinteg || true
__END__

for pkgfile in "$build_directory"/build1/pkgdest/*; do
    mv "$pkgfile" build1.tar.xz
done

echo "Delete snapshot for build1..."
btrfs subvolume delete "$build_directory/build1"

#### Build 2

echo "Create snapshot for build2..."
btrfs subvolume snapshot "$build_directory/root" "$build_directory/build2"
touch "$build_directory/build2"
exec_nspawn build2 \
    --bind="$PWD:/startdir" \
    --bind="$PWD:/srcdest" \
    bash <<-__END__
set -e
mkdir -p /pkgdest
chown build:build /pkgdest
mkdir -p /srcpkgdest
chown build:build /srcpkgdest
cd /startdir
sudo -u build SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH PKGDEST=/pkgdest SRCPKGDEST=/srcpkgdest makepkg --syncdeps --noconfirm --skipinteg || true
__END__

for pkgfile in "$build_directory"/build2/pkgdest/*; do
    mv "$pkgfile" build2.tar.xz
done

echo "Delete snapshot for build2..."
btrfs subvolume delete "$build_directory/build2"

sha512sum -b build1.tar.xz | read build1_checksum _
sha512sum -b build2.tar.xz | read build2_checksum _
if [ "$build1_checksum" = "$build2_checksum" ]; then
  echo "Reproducible package!"
else
  echo "Not reproducible!"
fi
