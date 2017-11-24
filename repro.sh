#!/usr/bin/bash

readonly BUILD_DIRECTORY="$(pwd)/builds"

readonly BOOTSTRAP_MIRROR="https://mirror.archlinux.no/iso/latest"
readonly BOOTSTRAP_IMG="archlinux-bootstrap-$(date +"%Y.%m").01-x86_64.tar.gz"

exec_nspawn(){
    container="$1" && shift 1
    systemd-nspawn -q \
        --as-pid2 \
        -D $BUILD_DIRECTORY/$container "$@"
}

init_container(){
    if [ ! -d $BUILD_DIRECTORY/root ]; then
        tar xvf $1 -C $BUILD_DIRECTORY
        mv $BUILD_DIRECTORY/root.* $BUILD_DIRECTORY/root

        host_mirror=$(pacman --cachedir /doesnt/exist -Sddp extra/devtools 2>/dev/null | sed -r 's#(.*/)extra/os/.*#\1$repo/os/$arch#')
        echo "Server = $host_mirror" >"$BUILD_DIRECTORY/root/etc/pacman.d/mirrorlist"
        sed -r "s|^#?\\s*CacheDir.+|CacheDir = $(echo -n "${cache_dirs[@]}")|g" -i "$BUILD_DIRECTORY/root/etc/pacman.conf"
        printf '%s.UTF-8 UTF-8\n' en_US de_DE > "$BUILD_DIRECTORY/root/etc/locale.gen"
        echo 'LANG=en_US.UTF-8' > "$BUILD_DIRECTORY/root/etc/locale.conf"
        cp "./makepkg.conf" "$BUILD_DIRECTORY/root/etc/makepkg.conf"
        cp "./pacman.conf" "$BUILD_DIRECTORY/root/etc/pacman.conf"
        systemd-machine-id-setup --root="$BUILD_DIRECTORY/root"
        init_archlinux
    fi
}

install_user(){
    exec_nspawn root useradd -m -G wheel -s /bin/bash build
    echo "build ALL = NOPASSWD: /usr/bin/pacman" > $BUILD_DIRECTORY/root/etc/sudoers.d/build-pacman
}

install_pacman-git(){
    mkdir -p $BUILD_DIRECTORY/root/home/build/pacman
    curl -o $BUILD_DIRECTORY/root/home/build/pacman/PKGBUILD https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=pacman-git

    echo 'provides=("pacman=5.0.2")' >> $BUILD_DIRECTORY/root/home/build/pacman/PKGBUILD
    exec_nspawn root chown -R build:build /home/build/pacman
    exec_nspawn root sudo -iu build bash -c 'cd pacman; makepkg --noconfirm -si'
    # Pacman replaces these files, so lets reinsert them
    cp "./makepkg.conf" "$BUILD_DIRECTORY/root/etc/makepkg.conf"
    cp "./pacman.conf" "$BUILD_DIRECTORY/root/etc/pacman.conf"
}

init_archlinux(){
    exec_nspawn root pacman -Syu --noconfirm
    exec_nspawn root pacman -S base base-devel --noconfirm
    exec_nspawn root locale-gen
}

if [ ! -f $BOOTSTRAP_IMG ]; then
    curl -O  $BOOTSTRAP_MIRROR/$BOOTSTRAP_IMG
fi

init_container $BOOTSTRAP_IMG
install_user
install_pacman-git
exec_nspawn root bash

