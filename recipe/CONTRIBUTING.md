# conda-forge-ci-setup contributing guidelines

## Adding a new OSX SDK

SDKs are listed in two files, each mapping a version to a URL, sha256 and
package kind. `download_osx_sdk.sh` prefers `macosx_sdks_cdn.json` and falls back to
`macosx_sdks_legacy.json` for versions it lacks or when a download fails. Both
list the newest versions first.

- `macosx_sdks_cdn.json`: Command Line Tools packages on Apple's software update CDN,
  one per minor version using its newest patch release.
  Regenerate it with `python recipe/discover_macos_sdks.py discover`, which
  rescans Apple's catalogs and downloads every SDK package (so takes a while);
  `python recipe/discover_macos_sdks.py list` summarises it. Existing entries
  are kept as long as they still download.
- `macosx_sdks_legacy.json`: `.sdk.tar.xz` tarballs from GitHub mirrors such as
  https://github.com/joseluisq/macosx-sdks; edit it by hand.
- `test_osx_sdk.sh` downloads every SDK in both files, and `test_osx_sdk_metal.sh`
  checks what each one from 26.0 on offers Metal code.
- Temporarily test it works:
    1. Define `MACOSX_SDK_VERSION` in `conda_build_config.yaml`; e.g. `MACOS_SDK_VERSION: ["26.1"] # [osx]`.
    2. Add a dummy variable using in it `meta.yaml`; e.g. `{% set _dummy = MACOSX_SDK_VERSION %}`.
    3. Pick `osx` and a single Python version, and skip the rest; e.g. `skip: true # [not (osx and py==313)]`
    4. Rerender and push the commits.
    5. When everything passes, revert steps 1-4 and rerender again so it's ready for review/merge.

## Compiling Metal shaders with these SDKs

Feedstocks that compile Metal shaders, such as pytorch and mlx, need two things:

- A Metal compiler: `xcrun metal` comes from the runner's Xcode, not from the SDK.
  `-std=metal4.0` needs Xcode 26 or newer, and its Metal Toolchain component
  (`xcodebuild -downloadComponent MetalToolchain`).
- An SDK with the headers: `MetalPerformancePrimitives` is in 26.0 and newer, and
  the cooperative tensor input accessors in 26.2 and newer. `xcrun metal` ignores
  `CONDA_BUILD_SYSROOT`, so point it at the downloaded SDK with
  `export SDKROOT="${CONDA_BUILD_SYSROOT}"`. Use it after any `xcodebuild` step.
  `xcrun --show-sdk-version` then fails, so read the version from `SDKSettings.plist`.

Check the compiler explicitly, as code that guards these headers with
`__has_include` still compiles against an older SDK, and just leaves kernels out.
