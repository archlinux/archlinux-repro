#!/bin/sh

readonly build_directory=$PWD/builds

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
    tar xvf "$bootstrap_img" -C "$build_directory" &> /dev/null
    mv "$build_directory"/root.* "$build_directory"/root

    # host_mirror=$(curl -s 'https://www.archlinux.org/mirrorlist/?protocol=https' | awk '/^#Server/ {print $3; exit}')
    ## Hardcoded until further notice
    host_mirror="http://mirror.neuf.no/archlinux/\$repo/os/\$arch"

    printf 'Server = %s\n' "$host_mirror" > "$build_directory"/root/etc/pacman.d/mirrorlist
    printf '%s.UTF-8 UTF-8\n' en_US de_DE > "$build_directory"/root/etc/locale.gen
    printf 'LANG=en_US.UTF-8\n' > "$build_directory"/root/etc/locale.conf

    cp ./makepkg.conf "$build_directory"/root/etc/makepkg.conf
    cp ./pacman.conf "$build_directory"/root/etc/pacman.conf

    systemd-machine-id-setup --root="$build_directory"/root

    exec_nspawn root pacman-key --init &> /dev/null
    exec_nspawn root pacman-key --populate archlinux &> /dev/null
    exec_nspawn root pacman-key --refresh &> /dev/bull
    
    exec_nspawn root pacman -Syu --noconfirm --ignore linux --ignore mkinitcpio
    exec_nspawn root pacman -S base base-devel --noconfirm
    exec_nspawn root locale-gen

    printf 'build ALL = NOPASSWD: /usr/bin/pacman\n' > "$build_directory"/root/etc/sudoers.d/build-pacman
    exec_nspawn root useradd -m -G wheel -s /bin/bash build

    mkdir -p "$build_directory"/root/home/build/pacman

    curl -o "$build_directory"/root/home/build/pacman/PKGBUILD https://raw.githubusercontent.com/Earnestly/pkgbuilds/master/pacman-git/PKGBUILD

    exec_nspawn root chown -R build:build /home/build/pacman
    exec_nspawn root sudo -iu build bash -c 'cd pacman && makepkg --noconfirm -csrif'
    cp ./makepkg.conf "$build_directory"/root/etc/makepkg.conf
    cp ./pacman.conf "$build_directory"/root/etc/pacman.conf
fi




exec_nspawn root bash
