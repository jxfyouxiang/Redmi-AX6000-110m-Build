#!/bin/bash
#=================================================
# 小米 AX3000T · ImmortalWrt v25.12.2 · 编译前定制脚本
#
# 这份脚本比 AX6000 那份**故意更保守**，原因写在这里，方便以后回看：
#   · 不默认改 LAN IP、不默认改主机名 —— 这台机器的 /etc/config 会在 sysupgrade
#     时被保留，改了默认值等于"新闪存才生效"，但一旦用户是全新刷（不保留配置），
#     突然变成别的 IP 反而会让人找不到管理页面。要改的话把下面第 2/3 节取消注释。
#   · WiFi 默认值放在 uci-defaults 里，并且**只在设备还没被个人化时**才写
#     （判据：default_radio0 还没有 key）。sysupgrade 保留配置时它直接退出，绝不覆盖。
#     用 SET_DEFAULT_WIFI=0 可以整体关掉（工作流 env 里也能改）。
#   · 只做两件"必然是好事"的事：把默认主题换成 argon（和 AX6000 一致）、
#     把 WiFi 默认值写好（与 AX6000 同 SSID/密码，方便 usteer 漫游）。
#
# 本文件必须是 LF 换行、UTF-8 无 BOM，否则在 runner 上会跑不起来。
#=================================================
set -euo pipefail

# OW 解析（云端与本机都要能用）：
#   ① OPENWRT_DIR 环境变量（本地套件 config.env 导出）
#   ② 当前目录 —— 云端这一步的 working-directory 就是 /builder/openwrt
#   ③ 常见位置兜底
# 教训：旧写法 OW="${OPENWRT_DIR:-$HOME/openwrt}" 在云端 runner 上会去找
# /home/runner/openwrt/… ⇒ 报 "config_generate 不存在" 而中止（2026-10-13 踩过）。
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
[ -f "$CG" ] || { echo "::error::$CG 不存在"; exit 1; }

# ---------- 1. 默认主题改成 Argon ----------
# 必须在 ./scripts/feeds install -a 之后执行，否则打不到 luci 集合的 Makefile 上。
# 遍历而不是写死路径的原因：上游换过版式（24.10 时真正列 bootstrap 的是
# collections/luci-light/Makefile，不是 collections/luci/Makefile）。
# 这一步只影响"装哪个主题"；即使打不到，.config 里的
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
    echo "::warning::feeds/luci/collections/*/Makefile 里既没有 +luci-theme-bootstrap 也没有 +luci-theme-argon —— 主题改由 ax3000t_112m_25.12.2.config 的包选择决定，不中断编译。"
  fi
fi

# ---------- 2. 可选：默认 LAN IP ----------
# 默认不动（保持官方 192.168.1.1）。要注意别和 AX6000（192.168.0.2）冲突。
# if ! grep -q '192\.168\.1\.1' "$CG"; then echo "::error::config_generate 里没有 192.168.1.1"; exit 1; fi
# sed -i 's/192\.168\.1\.1/192.168.1.2/g' "$CG"

# ---------- 3. 可选：默认主机名 ----------
# 默认不动（保持官方 ImmortalWrt）。要改就取消注释并换成想要的名字。
# grep -q "hostname='ImmortalWrt'" "$CG" || { echo "::error::上游改了默认主机名"; exit 1; }
# sed -i "s/hostname='ImmortalWrt'/hostname='Redmi_AX3000T'/" "$CG"

# ---------- 4. uci-defaults：只在"还没个人化"的设备上写 WiFi ----------
# 判据：default_radio0 还没有 key —— 出厂镜像首次开机必然为空；
# 之后 sysupgrade（保留 /etc/config）时 key 还在，这里直接退出，绝不覆盖用户设置。
SET_DEFAULT_WIFI="${SET_DEFAULT_WIFI:-1}"
if [ "$SET_DEFAULT_WIFI" = "1" ]; then
  mkdir -p "$OW/files/etc/uci-defaults"
  cat > "$OW/files/etc/uci-defaults/99-set-default-wifi" <<'EOF'
#!/bin/sh
# 只在出厂/未配置状态下写入 WiFi 凭据（与 AX6000 同 SSID/密码，方便 usteer 漫游）。
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
  echo "✅ 已写入 WiFi 默认值 uci-defaults（SET_DEFAULT_WIFI=0 可关闭）"
else
  echo "⏭  SET_DEFAULT_WIFI=$SET_DEFAULT_WIFI ⇒ 不写 WiFi 默认值"
fi

# ---------- 5. 结果确认 ----------
echo "== 定制结果 =="
grep -rn 'luci-theme-argon' "$OW"/feeds/luci/collections/*/Makefile 2>/dev/null || echo "  （luci 集合里没有 +luci-theme-argon 字样）"
[ -f "$OW/files/etc/uci-defaults/99-set-default-wifi" ] && ls -l "$OW/files/etc/uci-defaults/99-set-default-wifi" || true
echo "✅ customize_immortalwrt_ax3000t_25.12.2.sh 全部完成"
