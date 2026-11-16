# AUR files

These three files are what gets pushed to the AUR (`ssh://aur@aur.archlinux.org/rog-companion.git`):
`PKGBUILD` (with the release checksum), `rog-companion.install` and `.SRCINFO`.

For each release: bump `pkgver` in `pkgbuild/PKGBUILD`, tag `v<version>`, then update the
checksum here with `updpkgsums` and regenerate `.SRCINFO` with `makepkg --printsrcinfo > .SRCINFO`.
