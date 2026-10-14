#!/bin/bash
# =============================================================================
# 小米 AX3000T · 112M 大分区补丁（yuzhii / hanwckf MTK U-Boot 布局 + 开源 mt76）
# 目标版本：ImmortalWrt v25.12.2（内核 6.12.103）
#
# 这份脚本就是工作流 immortalwrt_ax3000t_112m_25.12.2.yml 里
# 「应用 AX3000T 112M 大分区补丁」那一步执行的同一份代码（单一来源，避免两边漂移），
# 本地相对云端多两点适配：
#   ① 幂等：重复执行不会把设备定义追加第二遍、不会重写 DTS
#   ② 路径：源码树由 $OPENWRT_DIR 决定（云端跑在 /builder/openwrt，脚本靠 working-directory 定位）
#
# 用法：  ./112m-patch.sh                            # 默认 ~/openwrt25
#         OPENWRT_DIR=~/openwrt25 ./112m-patch.sh
#
# ── 改这个脚本之前必须先理解的三个事实 ────────────────────────────────────────
# 1) 机型名 `xiaomi_mi-router-ax3000t-mtkuboot` 不要改。
#    OpenWrt 用机型名推出 SUPPORTED_DEVICES = xiaomi,mi-router-ax3000t-mtkuboot，
#    它正好等于 DTS 的 compatible，也正好等于用户这台机器**现在正在跑的** 24.10 固件的
#    board_name ⇒ 三者一致，LuCI「更新固件」/ sysupgrade 才会接受，配置才会保留。
#    改了名字 = 刷机时被拒绝（或必须走 U-Boot 重刷、配置全丢）。
# 2) ubi 分区固定从 0x600000 起、大小 0x7000000（112 MiB），终点 0x7600000 正好是
#    common dtsi 里 KF 分区的起点（mt7981b-xiaomi-mi-router-common.dtsi:390）⇒ 不越界。
#    这段偏移与上游 ubootmod 机型**完全相同**，只是启动方案不同（见第 3 点）。
# 3) 必须 KERNEL_IN_UBI=1 + `IMAGE/factory.bin := append-ubi`：
#    yuzhii / hanwckf 的 MTK U-Boot 是「挂载 UBI → 读名为 kernel 的卷 → bootm」，
#    它不认识上游 OpenWrt U-Boot 的 .itb / FIT 方案（IMAGES := sysupgrade.itb）。
#    两者共用同一段 flash 偏移，但产物格式不通用 —— 刷错格式会进不了系统。
# =============================================================================
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$KIT_DIR/config.env" ]; then
  # shellcheck disable=SC1091
  source "$KIT_DIR/config.env"
fi
OW="${OPENWRT_DIR:-$HOME/openwrt25}"

# 源码树判据与 build-local.sh 保持一致：不看 .git（源码包解出来的树本来就没有 .git）
[ -f "$OW/rules.mk" ] && [ -f "$OW/feeds.conf.default" ] \
  || { echo "❌ 源码树不存在或不像 ImmortalWrt 树：$OW"; exit 1; }

cd "$OW"
echo "== 源码树 =="
echo "  路径   : $OW"
if [ -d .git ]; then
  echo "  commit : $(git rev-parse HEAD 2>/dev/null || echo '?')"
else
  echo "  来源   : 源码包（无 .git）"
  grep -m1 -E '^src-git packages ' feeds.conf.default | sed 's/^/  指纹   : /'
  grep -m1 -E 'LINUX_VERSION-' target/linux/generic/kernel-6.12 2>/dev/null | sed 's/^/  指纹   : /'
fi
echo

# ---------------------------------------------------------------------------
# 0. 前置断言：112M 布局的两端都必须还成立
#    · 起点：上游 ubootmod 的 ubi 仍是 0x600000 + 0x7000000（我们与它同偏移）
#    · 终点：common dtsi 里 KF 分区仍从 0x7600000 开始（= 我们 ubi 的结束地址）
#    上游一改 flash 布局，这里必须先失败 —— 硬套会写到 KF 分区上（变砖）。
# ---------------------------------------------------------------------------
DTSI=target/linux/mediatek/dts/mt7981b-xiaomi-mi-router-common.dtsi
UBOOTMOD_DTS=target/linux/mediatek/dts/mt7981b-xiaomi-mi-router-ax3000t-ubootmod.dts
STOCK_DTS=target/linux/mediatek/dts/mt7981b-xiaomi-mi-router-ax3000t.dts
for f in "$DTSI" "$UBOOTMOD_DTS" "$STOCK_DTS"; do
  [ -f "$f" ] || { echo "❌ 找不到 $f（上游目录结构或机型名变了？）"; exit 1; }
done

grep -q '0x600000 0x7000000' "$UBOOTMOD_DTS" || {
  echo "❌ 上游 ubootmod 的 ubi 不再是 0x600000 + 0x7000000，112M 布局的起点假设已失效，"
  echo "   必须重新核对分区表后再刷机（硬套会变砖）"
  exit 1
}
grep -q '0x7600000 0x40000' "$DTSI" || {
  echo "❌ $DTSI 里 KF 分区不再是 0x7600000 + 0x40000，112M 布局的终点假设已失效"
  exit 1
}
grep -q '0x600000 0x2200000' "$STOCK_DTS" && grep -q '0x2800000 0x4e00000' "$STOCK_DTS" || {
  echo "❌ 上游 stock 的 ubi_kernel/ubi 分段变了（原来 0x600000+0x2200000 / 0x2800000+0x4e00000，"
  echo "   合并后终点 0x7600000）。112M 是把这两段合并，分段一变就必须重算"
  exit 1
}
echo "✅ 前置断言通过：ubi 0x600000+0x7000000，两端（起点=上游 ubootmod、终点=KF 分区）都成立"

# ---------------------------------------------------------------------------
# 1. 新建 112M 布局的设备树（幂等）
#    include 官方 .dtsi，只覆盖三件事：model/compatible、NMBM、ubi 分区。
#    NMBM（NAND 坏块管理）必须开 —— 官方 stock/ubootmod 两种 DTS 都开着它。
# ---------------------------------------------------------------------------
DTS=target/linux/mediatek/dts/mt7981b-xiaomi-mi-router-ax3000t-mtkuboot.dts
if [ -f "$DTS" ]; then
  echo "⏭  $DTS 已存在，跳过创建"
else
  cat << 'EOF' > "$DTS"
// SPDX-License-Identifier: GPL-2.0-or-later OR MIT
//
// Xiaomi Mi Router AX3000T —— yuzhii / hanwckf MTK U-Boot，immortalwrt-112m 大分区布局
//
// ubi 分区：起始 0x600000 (6 MiB)，大小 0x7000000 (112 MiB)，即布局名里的 "112m"。
// 与 stock 布局的关系：stock 把 ubi_kernel(0x600000+0x2200000) 和
// ubi(0x2800000+0x4e00000) 分成两块，终点都是 0x7600000；
// 这里把两块合并成一个连续的 112 MiB 分区。
//
// 【不要改 compatible】它等于机型名推出的 SUPPORTED_DEVICES，
// 也等于这台机器现在跑着的 24.10 固件的 /tmp/sysinfo/board_name。

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
EOF
  echo "✅ 已创建 $DTS"
fi

# ---------------------------------------------------------------------------
# 2. 在 filogic.mk 里注册机型（幂等）
#    插在 stock 机型注册行之后（位置稳定，不盲插文件末尾）。
#    上游结构一变，awk 会「什么都不插」却不报错 ⇒ 所以锚点必须先断言。
# ---------------------------------------------------------------------------
MK=target/linux/mediatek/image/filogic.mk
[ -f "$MK" ] || { echo "❌ 找不到 $MK"; exit 1; }
if grep -q 'Device/xiaomi_mi-router-ax3000t-mtkuboot' "$MK"; then
  echo "⏭  filogic.mk 里已经有 112M 机型定义，跳过插入"
else
  if ! grep -q '^TARGET_DEVICES += xiaomi_mi-router-ax3000t$' "$MK"; then
    echo "❌ $MK 里找不到锚点行 'TARGET_DEVICES += xiaomi_mi-router-ax3000t'"
    echo "   上游源码结构可能变了，请人工确认后再改本脚本。"
    exit 1
  fi
  cat > /tmp/112m-device.$$.mk <<'MK_EOF'

# ---- AX3000T 112M 大分区（yuzhii/hanwckf MTK U-Boot）+ 开源 mt76 ----
# 移植自 padavanonly/immortalwrt-mt798x-6.6 的 -mtkuboot 机型，只补了 DEVICE_PACKAGES
# （237 靠 target 默认值选驱动，官方树需要显式写）。机型定义里没有任何闭源驱动依赖。
#   · IMAGE_SIZE := 114688k = 112 MiB，与 DTS 的 ubi 分区对齐
#   · KERNEL_IN_UBI := 1 ⇒ 产出 U-Boot 要读的 kernel 卷
#   · factory.bin := append-ubi ⇒ 整份 UBI 镜像，从 U-Boot WebUI 刷
#   · sysupgrade.bin := sysupgrade-tar | append-metadata ⇒ 系统内 LuCI/ssh 就地升级
# 机型名推出 SUPPORTED_DEVICES = xiaomi,mi-router-ax3000t-mtkuboot，不要改。
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
  IMAGES := factory.bin sysupgrade.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += xiaomi_mi-router-ax3000t-mtkuboot
MK_EOF

  # 原地截断写回（不能用 mv：mv 会把新文件 umask 权限盖到上游文件上。
  # filogic.mk 不执行，但这条习惯来自 gen_netgear_rootfs_node.sh 那次 Error 126 的教训）
  awk 'NR==FNR { d = d $0 "\n"; next }
       { print }
       /^TARGET_DEVICES \+= xiaomi_mi-router-ax3000t$/ { printf "%s", d }' \
      "/tmp/112m-device.$$.mk" "$MK" > "$MK.new.$$"
  cat "$MK.new.$$" > "$MK"
  rm -f "$MK.new.$$" "/tmp/112m-device.$$.mk"
  echo "✅ 已在 filogic.mk 中插入 Device/xiaomi_mi-router-ax3000t-mtkuboot（IMAGE_SIZE 114688k = 112 MiB）"
fi

# ---------------------------------------------------------------------------
# 3. 上游 25.12 缺陷兜底：netgear FIT 的 rootfs 节点（否则编译必挂）
#
#    filogic.mk:13 会拼出 $(KERNEL_BUILD_DIR)/root.squashfs+pkg=$(ROOTFS_ID/$(DEVICE_NAME))，
#    而 ROOTFS_ID 只为「被选中的设备」生成（include/image.mk:610）——
#    没勾选的 netgear 设备于是拿到一个不存在的 .../root.squashfs+pkg= ，
#    脚本 stat/sha1sum 失败 → 生成的 FIT 里出现 "value = ;" →
#    mkimage 报 netgear_eax17-kernel.bin.its:50.12-13 syntax error →
#    target/linux/install 失败 → 整个 make world 挂掉。
#    （官方 release 用 TARGET_ALL_PROFILES=y 编译，所有设备都被选中，所以他们碰不到。）
#
#    兜底方式：文件不存在时换成一个空文件，让上游自己的代码继续跑，
#    输出格式分毫不变（size=0、sha1 合法），我们并不产出这些设备的镜像。
# ---------------------------------------------------------------------------
NGFIT="$OW/scripts/gen_netgear_rootfs_node.sh"
if [ ! -f "$NGFIT" ]; then
  echo "⏭  上游没有 scripts/gen_netgear_rootfs_node.sh（24.10 分支就是这样），无需兜底"
else
  if grep -q 'AX3000T-KIT: netgear-empty-rootfs-guard' "$NGFIT"; then
    echo "⏭  已打过 netgear 空 rootfs 兜底补丁，跳过"
  else
    GUARD=$(mktemp)
    cat > "$GUARD" <<'GUARD_EOF'
# AX3000T-KIT: netgear-empty-rootfs-guard
if [ ! -f "$ROOTFS_FILE" ]; then
	ROOTFS_FILE=$(mktemp)
fi
GUARD_EOF
    awk -v guard="$GUARD" '
      /^ROOTFS_FILE="\$1"$/ && !done {
        print
        while ((getline line < guard) > 0) print line
        close(guard); done = 1; next
      }
      { print }
    ' "$NGFIT" > "$NGFIT.kitnew"
    # ⚠️ 必须「原地截断写回」，不能用 mv：mv 会把新文件（umask 644）的权限盖到上游脚本上，
    #    而 filogic.mk 是直接执行这个脚本的 ⇒ 镜像阶段报
    #      bash: .../scripts/gen_netgear_rootfs_node.sh: Permission denied
    #      make[5]: *** [.../netgear_eax17-kernel.bin] Error 126
    cat "$NGFIT.kitnew" > "$NGFIT"
    rm -f "$NGFIT.kitnew"
    chmod 755 "$NGFIT"
    rm -f "$GUARD"
    if grep -q 'AX3000T-KIT: netgear-empty-rootfs-guard' "$NGFIT"; then
      echo "✅ 已给 scripts/gen_netgear_rootfs_node.sh 加空 rootfs 兜底（权限已确保 755）"
    else
      echo "❌ 兜底补丁没打上：上游把 ROOTFS_FILE=\"\$1\" 那一行改了，请人工核对 $NGFIT"
      exit 1
    fi
  fi
  # 无条件复查可执行位（放在幂等分支之外：旧补丁留下的 644 必须能被修好）
  if [ ! -x "$NGFIT" ]; then
    chmod 755 "$NGFIT"
    echo "🔧 修复 scripts/gen_netgear_rootfs_node.sh 的可执行位（644 → 755）"
  fi
fi

# ---------------------------------------------------------------------------
# 4. 自检 —— 任何一项不过就中止，避免编出一个刷不进去的固件
#
#    检查「机型定义块内部」的那几项，都先把块单独截出来再 grep：
#    filogic.mk 里别的机型本来就有 kmod-mt7915e / IMAGE_SIZE := 这些字样，
#    对整文件 grep 会误判成通过。
# ---------------------------------------------------------------------------
fail() { echo "❌ 自检失败：$1"; exit 1; }

grep -q '^define Device/xiaomi_mi-router-ax3000t-mtkuboot$' "$MK" \
  || fail "filogic.mk 中没有机型定义（awk 没插进去？检查锚点行是否还在）"
grep -q '^TARGET_DEVICES += xiaomi_mi-router-ax3000t-mtkuboot$' "$MK" \
  || fail "机型没注册到 TARGET_DEVICES（少了这行 make defconfig 会静默丢掉机型）"

BLOCK=$(awk '/^define Device\/xiaomi_mi-router-ax3000t-mtkuboot$/{f=1} f{print} f&&/^endef$/{exit}' "$MK")
[ -n "$BLOCK" ] || fail "截取机型定义块失败"

echo "$BLOCK" | grep -q 'DEVICE_DTS := mt7981b-xiaomi-mi-router-ax3000t-mtkuboot' \
  || fail "机型块里 DEVICE_DTS 不对"
echo "$BLOCK" | grep -q 'UBINIZE_OPTS := -E 5' \
  || fail "机型块里 UBINIZE_OPTS 不对（必须与 yuzhii/hanwckf 布局完全一致）"
echo "$BLOCK" | grep -q 'KERNEL_IN_UBI := 1' \
  || fail "机型块里没有 KERNEL_IN_UBI（U-Boot 读不到 kernel 卷）"
echo "$BLOCK" | grep -q 'IMAGE_SIZE := 114688k' \
  || fail "机型块里 IMAGE_SIZE 不是 114688k（= 112 MiB）"
echo "$BLOCK" | grep -q 'kmod-mt7915e' \
  || fail "机型块里没有开源 mt76 驱动"
echo "$BLOCK" | grep -q 'IMAGE/factory.bin := append-ubi' \
  || fail "机型块里没有 append-ubi factory.bin（U-Boot WebUI 刷的就是它）"

grep -q 'mt7981b-xiaomi-mi-router-ax3000t.dtsi' "$DTS" || fail "DTS 没有 include 官方 .dtsi"
grep -q '0x600000 0x7000000' "$DTS" || fail "DTS 里 ubi 分区不是 0x600000 起、112 MiB"
grep -q 'xiaomi,mi-router-ax3000t-mtkuboot' "$DTS" || fail "DTS 里 compatible 不对（sysupgrade 会拒绝刷机）"
grep -q 'mediatek,nmbm' "$DTS" || fail "DTS 里没有开 NMBM（NAND 坏块管理，必须要有）"

if [ -f "$NGFIT" ]; then
  grep -q 'AX3000T-KIT: netgear-empty-rootfs-guard' "$NGFIT" \
    || fail "netgear 空 rootfs 兜底没打上（25.12 窄配置编译会在镜像阶段挂）"
  [ -x "$NGFIT" ] || fail "gen_netgear_rootfs_node.sh 没有可执行位（镜像阶段会 Error 126）"
fi

if grep -q 'kmod-mt_wifi' "$MK"; then
  echo "⚠️  警告：filogic.mk 里出现了 kmod-mt_wifi（闭源驱动），请人工确认这不是我们引入的"
fi

# ---------------------------------------------------------------------------
# 5. 结果确认
# ---------------------------------------------------------------------------
echo
echo "== 补丁结果 =="
grep -n 'xiaomi_mi-router-ax3000t-mtkuboot' "$MK" | head -n 4
ls -l "$DTS"
echo "== ubi 分区核对（应为 0x600000 + 0x7000000 = 112 MiB，终点 0x7600000） =="
grep -n 'partition@600000' -A 3 "$DTS" || true
if [ -f "$NGFIT" ]; then
  echo "== netgear 空 rootfs 兜底核对 =="
  grep -n 'AX3000T-KIT: netgear-empty-rootfs-guard' -A 3 "$NGFIT"
fi
echo "✅ AX3000T 112M 大分区适配补丁应用成功"
