#!/bin/bash
set -e

JOBS=$(nproc)

while getopts "j:h" opt; do
  case $opt in
    j) JOBS="$OPTARG" ;;
    h)
      echo "Uso: ./build.sh [-jN]"
      echo "  Sin argumentos : Usa todos los hilos ($(nproc))"
      echo "  -jN            : Hilos a usar (ej. -j3)"
      exit 0
      ;;
    *) exit 1 ;;
  esac
done

export CCACHE_DIR="$HOME/.ccache_ctwo"
export CCACHE_COMPRESS=1
export USE_CCACHE=1

echo ">>> Limpiando compilación previa..."
rm -rf out
mkdir -p out

MAKE_ARGS=(
  -j"$JOBS"
  O=out
  ARCH=arm64
  LLVM=1
  LLVM_IAS=1
  CC="ccache clang"
  KCFLAGS=-D_ANDROID_COMMON_KERNEL_
)

echo ">>> Configurando ctwo_defconfig..."
make "${MAKE_ARGS[@]}" ctwo_defconfig

echo ">>> Compilando Image y módulos del kernel con -j$JOBS..."
make "${MAKE_ARGS[@]}" Image modules

echo ">>> Compilando módulos WLAN (CNSS + qca_cld3_kiwi_v2)..."
WLAN_PLATFORM="vendor/qcom/opensource/wlan/platform"
WLAN_DRIVER="vendor/qcom/opensource/wlan/qcacld-3.0"

make "${MAKE_ARGS[@]}" M="$WLAN_PLATFORM" \
  WLAN_PLATFORM_ROOT="$(pwd)/$WLAN_PLATFORM" \
  CONFIG_CNSS_OUT_OF_TREE=y CONFIG_CNSS2=m CONFIG_CNSS2_QMI=y \
  CONFIG_CNSS_QMI_SVC=m CONFIG_CNSS_PLAT_IPC_QMI_SVC=m \
  CONFIG_CNSS_UTILS=m CONFIG_CNSS_GENL=m CONFIG_WCNSS_MEM_PRE_ALLOC=m \
  CONFIG_BUS_AUTO_SUSPEND=y CONFIG_CNSS_HW_SECURE_DISABLE=y \
  CONFIG_CNSS_HW_SECURE_SMEM=y CONFIG_CNSS2_SSR_DRIVER_DUMP=y \
  CONFIG_CNSS2_SMMU_DB_SUPPORT=y modules

make "${MAKE_ARGS[@]}" M="$WLAN_DRIVER" \
  WLAN_ROOT="$(pwd)/$WLAN_DRIVER" \
  WLAN_FW_API="$(pwd)/vendor/qcom/opensource/wlan/fw-api" \
  WLAN_PLATFORM_INC="$(pwd)/$WLAN_PLATFORM/inc" \
  WLAN_PROFILE=pineapple_gki_kiwi-v2 \
  KBUILD_EXTRA_SYMBOLS="$(pwd)/out/$WLAN_PLATFORM/Module.symvers" \
  MODNAME=qca_cld3_kiwi_v2 DEVNAME=kiwi_v2 DYNAMIC_SINGLE_CHIP=kiwi_v2 \
  BOARD_PLATFORM=pineapple CONFIG_QCA_CLD_WLAN=m \
  CONFIG_QCA_WIFI_ISOC=0 CONFIG_QCA_WIFI_2_0=1 \
  CONFIG_CNSS2=m CONFIG_CNSS2_MODULE=y CONFIG_CNSS_OUT_OF_TREE=y modules

echo ">>> Compilando módulos externos de Motorola/Qualcomm (pantalla, táctil, huella, etc.)..."
make -f scripts/ctwo-external-modules.mk -j"$JOBS" KERNEL_OUT="$(pwd)/out" LLVM=1

echo ">>> ¡Compilación stock completada con éxito!"
echo ">>> Image generado en: out/arch/arm64/boot/Image"
