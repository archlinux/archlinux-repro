archlinux-repro
===============

`archlinux-repro` is intended to be a tool for users to verify packages distributed by Arch Linux.

The current goals are:
- Recreate packages given a `.BUILDINFO` file, or `.pkg.tar.xz`
- Download and verify needed packages from `archive.archlinux.org`
- Be a simple and easily auditable code
- Distribution independent. One should be able to verify Arch packages on Debian.

Work in progress. Please read the code before using.

## Dependencies

* asciidoc (make)
* coreutils
* curl
* gnupg
* systemd
* bsdtar
* zstd
