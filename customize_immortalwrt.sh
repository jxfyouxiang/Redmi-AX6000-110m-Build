#!/bin/bash
#=================================================
# 基于 lixiang2017/Redmi-AX6000-110m 的 customize_immortalwrt.sh 修改
#
# 本版参数：
#   LAN IP      : 192.168.0.2
#   主机名      : AX6000
#   默认主题    : Argon
#   2.4G SSID   : Redmi_805D     密码 u2hdehyh   加密 psk2（算法自动协商）
#   5G   SSID   : Redmi_805D_5G  密码 u2hdehyh   加密 psk2+ccmp（强制 AES）
#
# 注意：本文件必须是 LF 换行、UTF-8 无 BOM，否则在 runner 上跑不起来。
#=================================================
set -e

# 1. 修改默认 LAN IP
sed -i 's/192.168.1.1/192.168.0.2/g' /builder/openwrt/package/base-files/files/bin/config_generate

# 2. 修改默认主机名
sed -i 's/ImmortalWrt/AX6000/g' /builder/openwrt/package/base-files/files/bin/config_generate

# 3. 把 Argon 设为默认主题
#    必须在 ./scripts/feeds install -a 之后执行，否则打不到 luci 集合的 Makefile 上
sed -i 's/+luci-theme-bootstrap/+luci-theme-argon/g' /builder/openwrt/feeds/luci/collections/luci/Makefile

# 4. 生成 uci-defaults，首次开机自动开 WiFi
#    SSID / 密码与 AX3000T 保持一致，便于漫游
#    加密策略：
#      2.4G -> psk2        WPA2 个人版，加密算法自动协商（兼容老设备/IoT）
#      5G   -> psk2+ccmp   WPA2 个人版 + 强制 AES（漫游只涉及 5G，算法钉死更稳）
#    两台都不上 WPA3(sae)：AX3000T 是闭源 mt_wifi 驱动，
#    SAE 支持与跨驱动漫游都不可靠
mkdir -p /builder/openwrt/files/etc/uci-defaults

cat > /builder/openwrt/files/etc/uci-defaults/99-set-default-wifi <<'EOF'
#!/bin/sh

# 2.4G radio0 —— 加密算法自动协商
uci set wireless.radio0.disabled='0'
uci set wireless.radio0.country='CN'
uci set wireless.default_radio0.ssid='Redmi_805D'
uci set wireless.default_radio0.encryption='psk2'
uci set wireless.default_radio0.key='u2hdehyh'

# 5G radio1 —— 漫游涉及此频段，强制 AES
uci set wireless.radio1.disabled='0'
uci set wireless.radio1.country='CN'
uci set wireless.default_radio1.ssid='Redmi_805D_5G'
uci set wireless.default_radio1.encryption='psk2+ccmp'
uci set wireless.default_radio1.key='u2hdehyh'

uci commit wireless
exit 0
EOF

chmod +x /builder/openwrt/files/etc/uci-defaults/99-set-default-wifi
