#!/bin/bash
#=================================================
# 红米 AX6000 · ImmortalWrt v25.12.2 · 编译前定制脚本
#
# 与 customize_immortalwrt_24.10.6.sh 的三处改动完全一致，每一处都对应一个真实故障：
#
#  ① WiFi 凭据不再"无条件写死"
#     旧版：uci-defaults 里无条件 uci set ssid/key/encryption。
#           而 /etc/uci-defaults/ 里的脚本在每次 sysupgrade 后都会重跑
#           ⇒ 刷机后 WiFi 密码被打回脚本里的值，手动改过的全部丢失。
#     新版：只在"这台还没被个人化"时写（判据 = default_radio0 还没有密码），
#           已经设过密码的设备直接跳过。
#
#  ② 两处 sed 加断言（幂等：已改好就跳过）
#     旧版：sed 目标串一旦不存在就是静默 no-op（改主题那行尤其危险，
#           上游一改 luci 集合的依赖写法，它就一直悄悄失效）。
#     新版：先看"是不是已经改好了"，是就跳过；不是才断言目标存在 → sed → 复核结果。
#
#  ③ 默认主机名改成 Redmi_805D
#     旧版写的是 AX6000，而设备当前实际主机名是 Redmi_805D
#     ⇒ 不刷则已，一刷主机名就变回去。
#
# 25.12 相对 24.10 的差异（本脚本已按此加固）：
#   · 包管理器 opkg → apk。本脚本不用包管理器，但刷完机装 kmod 时要改习惯。
#   · 主题那一步不再猜"哪个 collection 列 bootstrap"：25.12 的 luci 集合可能又变过
#     版式（24.10 的 bootstrap 在 collections/luci-light/Makefile，不在 luci/Makefile），
#     所以直接遍历 feeds/luci/collections/*/Makefile，谁写着 bootstrap 就改谁。
#
# 本文件必须是 LF 换行、UTF-8 无 BOM，否则在 runner 上会跑不起来。
#=================================================
set -euo pipefail

# OW 解析（云端与本机都要能用 —— 2026-10-13 第一次 25.12 云编译就栽在这里）：
#   ① OPENWRT_DIR 环境变量（本地套件 config.env 里 export 的就是它）
#   ② 当前目录 —— 云端工作流这一步的 working-directory 就是 /builder/openwrt
#   ③ 常见位置兜底（/builder/openwrt、$HOME/openwrt25、$HOME/openwrt）
# 旧写法是 OW="${OPENWRT_DIR:-$HOME/openwrt}"：云端 runner 的 $HOME 是 /home/runner，
# 于是脚本跑去找 /home/runner/openwrt/package/… ⇒ 报 "config_generate 不存在" 而中止。
# （24.10.6 那份脚本写死 OW=/builder/openwrt，所以这个坑一直没暴露。）
pick_ow() {
  local c
  if [ -n "${OPENWRT_DIR:-}" ] && [ -f "$OPENWRT_DIR/package/base-files/files/bin/config_generate" ]; then
    printf '%s' "$OPENWRT_DIR"; return 0
  fi
  for c in "$PWD" /builder/openwrt "$HOME/openwrt25" "$HOME/openwrt"; do
    if [ -f "$c/package/base-files/files/bin/config_generate" ]; then printf '%s' "$c"; return 0; fi
  done
  printf '%s' "${OPENWRT_DIR:-$PWD}"   # 都找不到：交给下面那条断言报错，别在这里猜
}
OW="$(pick_ow)"
echo "源码树 OW = $OW"
CG=$OW/package/base-files/files/bin/config_generate

# ---------- 0. 前置断言：sed 目标必须真的存在 ----------
# 注意：本脚本必须**可重复执行**（本地套件会重跑同一阶段；而且它 2026-10-12 那次
# 已经改过一次，第二次再跑就会"找不到 192.168.1.1"而误报上游改版）。
# 所以每一项都先看"是不是已经改好了"，是就跳过，不是才断言+改写。
[ -f "$CG" ] || { echo "::error::$CG 不存在"; exit 1; }

# ---------- 1. 默认 LAN IP：192.168.1.1 -> 192.168.0.2 ----------
if grep -q '192\.168\.0\.2' "$CG"; then
  echo "⏭  默认 LAN IP 已经是 192.168.0.2（上次跑过），跳过"
else
  grep -q '192\.168\.1\.1' "$CG" || { echo "::error::config_generate 里既没有 192.168.1.1 也没有 192.168.0.2（上游改了默认 LAN IP？）"; exit 1; }
  sed -i 's/192\.168\.1\.1/192.168.0.2/g' "$CG"
  grep -q '192\.168\.0\.2' "$CG" || { echo "::error::LAN IP 改写没生效"; exit 1; }
  echo "✅ 默认 LAN IP：192.168.1.1 → 192.168.0.2"
fi

# ---------- 2. 默认主机名：ImmortalWrt -> Redmi_805D ----------
# 只动 "set system.@system[-1].hostname='...'" 这一行；不再用全局 s///g
# （那会顺手改掉同一文件里其它 ImmortalWrt 字样，属于隐性副作用）。
if grep -q "hostname='Redmi_805D'" "$CG"; then
  echo "⏭  默认主机名已经是 Redmi_805D（上次跑过），跳过"
else
  grep -q "hostname='ImmortalWrt'" "$CG" || { echo "::error::config_generate 里既没有 hostname='ImmortalWrt' 也没有 hostname='Redmi_805D'（上游改了默认主机名？）"; exit 1; }
  sed -i "s/hostname='ImmortalWrt'/hostname='Redmi_805D'/" "$CG"
  grep -q "hostname='Redmi_805D'" "$CG" || { echo "::error::主机名改写没生效"; exit 1; }
  echo "✅ 默认主机名：ImmortalWrt → Redmi_805D"
fi

# ---------- 3. 默认主题改成 Argon ----------
# 必须在 ./scripts/feeds install -a 之后执行，否则打不到 luci 集合的 Makefile 上。
# 版本差异（这就是为什么遍历而不是写死路径）：
#   collections/luci/Makefile        老版式：直接列 +luci-theme-bootstrap
#   collections/luci-light/Makefile  24.10.x：真正列 bootstrap 的是这一层
#   （24.10.6 上只改 luci/Makefile 是空改 —— 2026-10-12 踩过）
# 这一步只影响"装哪个主题"；即使打不到，config 里的
# CONFIG_PACKAGE_luci-theme-argon=y 也会把 Argon 装进固件，所以只警告不中止。
changed=0
for mk in "$OW"/feeds/luci/collections/*/Makefile; do
  [ -f "$mk" ] || continue
  if grep -q '+luci-theme-bootstrap' "$mk"; then
    sed -i 's/+luci-theme-bootstrap/+luci-theme-argon/g' "$mk"
    grep -q '+luci-theme-argon' "$mk" || { echo "::error::$mk 主题改写没生效"; exit 1; }
    echo "✅ 默认主题已改为 argon（$mk）"
    changed=1
  fi
done
if [ "$changed" = 0 ]; then
  if grep -rqs '+luci-theme-argon' "$OW"/feeds/luci/collections/ 2>/dev/null; then
    echo "⏭  默认主题已经是 argon（上次跑过），跳过"
  else
    echo "::warning::feeds/luci/collections/*/Makefile 里既没有 +luci-theme-bootstrap 也没有 +luci-theme-argon（上游改过 luci 集合）—— 主题改由 ax6000_110m_25.12.2.config 的包选择决定，不中断编译。"
  fi
fi

# ---------- 4. uci-defaults：只在"还没个人化"的设备上写 WiFi ----------
mkdir -p "$OW/files/etc/uci-defaults"
cat > "$OW/files/etc/uci-defaults/99-set-default-wifi" <<'EOF'
#!/bin/sh
# 只在出厂/未配置状态下写入 WiFi 凭据。
# 判据：default_radio0 还没有 key —— 出厂镜像首次开机必然为空；
# 之后再 sysupgrade（保留 /etc/config）时 key 还在，这里直接退出，绝不覆盖用户设置。
[ -n "$(uci -q get wireless.default_radio0.key)" ] && exit 0

# 2.4G：psk2（加密算法自动协商，兼容老设备 / IoT）
uci set wireless.radio0.disabled='0'
uci set wireless.radio0.country='CN'
uci set wireless.default_radio0.ssid='Redmi_805D'
uci set wireless.default_radio0.encryption='psk2'
uci set wireless.default_radio0.key='u2hdehyh'

# 5G：psk2+ccmp（强制 AES；漫游主要走这一段）
uci set wireless.radio1.disabled='0'
uci set wireless.radio1.country='CN'
uci set wireless.default_radio1.ssid='Redmi_805D_5G'
uci set wireless.default_radio1.encryption='psk2+ccmp'
uci set wireless.default_radio1.key='u2hdehyh'

uci commit wireless
exit 0
EOF
chmod +x "$OW/files/etc/uci-defaults/99-set-default-wifi"

# ---------- 5. 结果确认 ----------
echo "== 定制结果 =="
grep -n "hostname='Redmi_805D'" "$CG"
grep -n "192.168.0.2" "$CG"
ls -l "$OW/files/etc/uci-defaults/99-set-default-wifi"
echo "✅ customize_immortalwrt_25.12.2.sh 全部完成"
