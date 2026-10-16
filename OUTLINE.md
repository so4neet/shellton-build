# Outline of the Shellton Build System

One central application manages the building of packages, checking for updates, and ensuring that builds function.

Each package is denoted through a Shellton file, <pkg-name>.shellton. This contains metadata about the package that tells the build system how to build it.

The head of a Shellton file contains key information about the package.

```
PKG_NAME
PKG_PRETTY
PKG_DESC
PKG_URL
PKG_VER
PKG_DEPENDS
```

`PKG_NAME` denotes the internal name of the package. For example, we will use the Helium web browser. This would be `helium-browser`

`PKG_PRETTY` denotes the "pretty" name of the package for the GUI interface. This would be "Helium"

`PKG_DESC` denotes the description of the package for the GUI/TUI interfaces. This would be "Private, fast, and honest web browser"

`PKG_URL` denotes the URL to fetch the package from. For Helium, this is through Github, therefore this would be `https://github.com/imputnet/helium-linux/releases/download/${PKG_VER}/helium-${PKG_VER}-x86_64.AppImage`

`PKG_VER` denotes the latest version of the package. This would be, for example, `0.19.3.1`

`PKG_DEPENDS` denotes the dependencies that the package needs to be bundled with. Since Helium distributes an AppImage, this isn't necessary.

## Extra Flags

There are a couple extra flags that are useful for the LiraOS Package Manager.

```
FLAG_APPIMAGE
FLAG_PREPACKAGED
FLAG_SYSPACKAGE
FLAG_NOT_BUNDLEABLE
FLAG_OOD
FLAG_BROKEN
FLAG_DEPRICATED
```

`FLAG_APPIMAGE` denotes that the package is distributed by the Developer as an AppImage, and does not need to be built.

`FLAG_PREPACKAGED` denotes that the package is distributed as a Binary or tarball by the developer and does not need to be built.

`FLAG_SYSPACKAGE` denotes that the package is a core system package necessary for the system to be functional. These typically have their own specific packaging steps.

`FLAG_NOT_BUNDLEABLE` denotes that the package cannot be bundled with its dependencies.

`FLAG_OOD` denotes that the package is out of date.

`FLAG_BROKEN` denotes that the package failed to build.

`FLAG_DEPRICATED` denotes that the package is no longer maintained or updated.

## Extra Functions

Sometimes, a package cannot be built using the default guesses. A custom build() function can be added, which will override the default build logic.

Here's an example.

```
build() {
    meson setup build --prefix=/usr --buildtype=release -Dlibwacom=false -Ddebug-gui=false -Dtests=false -Ddocumentation=false -Dinstall-tests=false
    ninja -C build -j"$(nproc)"
}
```
