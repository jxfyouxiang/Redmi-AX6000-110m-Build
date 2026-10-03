#!/bin/bash
#
# 小米 AX3000T —— 把 yuzhii/hanwckf MTK U-Boot 的 "immortalwrt-112m" 大分区布局
# 移植到 ImmortalWrt 官方源码（openwrt-24.10，开源 mt76 驱动）。
#
# 在 openwrt 源码根目录执行： ./customize_ax3000t_112m.sh
#
# 为什么可行：
#   yuzhii U-Boot 的启动流程只有三步 —— attach UBI -> 读名为 kernel 的卷 -> bootm。
#   它完全不关心内核里用的是闭源 mt_wifi 还是开源 mt76。
#   237 那个大分区镜像的第一个字节就是 "UBI#"，且文件大小正好是 128K 的整数倍，
#   没有任何厂商私有头或签名尾部 —— 说明它就是一个裸 UBI 镜像。
#   而 237 的机型定义里也没有一行驱动相关的配置，纯布局。
#
set -e

DTS_NAME=mt7981b-xiaomi-mi-router-ax3000t-mtkuboot
DTS_DIR=target/linux/mediatek/dts
FLOGIC=target/linux/mediatek/image/filogic.mk

if [ ! -f "$FLOGIC" ]; then
	echo "错误：找不到 $FLOGIC"
	echo "      请在 OpenWrt/ImmortalWrt 源码根目录执行本脚本。"
	exit 1
fi

# ---------------------------------------------------------------------------
# 步骤 1/3：新增 112M 大分区布局的 DTS
#
# 内容与 padavanonly/immortalwrt-mt798x-6.6 分支 openwrt-24.10-6.6 的
# target/linux/mediatek/dts/mt7981b-xiaomi-mi-router-ax3000t-mtkuboot.dts 一致。
# 它只做三件事：改 model/compatible、开 NMBM、把 ubi 分区改成 6M 起的 112 MiB。
# 注意里面没有任何 WiFi 驱动的痕迹 —— 与官方树共用同一个 .dtsi。
# ---------------------------------------------------------------------------
# 如果官方树未来新增了同名文件，先备份，避免覆盖
if [ -f "$DTS_DIR/$DTS_NAME.dts" ]; then
	cp "$DTS_DIR/$DTS_NAME.dts" "$DTS_DIR/$DTS_NAME.dts.orig.$$"
	echo "提示：$DTS_NAME.dts 已存在，原文件备份为 $DTS_NAME.dts.orig.$$"
fi

cat > "$DTS_DIR/$DTS_NAME.dts" <<'DTS_EOF'
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT
//
// Xiaomi Mi Router AX3000T —— yuzhii / hanwckf MTK U-Boot，immortalwrt-112m 大分区布局
//
// ubi 分区：起始 0x600000 (6 MiB)，大小 0x7000000 (112 MiB)，即布局名里的 "112m"。
// 与 stock 布局的关系：stock 把 ubi_kernel(0x600000+0x2200000) 和
// ubi(0x2800000+0x4e00000) 分成两块，终点都是 0x7600000；
// 这里把两块合并成一个连续的 112 MiB 分区。

/dts-v1/;
#include "mt7981b-xiaomi-mi-router-ax3000t.dtsi"

/ {
	model = "Xiaomi Mi Router AX3000T (MTK U-Boot layout)";
	compatible = "xiaomi,mi-router-ax3000t-mtkuboot", "mediatek,mt7981";
};

&spi_nand {
	mediatek,nmbm;
	mediatek,bmt-max-ratio = <1>;
	mediatek,bmt-max-reserved-blocks = <64>;
	mediatek,bmt-mtd-overridden-oobsize = <64>;
};

&partitions {
	partition@600000 {
		label = "ubi";
		reg = <0x600000 0x7000000>;
	};
};
DTS_EOF
echo "[1/3] 已写入 $DTS_DIR/$DTS_NAME.dts"

# ---------------------------------------------------------------------------
# 步骤 2/3：在 filogic.mk 里注册机型
#
# 移植自 237 的 Device/xiaomi_mi-router-ax3000t-mtkuboot，
# 唯一改动是补上 DEVICE_PACKAGES（237 靠 target 默认值选驱动，官方树需要显式写）。
#
# 【机型名不要改】OpenWrt 会用机型名推出 SUPPORTED_DEVICES：
#   xiaomi_mi-router-ax3000t-mtkuboot  ->  xiaomi,mi-router-ax3000t-mtkuboot
# 正好等于 DTS 的 compatible。改了名字会导致 sysupgrade 拒绝刷机。
#
# 【IMAGE_SIZE := 114688k】114688 KiB = 112 MiB，与 DTS 的 ubi 分区对齐。
# ---------------------------------------------------------------------------
if grep -q "Device/xiaomi_mi-router-ax3000t-mtkuboot" "$FLOGIC"; then
	echo "[2/3] 机型定义已存在，跳过"
else
	cat > /tmp/112m-device.$$.mk <<'MK_EOF'

# ---- AX3000T 112M 大分区（yuzhii/hanwckf MTK U-Boot）+ 开源 mt76 ----
# 移植自 padavanonly/immortalwrt-mt798x-6.6，只补了 DEVICE_PACKAGES。
# 这个机型定义里没有任何闭源驱动依赖，纯布局 + mt76。
define Device/xiaomi_mi-router-ax3000t-mtkuboot
  DEVICE_VENDOR := Xiaomi
  DEVICE_MODEL := Mi Router AX3000T
  DEVICE_VARIANT := (MTK U-Boot 112M layout)
  DEVICE_DTS := mt7981b-xiaomi-mi-router-ax3000t-mtkuboot
  DEVICE_DTS_DIR := ../dts
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware
  IMAGE_SIZE := 114688k
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += xiaomi_mi-router-ax3000t-mtkuboot
MK_EOF

	# 插在 stock 机型的注册行之后，保证位置稳定（不要盲插文件末尾）
	awk 'NR==FNR { d = d $0 "\n"; next }
	     { print }
	     /^TARGET_DEVICES \+= xiaomi_mi-router-ax3000t$/ { printf "%s", d }' \
		"/tmp/112m-device.$$.mk" "$FLOGIC" > "$FLOGIC.new.$$"
	mv "$FLOGIC.new.$$" "$FLOGIC"
	rm -f "/tmp/112m-device.$$.mk"
	echo "[2/3] 已在 filogic.mk 中插入机型定义"
fi

# ---------------------------------------------------------------------------
# 步骤 3/3：自检 —— 任何一项不过就中止，避免编出一个刷不进去的固件
# ---------------------------------------------------------------------------
fail() { echo "自检失败：$1"; exit 1; }

grep -q "define Device/xiaomi_mi-router-ax3000t-mtkuboot" "$FLOGIC" \
	|| fail "filogic.mk 中没有机型定义"
grep -q "^TARGET_DEVICES += xiaomi_mi-router-ax3000t-mtkuboot" "$FLOGIC" \
	|| fail "机型未注册到 TARGET_DEVICES"
grep -q '0x600000 0x7000000' "$DTS_DIR/$DTS_NAME.dts" \
	|| fail "DTS 里 ubi 分区不是 0x600000 起、112 MiB"
grep -q 'xiaomi,mi-router-ax3000t-mtkuboot' "$DTS_DIR/$DTS_NAME.dts" \
	|| fail "DTS 里 compatible 不对（sysupgrade 会拒绝刷机）"
grep -q 'IMAGE_SIZE := 114688k' "$FLOGIC" \
	|| fail "IMAGE_SIZE 不是 112 MiB"
grep -q 'kmod-mt7915e' "$FLOGIC" \
	|| fail "没有选中开源 mt76 驱动"
grep -q 'mediatek,nmbm' "$DTS_DIR/$DTS_NAME.dts" \
	|| fail "DTS 里没有开 NMBM（NAND 坏块管理，必须要有）"

if grep -q 'kmod-mt_wifi' "$FLOGIC"; then
	echo "警告：filogic.mk 里出现了 kmod-mt_wifi，请人工确认"
fi

echo "[3/3] 自检通过：112M 大分区布局 + 开源 mt76 已就位"
echo "      下一步： make defconfig && make -j\$(nproc)"
