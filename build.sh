#!/bin/bash

LINKER="lld"
DIR=$(readlink -f .)
MAIN=$(readlink -f ${DIR}/..)
CLANG=$MAIN/prebuilts/clang
KERNEL_DIR=$(pwd)
ZIMAGE_DIR="$KERNEL_DIR/out/arch/arm64/boot"

export PATH="$CLANG/bin:$PATH"
export ARCH=arm64
export SUBARCH=arm64
export KBUILD_COMPILER_STRING="$($CLANG/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
purple='\033[0;35m'
cyan='\033[0;36m'
nocol='\033[0m'

device="" # 'alioth' or 'apollo'
clean=0   # Default value for clean

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --device=*)  # Handle the --device argument with '='
            device="${1#--device=}"
            shift
            ;;
        --clean) # Handle the --clean flag
            clean=1
            shift
            ;;
        *) # Handle unknown arguments
            echo -e "Unknown option: $1"
            exit 1
            ;;
    esac
done

# If device is empty, prompt the user for input
if [[ -z "$device" ]]; then
    read -p "Enter your device (alioth/apollo): " device
fi

# Validate user device input
if [[ ! "$device" =~ ^(alioth|apollo)$ ]]; then
    echo -e "Invalid device: $device"
    echo -e "Valid devices: alioth, apollo"
    exit 1
fi

# Check if Clang directory exists
if ! [ -f "$CLANG/bin/clang" ]; then
    echo -e "$red-> Clang compiler not found!$nocol"
    echo -e "-> Downloading WeebX Clang..."
    wget -q --show-progress "$(curl -s https://raw.githubusercontent.com/XSans0/WeebX-Clang/refs/heads/main/main/link.txt)" -O "weebx-clang.tar.gz"
    rm -rf "$CLANG"
    mkdir -p "$CLANG"
    tar -xvf weebx-clang.tar.gz -C "$CLANG"
    rm -rf weebx-clang.tar.gz
    echo -e "$green-> Clang downloaded successfully!$nocol"
fi

echo -e "$blue***********************************************"
echo -e " COMPILING DELTA KERNEL              "
echo -e " Device: $device"
echo -e " Compiler: $KBUILD_COMPILER_STRING"
echo -e "***********************************************$nocol"

# Device specific configs
if [ "$device" = "alioth" ]; then
  KERNEL_DEFCONFIG=alioth_defconfig
  DEVICE_NAME1="alioth"
  DEVICE_NAME2="aliothin"
  IS_SLOT_DEVICE=1
  VENDOR_BOOT_LINES_REMOVED=0
else
  KERNEL_DEFCONFIG=apollo_defconfig
  DEVICE_NAME1="apollo"
  DEVICE_NAME2="apollon"
  IS_SLOT_DEVICE=0
  VENDOR_BOOT_LINES_REMOVED=1
fi

CONFIG_FILE=arch/arm64/configs/$KERNEL_DEFCONFIG
BUILD_VERSION=$(cat anykernel/version)
sed -i "s|^CONFIG_LOCALVERSION=.*|CONFIG_LOCALVERSION=\"//Delta_$BUILD_VERSION\"|" $CONFIG_FILE

START_TIME=$(date +"%s")
ANYKERNEL_SH=anykernel/anykernel.sh

# Backup anykernel.sh
cp -p $ANYKERNEL_SH $ANYKERNEL_SH.bak

# Modify anykernel.sh based on device and is_slot_device
sed -i "s/device.name1=.*/device.name1=$DEVICE_NAME1/" $ANYKERNEL_SH
sed -i "s/device.name2=.*/device.name2=$DEVICE_NAME2/" $ANYKERNEL_SH
sed -i "s/is_slot_device=.*/is_slot_device=$IS_SLOT_DEVICE;/" $ANYKERNEL_SH

# Remove vendor_boot block if necessary
if [ "$VENDOR_BOOT_LINES_REMOVED" -eq 1 ]; then
  sed -i '/## vendor_boot shell variables/,/## end vendor_boot install/d' $ANYKERNEL_SH
fi

# Compile Kernel
if [ -d "out" ] && [ "$clean" -eq 1 ]; then
  echo -e "$cyan-> Cleaning out directory...$nocol"
  rm -rf out
fi
mkdir -p out

# Speed up build process
MAKE="./makeparallel"

make $KERNEL_DEFCONFIG O=out CC=clang
make -j$(nproc --all) O=out \
  CC=clang \
  ARCH=arm64 \
  CROSS_COMPILE=aarch64-linux-gnu- \
  NM=llvm-nm \
  OBJDUMP=llvm-objdump \
  STRIP=llvm-strip

echo -e "$green\n-> Completed kernel compilation!$nocol"

# Copy built kernel to anykernel flashable zip
echo -e "$cyan\n-> Generating flashable zip...$nocol"
if [ -f "$ZIMAGE_DIR/Image.gz" ] && [ -f "$ZIMAGE_DIR/dtbo.img" ] && [ -f "$ZIMAGE_DIR/dtb" ]; then
mkdir -p tmp
cp -fp $ZIMAGE_DIR/Image.gz tmp
cp -fp $ZIMAGE_DIR/dtbo.img tmp
cp -fp $ZIMAGE_DIR/dtb tmp
cp -rp ./anykernel/* tmp
cd tmp
7zz a -mx9 tmp.zip *
cd ..
for file in delta-kernel-*.zip; do
  if [ -f "$file" ]; then
    rm "$file"
  fi
done
TIMESTAMP="$(date "+%Y%m%d-%H%M%S")"
BUILD_FILENAME="delta-kernel-$device-$BUILD_VERSION.zip"
cp -fp tmp/tmp.zip $BUILD_FILENAME

if [ -f "$BUILD_FILENAME" ]; then
  echo -e "$green\n-> Delta Kernel $BUILD_VERSION Build Successful!$nocol"
fi

END_TIME=$(date +"%s")
ELAPSED_TIME=$(($END_TIME - $START_TIME))
ELAPSED_HOURS=$((ELAPSED_TIME / 3600))
ELAPSED_MINUTES=$((ELAPSED_TIME % 3600 / 60))
ELAPSED_SECONDS=$((ELAPSED_TIME % 60))

echo -e "Elapsed: $ELAPSED_HOURS hours, $ELAPSED_MINUTES minutes, and $ELAPSED_SECONDS seconds."

else
  echo -e "$red\nERROR: Compilation failed!$nocol"
fi

# Cleanup
rm -rf tmp
# Restore anykernel.sh
mv -f anykernel/anykernel.sh.bak anykernel/anykernel.sh
