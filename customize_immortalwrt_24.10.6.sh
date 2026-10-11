#!/bin/bash
#=================================================
# 红米 AX6000 · ImmortalWrt v24.10.6 · 编译前定制脚本
#
# 相对上一版（lixiang2017/Redmi-AX6000-110m 的 customize_immortalwrt.sh。
# 本仓库把它改名为 customize_immortalwrt_24.10.6.sh，让"哪份脚本配哪个版本"一眼可辨）
# 的三处改动，每一处都对应一个真实故障：
#
#  ① WiFi 凭据不再"无条件写死"
#     旧版：uci-defaults 里无条件 uci set ssid/key/encryption。
#           而 /etc/uci-defaults/ 里的脚本在每次 sysupgrade 后都会重跑
#           ⇒ 刷机后 WiFi 密码被打回脚本里的值，手动改过的全部丢失。
#     新版：只在"这台还没被个人化"时写（判据 = default_radio0 还没有密码），
#           已经设过密码的设备直接跳过。
#
#  ② 两处 sed 加断言
#     旧版：sed 目标串一旦不存在就是静默 no-op（改主题那行尤其危险，
#           上游一改 luci 集合的依赖写法，它就一直悄悄失效）。
#     新版：先确认目标存在，再 sed，sed 完再确认结果；对不上就中止编译。
#
#  ③ 默认主机名改成 Redmi_805D
#     旧版写的是 AX6000，而设备当前实际主机名是 Redmi_805D
#     ⇒ 不刷则已，一刷主机名就变回去。
#
# 本文件必须是 LF 换行、UTF-8 无 BOM，否则在 runner 上会跑不起来。
#=================================================
set -euo pipefail

OW=/builder/openwrt
CG=$OW/package/base-files/files/bin/config_generate
LUCI_MK=$OW/feeds/luci/collections/luci/Makefile

# ---------- 0. 前置断言：sed 目标必须真的存在 ----------
[ -f "$CG" ] || { echo "::error::$CG 不存在"; exit 1; }
grep -q '192\.168\.1\.1' "$CG" || { echo "::error::config_generate 里找不到 192.168.1.1（上游改了默认 LAN IP？）"; exit 1; }
grep -q "hostname='ImmortalWrt'" "$CG" || { echo "::error::config_generate 里找不到 hostname='ImmortalWrt'（上游改了默认主机名？）"; exit 1; }

# ---------- 1. 默认 LAN IP：192.168.1.1 -> 192.168.0.2 ----------
sed -i 's/192\.168\.1\.1/192.168.0.2/g' "$CG"
grep -q '192\.168\.0\.2' "$CG" || { echo "::error::LAN IP 改写没生效"; exit 1; }

# ---------- 2. 默认主机名：ImmortalWrt -> Redmi_805D ----------
# 只动 "set system.@system[-1].hostname='...'" 这一行；不再用全局 s///g
# （那会顺手改掉同一文件里其它 ImmortalWrt 字样，属于隐性副作用）。
sed -i "s/hostname='ImmortalWrt'/hostname='Redmi_805D'/" "$CG"
grep -q "hostname='Redmi_805D'" "$CG" || { echo "::error::主机名改写没生效"; exit 1; }

# ---------- 3. 默认主题改成 Argon ----------
# 必须在 ./scripts/feeds install -a 之后执行，否则打不到 luci 集合的 Makefile 上。
# 这一步只影响"默认主题"；即使打不到，config 里的
# CONFIG_PACKAGE_luci-theme-argon=y 也会把 Argon 装进固件，所以只警告不中止。
if [ -f "$LUCI_MK" ] && grep -q '+luci-theme-bootstrap' "$LUCI_MK"; then
  sed -i 's/+luci-theme-bootstrap/+luci-theme-argon/g' "$LUCI_MK"
  echo "✅ 默认主题已改为 argon"
else
  echo "::warning::$LUCI_MK 里没有 +luci-theme-bootstrap（上游改过 luci 集合）—— 主题改由 ax6000_110m_24.10.6.config 的包选择决定，不中断编译。"
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
echo "✅ customize_immortalwrt_24.10.6.sh 全部完成"
