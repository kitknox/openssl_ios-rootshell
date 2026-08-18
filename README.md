# OpenSSL for rootshell

This repository contains the Apple-platform build wrapper used to produce the
OpenSSL libraries linked into rootshell's curl framework. It is maintained for
the [rootshell](https://www.rootshell.com) project and is not an upstream
OpenSSL distribution.

The current curl release is built from the official `openssl-3.5.4` tag. The
wrapper produces static `libssl` and `libcrypto` XCFrameworks for:

- iOS devices and arm64 simulators
- Mac Catalyst on arm64 and x86_64
- visionOS devices and arm64 simulators

## Building

Check out the official [openssl/openssl](https://github.com/openssl/openssl)
source beside this repository at the required tag, then run:

```bash
git -C ../openssl checkout openssl-3.5.4
./build.sh
```

To avoid changing an existing sibling checkout, provide another source path:

```bash
OPENSSL_SOURCE_DIR=/path/to/openssl-3.5.4 ./build.sh
```

Generated XCFrameworks are written under `.build/`. They are build inputs for
the rootshell curl release and are not committed to this repository.

## Licensing and upstream issues

OpenSSL remains licensed and maintained by the upstream OpenSSL project. See
the upstream [license](https://github.com/openssl/openssl/blob/master/LICENSE.txt)
and report OpenSSL issues upstream. Report rootshell integration problems in
the [rootshell issue tracker](https://github.com/kitknox/rootshell-app/issues).
