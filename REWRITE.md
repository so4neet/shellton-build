# Rewrite of Shellton

Shellton has become very fragmented due to a lack of structure throughout the build process, so now I am restarting with a clear layout of what needs to happen for development.


## RULES

There are 2 package types: Corepackages and Syspackages

## Corepackages

Corepackages are "standard" Linux packages, installed into root. These exist solely for packages that will not work bundled with their dependencies.

Packages MUST NOT contain bin, sbin, lib, or lib64 TOP LEVEL DIRECTORIES. Packages will be built with the /usr prefix before ALL top level directories, and if build scripts do not comply, Shellton should contain a sanitizer to ensure that folders are renamed to comply.

Corepackages should NOT be used for any application or program that is not VITAL to the system's function. This type of package is reserved ONLY for system level tools that can NOT be packed elsewhere.

Current list of Corepackages are:

linux
linux-headers
glibc
systemd
lira-base

This list SHOULD NOT CHANGE unless a VITAL SYSTEM FUNCTION cannot be a syspackage

## Syspackages

Syspackages are packages bundled with all of their dependencies. These live in /opt/syspackages/ and their binaries are symlinked to /usr/bin. A sysroot called syslibs on the build host should contain all libraries needed, and build processes should pull libraries from that directory into the syspackage at build time, then patch the binaries to look internally for their dependencies.

## Signing

Openssl key generated offline, packages are NOT signed on the build server. They are transferred to the offline machine and signed, then placed back on the build server's staging directory to be uploaded to the repository. 

## Code

Code should remain *SIMPLE*. Processes shouldn't be over-complicated, and relying on janky fixes for core functions is not acceptable. 