#!/bin/sh

# Misc functions i want from pacman and makepkg

set -eE -o pipefail

readonly build_directory=/var/lib/repro
readonly bootstrap_mirror=https://mirror.archlinux.no/iso/latest
readonly bootstrap_img=archlinux-bootstrap-"$(date +%Y.%m)".01-"$(uname -m)".tar.gz

readonly config_dir=/home/fox/Git/prosjekter/Bash/devtools-repro

# Default options
use_rsync=false
pacman_conf=$config_dir/pacman.conf
makepkg_conf=$config_dir/makepkg.conf

# img_directory=$(mktemp -dt .arch_img)
img_directory="/tmp/arch_img"
mkdir -p $img_directory



orig_argv=("$0" "$@")
check_root() {
	(( EUID == 0 )) && return
	if type -P sudo >/dev/null; then
		exec sudo -- "${orig_argv[@]}"
	else
		exec su root -c "$(printf ' %q' "${orig_argv[@]}")"
	fi
}

is_btrfs() {
	[[ -e "$1" && "$(stat -f -c %T "$1")" == btrfs ]]
}

is_subvolume() {
	[[ -e "$1" && "$(stat -f -c %T "$1")" == btrfs && "$(stat -c %i "$1")" == 256 ]]
}

colorize() {
	# prefer terminal safe colored and bold text when tput is supported
	if tput setaf 0 &>/dev/null; then
		ALL_OFF="$(tput sgr0)"
		BOLD="$(tput bold)"
		BLUE="${BOLD}$(tput setaf 4)"
		GREEN="${BOLD}$(tput setaf 2)"
		RED="${BOLD}$(tput setaf 1)"
		YELLOW="${BOLD}$(tput setaf 3)"
	else
		ALL_OFF="\e[0m"
		BOLD="\e[1m"
		BLUE="${BOLD}\e[34m"
		GREEN="${BOLD}\e[32m"
		RED="${BOLD}\e[31m"
		YELLOW="${BOLD}\e[33m"
	fi
	readonly ALL_OFF BOLD BLUE GREEN RED YELLOW
}
colorize

plain() {
	local mesg=$1; shift
	printf "${BOLD}    ${mesg}${ALL_OFF}\n" "$@" >&2
}

msg() {
	local mesg=$1; shift
	printf "${GREEN}==>${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
}

msg2() {
	local mesg=$1; shift
	printf "${BLUE}  ->${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
}

warning() {
	local mesg=$1; shift
	printf "${YELLOW}==> $(gettext "WARNING:")${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
}

error() {
	local mesg=$1; shift
	printf "${RED}==> $(gettext "ERROR:")${ALL_OFF}${BOLD} ${mesg}${ALL_OFF}\n" "$@" >&2
}



exec_nspawn(){
    local container=$1
    systemd-nspawn -q --as-pid2 -D "$build_directory/$container" "${@:2}"
}

cleanup_root_volume(){
    warning "Removing root container..."
    if is_subvolume "$build_directory/$build"; then 
        btrfs subvolume delete "$build_directory/root" &> /dev/null
    else
        rm -rf "$build_directory/root"
    fi
}

# $1 -> name of container
remove_snapshot (){
    local build=$1
    msg2 "Delete snapshot for $build..."
    if is_subvolume "$build_directory/$build"; then 
        btrfs subvolume delete "$build_directory/$build" &> /dev/null
    else
        rm -rf "$build_directory/$build"
    fi
}

# $1 -> name of container
create_snapshot (){
    local build=$1

    trap '{ remove_snapshot $build ; exit 1; }' ERR
    trap '{ remove_snapshot $build ; trap - INT; kill -INT $$; }' INT

    msg2 "Create snapshot for $build..."
    if $use_rsync || ! is_btrfs "$build_directory/root"; then 
        msg2 "Creating rsync snapshot"
        mkdir -p "$build_directory/$build"
		rsync -a --delete -W -x "$build_directory/root/" "$build_directory/$build"
    else
        msg2 "Creating btrfs snapshot"
        if ! btrfs subvolume snapshot "$build_directory/root" "$build_directory/$build" &> /dev/null; then
            error "Couldn't create snapshot, did you forget -R?"
            remove_snapshot $build && exit 1
        fi
    fi

    touch "$build_directory/$build"
}


build_package(){
    local build=$1
    exec_nspawn $build \
        --bind="$PWD:/startdir" \
        --bind="$PWD:/srcdest" \
bash <<-__END__
set -e
mkdir -p /pkgdest
chown build:build /pkgdest
mkdir -p /srcpkgdest
chown build:build /srcpkgdest
cd /startdir
sudo -u build SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH PKGDEST=/pkgdest SRCPKGDEST=/srcpkgdest makepkg -sc --noconfirm || true
__END__
    mkdir -p "./$build" || true
    for pkgfile in "$build_directory/$build"/pkgdest/*; do
        mv "$pkgfile" "./$build/"
    done
}

init_chroot(){
    set -e

    check_root

    if [ ! -d "$build_directory" ]; then
        mkdir -p $build_directory
    fi

    # Prepare root chroot
    if [ ! -d "$build_directory"/root ]; then

        msg "Preparing chroot"
        trap '{ cleanup_root_volume; exit 1; }' ERR
        trap '{ cleanup_root_volume; trap - INT; kill -INT $$; }' INT

        msg2 "Extracting image into container..."
        # mkdir -p $build_directory/root
        # Turn into a subvolume if there is btrfs present
        if ! $use_rsync && is_btrfs "$build_directory"; then 
            msg "Creating btrfs root container"
            btrfs subvolume create "$build_directory/root" > /dev/null
        else
            mkdir -p $build_directory/root
        fi
        tar xvf "$img_directory/$bootstrap_img" -C "$build_directory/root" --strip-components=1 > /dev/null

        # host_mirror=$(curl -s 'https://www.archlinux.org/mirrorlist/?protocol=https' | awk '/^#Server/ {print $3; exit}')
        ## Hardcoded until further notice
        host_mirror="http://mirror.neuf.no/archlinux/\$repo/os/\$arch"

        printf 'Server = %s\n' "$host_mirror" > "$build_directory"/root/etc/pacman.d/mirrorlist
        printf '%s.UTF-8 UTF-8\n' en_US de_DE > "$build_directory"/root/etc/locale.gen
        printf 'LANG=en_US.UTF-8\n' > "$build_directory"/root/etc/locale.conf

        echo $makepkg_conf
        echo $pacman_conf

        cp $makepkg_conf "$build_directory"/root/etc/makepkg.conf
        cp $pacman_conf "$build_directory"/root/etc/pacman.conf

        systemd-machine-id-setup --root="$build_directory"/root
        msg2 "Setting up keyring, this might take a while..."
        # exec_nspawn root pacman-key --init #&> /dev/null
        # exec_nspawn root pacman-key --populate archlinux #&> /dev/null
        # exec_nspawn root pacman-key --refresh #&> /dev/bull
        
        msg2 "Updating and installing base & base-devel"
        exec_nspawn root pacman -Syu --noconfirm --ignore pacman-git
        exec_nspawn root pacman -S base-devel --noconfirm --ignore pacman-git
        exec_nspawn root locale-gen

        printf 'build ALL = NOPASSWD: /usr/bin/pacman\n' > "$build_directory"/root/etc/sudoers.d/build-pacman
        exec_nspawn root useradd -m -G wheel -s /bin/bash build

        msg2 "Installing pacman-git"
        exec_nspawn root bash -c "yes | pacman -S pacman-git"
        cp $makepkg_conf "$build_directory"/root/etc/makepkg.conf
        cp $pacman_conf "$build_directory"/root/etc/pacman.conf
    fi
}

cmd_build(){

    check_root

    SOURCE_DATE_EPOCH=$(date +%s)
    msg "Using SOURCE_DATE_EPOCH: $SOURCE_DATE_EPOCH"

    # trap '{ cleanup_snapshot; exit 1; }' ERR
    
    exec_nspawn root pacman -Syu --noconfirm

    # Build 1
    msg "Starting build1..."
    create_snapshot "build1"
    build_package "build1"
    remove_snapshot "build1"

    # Build 2
    msg "Starting build2..."
    create_snapshot "build2"
    build_package "build2"
    remove_snapshot "build2"

    msg "Comparing hashes..."
    is_error=false
    for pkgfile in ./build1/*; do
        sha512sum -b $pkgfile | read build1_checksum _
        sha512sum -b $pkgfile | read build2_checksum _
        if [ "$build1_checksum" = "$build2_checksum" ]; then
          msg2 "${pkgfile##*/} is reproducible!"
        else
          warning "${pkgfile##*/} is not reproducible!"
          is_error=true
        fi
    done

    if $is_error; then
        error "Package is not reproducible"
    else
        msg "Package is reproducible!"
    fi
}

cmd_check(){
    echo "Doing a build!"
}

cmd_help(){
cat <<__END__
Usage:   
  repro <command> [options]

Commands:
  check                       Recreate a package file
  build                       Build a package and test for reproducability 
  help                        This help message

General Options:
 -R                           Force the rsync subcontainer creation
 -C                           Specify pacman.conf to build with
 -M                           Specify makepkg.conf to build with
__END__
}

args(){
    while getopts :R arg; do
        case $arg in
            R) use_rsync=true;;
            C) pacman_conf=$OPTARG;;
            M) makepkg_conf=$OPTARG;;
            *);;
        esac
    done
}

if [ ! -e "$img_directory/$bootstrap_img" ]; then
    curl -o  "$img_directory/$bootstrap_img" "$bootstrap_mirror/$bootstrap_img"
fi

case "$1" in
    help) cmd_help "$@" ;;
    check) shift; args "$@"; init_chroot; cmd_check "$@" ;;
    build) shift; args "$@"; init_chroot; cmd_build "$@" ;;
    *) args "$@"; init_chroot; cmd_build "$@" ;;
esac
