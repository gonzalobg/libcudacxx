# Dockerfile for libcudacxx_base:host_x86_64_centos_7.6.1810__target_x86_64_centos_7.6.1810__gcc_4.8

FROM centos:7.6.1810

MAINTAINER Bryce Adelstein Lelbach <blelbach@nvidia.com>

ARG LIBCUDACXX_SKIP_BASE_TESTS_BUILD
ARG LIBCUDACXX_COMPUTE_ARCHS
ARG LIBCXX_TEST_STANDARD_VER

###############################################################################
# BUILD: The following is invoked when the image is built.

RUN yum -y --enablerepo=extras install epel-release\
 && yum -y updateinfo\
 && yum -y install which make gcc-c++ libstdc++-static llvm-devel clang python python-pip\
 && pip install lit\
 && mkdir -p /sw/gpgpu/libcudacxx/build\
 && mkdir -p /sw/gpgpu/libcudacxx/libcxx/build

# The distro doesn't have CMake 3.8 in its repositories, so we need to install
# it ourselves.
ADD https://github.com/Kitware/CMake/releases/download/v3.8.2/cmake-3.8.2-Linux-x86_64.sh /tmp/cmake.sh
RUN sh /tmp/cmake.sh --skip-license --prefix=/usr

# For debugging.
#RUN yum -y install gdb strace vim

# We use ADD here because it invalidates the cache for subsequent steps, which
# is what we want, as we need to rebuild if the sources have changed.

# Copy NVCC and the CUDA runtime from the source tree.
ADD bin /sw/gpgpu/bin

# Copy the core CUDA headers from the source tree.
ADD cuda/import/*.h* /sw/gpgpu/cuda/import/
ADD cuda/common/*.h* /sw/gpgpu/cuda/common/
ADD cuda/tools/cudart/*.h* /sw/gpgpu/cuda/tools/cudart/
ADD cuda/tools/cudart/nvfunctional /sw/gpgpu/cuda/tools/cudart/
ADD cuda/tools/cnprt/*.h* /sw/gpgpu/cuda/tools/cnprt/
ADD cuda/tools/cooperative_groups/*.h* /sw/gpgpu/cuda/tools/cooperative_groups/
ADD cuda/tools/cudart/cudart_etbl/*.h* /sw/gpgpu/cuda/tools/cudart/cudart_etbl/
ADD opencl/import/cl_rel/CL/*.h* /sw/gpgpu/opencl/import/cl_rel/CL/

# Copy libcu++ sources from the source tree.
ADD libcudacxx /sw/gpgpu/libcudacxx

# Build libc++ and configure libc++ tests.
RUN set -o pipefail; cd /sw/gpgpu/libcudacxx/libcxx/build\
 && cmake ..\
 -DLIBCXX_INCLUDE_TESTS=ON\
 -DLIBCXX_INCLUDE_BENCHMARKS=OFF\
 -DLIBCXX_CXX_ABI=libsupc++\
 -DLIBCXX_TEST_STANDARD_VER=$LIBCXX_TEST_STANDARD_VER\
 -DLIBCXX_ABI_UNSTABLE=ON\
 -DLLVM_CONFIG_PATH=$(which llvm-config)\
 -DCMAKE_C_COMPILER=gcc\
 -DCMAKE_CXX_COMPILER=g++\
 && make -j\
 2>&1 | tee /sw/gpgpu/libcudacxx/libcxx/build/libcxx_cmake.log

# Configure libcu++ tests.
RUN set -o pipefail; cd /sw/gpgpu/libcudacxx/build\
 && cmake ..\
 -DLIBCXX_TEST_STANDARD_VER=$LIBCXX_TEST_STANDARD_VER\
 -DLLVM_CONFIG_PATH=$(which llvm-config)\
 -DCMAKE_CXX_COMPILER=/sw/gpgpu/bin/x86_64_Linux_release/nvcc\
 -DLIBCXX_NVCC_HOST_COMPILER=g++\
 2>&1 | tee /sw/gpgpu/libcudacxx/build/libcudacxx_cmake.log

# Build tests if requested.
# NOTE: libc++ tests are disabled until we can setup libc++abi.
RUN cd /sw/gpgpu/libcudacxx\
 && LIBCUDACXX_COMPUTE_ARCHS=$LIBCUDACXX_COMPUTE_ARCHS\
 LIBCUDACXX_SKIP_BASE_TESTS_BUILD=$LIBCUDACXX_SKIP_BASE_TESTS_BUILD\
 /sw/gpgpu/libcudacxx/utils/nvidia/linux/perform_tests.bash\
 --skip-tests-runs\
 --skip-libcxx-tests\
 --libcxx-log /sw/gpgpu/libcudacxx/libcxx/build/libcxx_lit.log\
 --libcudacxx-log /sw/gpgpu/libcudacxx/build/libcudacxx_lit.log

# Build tests for sm6x and up if requested.
RUN cd /sw/gpgpu/libcudacxx\
 && LIBCUDACXX_COMPUTE_ARCHS="60 61 62 70 72 75"\
 LIBCUDACXX_SKIP_BASE_TESTS_BUILD=$LIBCUDACXX_SKIP_BASE_TESTS_BUILD\
 /sw/gpgpu/libcudacxx/utils/nvidia/linux/perform_tests.bash\
 --skip-tests-runs\
 --skip-libcxx-tests\
 --libcxx-log /sw/gpgpu/libcudacxx/libcxx/build/libcxx_lit_sm6x_plus.log\
 --libcudacxx-log /sw/gpgpu/libcudacxx/build/libcudacxx_lit_sm6x_plus.log

WORKDIR /sw/gpgpu/libcudacxx
