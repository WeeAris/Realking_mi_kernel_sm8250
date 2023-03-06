#!/usr/bin/env bash
# shellcheck disable=SC2199
# shellcheck source=/dev/null
#
# Copyright (C) 2020-22 UtsavBalar1231 <utsavbalar1231@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -

KBUILD_COMPILER_STRING=$($HOME/tc/clang/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')
KBUILD_LINKER_STRING=$($HOME/tc/clang/bin/ld.lld --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//' | sed 's/(compatible with [^)]*)//')
export KBUILD_COMPILER_STRING
export KBUILD_LINKER_STRING

#
# Enviromental Variables
#

DATE=$(date '+%Y%m%d-%H%M')
DEVICE="$1"

# Set our directory
OUT_DIR=out/

if [[ "$2" == "aosp" ]]; then
	VERSION="MiNaZuKi-${DEVICE^^}-AOSP-${DATE}"
fi

if [[ "$2" == "aospa" ]]; then
	VERSION="MiNaZuKi-${DEVICE^^}-AOSPA-${DATE}"
fi

if [[ $2 == "" || $2 == "miui" ]]; then
    VERSION="MiNaZuKi-${DEVICE^^}-MIUI-${DATE}"
fi

# Export Zip name
export ZIPNAME="${VERSION}.zip"

# How much kebabs we need? Kanged from @raphielscape :)
if [[ -z "${KEBABS}" ]]; then
    COUNT="$(grep -c '^processor' /proc/cpuinfo)"
    export KEBABS="$((COUNT + 2))"
fi

echo "Jobs: ${KEBABS}"

ARGS="ARCH=arm64 \
O=${OUT_DIR} \
LLVM=1 \
CLANG_TRIPLE=aarch64-linux-gnu- \
CROSS_COMPILE=aarch64-linux-gnu- \
CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
-j${KEBABS}"

dts_source=arch/arm64/boot/dts/vendor/qcom

START=$(date +"%s")

# Set compiler Path
export PATH="$HOME/tc/clang/bin:$PATH"
export LD_LIBRARY_PATH=${HOME}/tc/clang/lib64:$LD_LIBRARY_PATH

# Make defconfig
make -j${KEBABS} ${ARGS} "${DEVICE}"_defconfig

if [[ "$2" == "aosp" ]]; then
	echo "------ Starting AOSP Build ------"
fi
if [[ "$2" == "aospa" ]]; then
	echo "------ Starting AOSPA Build ------"
fi

if [[ $2 == "" || $2 == "miui" ]]; then
	echo "------ Starting MIUI Build ------"
fi

# Make defconfig
make -j${KEBABS} ${ARGS} "${DEVICE}"_defconfig

if [[ "$2" =~ "aosp"* ]]; then
scripts/config --file out/.config	\
    -e LOCALVERSION_AUTO	\
    -e TOUCHSCREEN_COMMON	\
    --set-str STATIC_USERMODEHELPER_PATH /system/bin/micd	\
    -d IPC_LOGGING	\
    -d MIGT	\
    -d MIHW	\
    -d MILLET	\
    -d MIGT_ENERGY_MODEL	\
    -d MIUI_ZRAM_MEMORY_TRACKING	\
    -d PACKAGE_RUNTIME_INFO	\
    -d PERF_HUMANTASK	\
    -d PERF_CRITICAL_RT_TASK	\
    -d PERF_HELPER	\
    -d RTMM	\
    -d MI_FRAGMENTION	\
    -d SF_BINDER	\
    -d TASK_DELAY_ACCT

    if [[ "$2" == "aospa" ]]; then
	scripts/config --file out/.config	\
	-d SDCARD_FS	\
	-e UNICODE
	sed -i "/FORTIFY_SOURCE/d" out/.config
    fi

    sed -i 's/<1546>/<155>/g' ${dts_source}/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
    sed -i 's/<695>/<70>/g' ${dts_source}/dsi-panel-l11r-38-08-0a-dsc-cmd.dtsi
fi

# Make olddefconfig
cd ${OUT_DIR} || exit
make -j${KEBABS} ${ARGS} CC="ccache clang" HOSTCC="ccache gcc" HOSTCXX="cache g++" olddefconfig
cd ../ || exit

make -j${KEBABS} ${ARGS} CC="ccache clang" HOSTCC="ccache gcc" HOSTCXX="ccache g++" 2>&1 | tee build.log

if [[ "$2" =~ "aosp"* ]]; then
	git checkout arch/arm64/boot/dts/vendor &>/dev/null
fi

if [[ "$2" =~ "aosp"* ]]; then
	if [[ "$2" == "aospa" ]]; then
		echo "------ Finishing AOSPA Build ------"
	else
		echo "------ Finishing AOSP Build ------"
	fi
fi

if [[ "$2" == "" || "$2" == "miui" ]]; then
	echo "------ Finishing MIUI Build ------"
fi

#remove KSU from source after compiling
git checkout drivers/Makefile &>/dev/null
rm -rf KernelSU
rm -rf drivers/kernelsu

find out/${dts_source} -name '*.dtb' -exec cat {} + >out/arch/arm64/boot/dtb

END=$(date +"%s")
DIFF=$((END - START))
zipname="$VERSION.zip"
if [ -f "out/arch/arm64/boot/Image" ] && [ -f "out/arch/arm64/boot/dtbo.img" ] && [ -f "out/arch/arm64/boot/dtb" ]; then
	git clone -q https://github.com/amackpro/AnyKernel3 -b $1
	cp out/arch/arm64/boot/Image AnyKernel3
	cp out/arch/arm64/boot/dtb AnyKernel3
	cp out/arch/arm64/boot/dtbo.img AnyKernel3
	rm -f *zip
	cd AnyKernel3
	sed -i "s/is_slot_device=0/is_slot_device=auto/g" anykernel.sh
	zip -r9 "../${zipname}" * -x '*.git*' README.md *placeholder >> /dev/null
	cd ..
	rm -rf AnyKernel3
	echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
	echo ""
	echo -e ${zipname} " is ready!"
	echo ""
else
	echo -e "\n Compilation Failed!"
fi
