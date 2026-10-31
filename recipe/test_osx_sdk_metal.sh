#!/bin/bash
set -e

# Check what an SDK offers Metal code, using pytorch's MPS kernels as the example.
# They call MetalPerformancePrimitives, whose cooperative tensor input accessors
# first appear in 26.2, so 26.0 and 26.1 have the framework but cannot build them.
# The headers are checked everywhere. Compiling also needs a Metal 4 compiler,
# which comes from the runner's Xcode and not from the SDK, so that part only
# runs where there is one.
#
#   bash test_osx_sdk_metal.sh /path/to/MacOSX26.5.sdk 26.5

sdk=$1
version=$2

version_ge() {
  [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)" == "$2" ]]
}

if ! version_ge "${version}" 26.0; then
  exit 0
fi

headers="${sdk}/System/Library/Frameworks/MetalPerformancePrimitives.framework/Versions/A/Headers"
test -f "${headers}/MetalPerformancePrimitives.h"
has_accessors=false
if grep -rq get_left_input_cooperative_tensor "${headers}"; then
  has_accessors=true
fi

if version_ge "${version}" 26.2; then
  expected=true
else
  expected=false
fi
if [[ "${has_accessors}" != "${expected}" ]]; then
  echo "SDK ${version}: expected cooperative tensor input accessors to be ${expected}, found ${has_accessors}"
  exit 1
fi

# `xcrun metal` ignores CONDA_BUILD_SYSROOT, and only reads the SDK from SDKROOT
workdir=$(mktemp -d)
trap 'rm -rf "${workdir}"' EXIT
cat > "${workdir}/language.metal" <<'EOF'
kernel void probe(device float* p, uint i [[thread_position_in_grid]]) {
  auto fn = [](float x) { return x + 1.0; };
  p[i] = fn(p[i]);
}
EOF
cat > "${workdir}/accessors.metal" <<'EOF'
#include <MetalPerformancePrimitives/MetalPerformancePrimitives.h>
using namespace metal;
kernel void probe(device float* p [[buffer(0)]]) {
  constexpr auto desc = mpp::tensor_ops::matmul2d_descriptor(
      16, 32, 16, false, true, true,
      mpp::tensor_ops::matmul2d_descriptor::mode::multiply_accumulate);
  mpp::tensor_ops::matmul2d<desc, execution_simdgroup> op;
  auto a = op.template get_left_input_cooperative_tensor<half, half, float>();
  auto b = op.template get_right_input_cooperative_tensor<half, half, float>();
  auto c = op.template get_destination_cooperative_tensor<decltype(a), decltype(b), float>();
  a[0] = half(p[0]);
  b[0] = half(p[1]);
  op.run(a, b, c);
  p[2] = c[0];
}
EOF

metal_40() {
  SDKROOT="${sdk}" xcrun metal -std=metal4.0 -mmacos-version-min=26.2 -c "$1" -o /dev/null
}

if ! command -v xcrun > /dev/null || ! metal_40 "${workdir}/language.metal" 2> /dev/null; then
  echo "SDK ${version}: headers are as expected; no Metal 4 compiler here to build with them"
  exit 0
fi

if [[ "${expected}" == "true" ]]; then
  metal_40 "${workdir}/accessors.metal"
elif metal_40 "${workdir}/accessors.metal" 2> /dev/null; then
  echo "SDK ${version}: expected the MetalPerformancePrimitives probe not to compile"
  exit 1
fi
echo "SDK ${version}: headers and the Metal 4 compiler behave as expected"
