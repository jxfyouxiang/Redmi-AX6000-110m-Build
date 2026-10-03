<h1 align="center">云编译红米 AX6000 · uboot 110M 大分区</h1>

<p align="center">
基于 <a href="https://github.com/lixiang2017/Redmi-AX6000-110m">lixiang2017/Redmi-AX6000-110m</a> 改造的个人自用仓库
</p>

---

## 一、这个仓库现在是什么

上游项目提供了 24.10 / 25.12 / LEDE / 23.07 四套 workflow。本仓库**只保留并启用一套**，其余全部移入 `Backups/` 目录备查。

> GitHub Actions 只读取 `.github/workflows/` 下的文件，放进 `Backups/` 等价于停用，但随时可以搬回来。

当前启用的 workflow：

| 项目 | 值 |
| --- | --- |
| 文件 | `.github/workflows/immortalwrt_110m_compact_24.10.yml` |
| 显示名称 | `immortalwrt_110m_compact_24.10` |
| 源码 | [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt) `openwrt-24.10` 分支 |
| 配置文件 | `ax6000_110m.config` |
| 触发方式 | 仅 `workflow_dispatch`（手动） + `repository_dispatch`，**已无定时任务** |
| 产物 | `factory.bin` + `sysupgrade.bin` + manifest + profiles.json |
| Release 名 | `RedmiAX6000_110m_24.10_<编译日期>` |

> workflow 文件名里的 `compact` 是沿用上游命名，**本仓库实际已放弃压缩方案**，见下文「与上游的差异」。

### 与上游的差异

| 项目 | 上游 | 本仓库 |
| --- | --- | --- |
| 使用的配置 | `ax6000_immortalwrt_110m_compact.config`（压缩优先，砍功能换空间） | `ax6000_110m.config`（官方默认包 + Argon + 代理内核层，不压缩） |
| 管理地址 | `192.168.16.1` | **`192.168.0.2`** |
| 主机名 | `ImmortalWrt` | **`AX6000`** |
| 默认主题 | `bootstrap` | **`Argon`** |
| 2.4G SSID | `Redmi-2.4G` | **`Redmi_805D`** |
| 5G SSID | `Redmi-5G` | **`Redmi_805D_5G`** |
| Wi-Fi 密码 | `qwer1234` | **自行设置** |

---

## 二、固件配置

### 编译内容

- **无线驱动**：ImmortalWrt 官方源码自带的**开源 `mt76`**（非闭源 `mt_wifi`），与 AX3000T 那套闭源驱动方案无关
- **主题**：`luci-theme-argon` + `luci-app-argon-config`
- **代理支持（内核层）**：`kmod-tun`、`kmod-inet-diag`、`kmod-nft-tproxy`、`kmod-veth`、`kmod-sched-core`、`kmod-sched-ingress`、`kmod-sched-bpf`、`kmod-xdp-sockets-diag`
- **daed 所需的 BPF / BTF 内核选项**：`CONFIG_KERNEL_BPF*`、`DEBUG_INFO_BTF`、`XDP_SOCKETS`、`KPROBE_EVENTS` 等一整套
- **用户态依赖**：`bash`、`dnsmasq-full`、`ip-full`、`unzip`、`ca-bundle`、`luci-compat`

**注意**：这里只编进「内核层的东西」。`luci-app-openclash`、`luci-app-daed` 的**本体不预装**，刷完后自行 `opkg install` 即可 —— 内核模块与内核版本绑定、自编译固件没有配套 kmod 源，所以它们必须编译时决定；而插件本体是纯用户态文件，随时能装。

### 默认参数

| 项目 | 配置 |
| --- | --- |
| 管理地址 | `192.168.0.2` |
| 主机名 | `AX6000` |
| 用户名 | `root` |
| 默认密码 |  **首次登录必须设置**（固件出厂不带密码） |
| 2.4G Wi-Fi | `Redmi_805D`，WPA2-PSK，加密算法**自动协商**（`psk2`） |
| 5G Wi-Fi | `Redmi_805D_5G`，WPA2-PSK，**强制 AES/CCMP**（`psk2+ccmp`） |
| Wi-Fi 密码 | 自行设置 |
| 国家 / 区域 | `CN` |

首次登录后请立即设置管理密码，并建议修改 Wi-Fi 密码。

> **为什么 2.4G 和 5G 的加密参数不一样？**
> 2.4G 用 `psk2`（算法自动协商）是为了兼容只有 TKIP 的老设备和 IoT 家电；5G 用 `psk2+ccmp` 把算法钉死在 AES，因为**跨设备漫游只发生在 5G 频段**，算法固定能少一类兼容性变量。
> 两台 AP 都不上 WPA3/SAE —— AX3000T 是闭源 `mt_wifi` 驱动，SAE 支持与跨驱动漫游都不可靠。

### 刻意没有做的事

这是一份 **fragment config**，只写「与官方默认不同」的部分，`make defconfig` 会自动补齐其余官方默认包。以下几项是**有意保持默认**的：

| 选项 | 为什么不开 |
| --- | --- |
| `CONFIG_OPTIMIZE_FOR_SIZE` | 收益极小，反而拖慢运行速度 |
| `CONFIG_STRIP_KERNEL_EXPORTS` | 会裁掉内核导出符号，以后想编译外部模块直接失败 |
| 关 USB / 关 cifs / nfs | 官方默认镜像本来就只有 ~16 MB，砍这些换不到空间，纯丢功能 |
| 语言白名单 `CONFIG_LUCI_LANG_*` | **纯属 no-op**。官方默认镜像本来就只装 zh-cn 的 4 个包（共 210 KB），英文是内建的（根本不存在 `luci-i18n-*-en` 这类包）。反过来把语言全开一次要 **+5.96 MB**（仅这 4 个应用），全部应用 × 全部语言理论上限 **+41.8 MB**。所以这一项保持默认即可 |

### 空间预期

- `factory.bin` / `sysupgrade.bin` 约 **16 MB**（上游压缩版也是这个量级，所以压缩在这里并没有换到额外收益）
- 刷入后 overlay 预计 **约 80 MB**（以刷完后 `df -h /overlay` 为准）
- 参考：非压缩但预装 OpenClash + Passwall 本体的固件约 45 MB，overlay 只剩 ~55 MB

---

## 三、仓库结构

```
.
├── .github/
│   ├── dependabot.yml
│   └── workflows/
│       └── immortalwrt_110m_compact_24.10.yml   ← 唯一启用
├── Backups/                                      ← 已停用的上游 workflow
│   ├── immortalwrt_110m.yml
│   ├── immortalwrt_110m_compact_25.12.yml
│   ├── immortalwrt_237_110m.yml
│   └── LEDE_110m.yml
├── ax6000_110m.config                            ← 本仓库使用的配置
├── customize_immortalwrt.sh                      ← 本仓库使用的定制脚本
├── ax6000_immortalwrt_110m.config                ← 上游配置，保留备查
├── ax6000_immortalwrt_110m_compact.config        ← 上游配置，保留备查
├── ax6000_LEDE_110m.config                       ← 上游配置，保留备查
├── customize.sh                                  ← 上游脚本，保留备查
├── 操作步骤-ax6000.md                             ← 从零到刷机的完整流程
└── README.md
```

`customize_immortalwrt.sh` 做了四件事：

1. 改默认 LAN IP：`192.168.1.1` → `192.168.0.2`
2. 改默认主机名：`ImmortalWrt` → `AX6000`
3. 把 luci 集合的默认主题 `luci-theme-bootstrap` 换成 `luci-theme-argon`
4. 写入 `/etc/uci-defaults/99-set-default-wifi`，首次开机自动开好两个频段的 SSID / 加密 / 密码

> `uci-defaults` 脚本只在**首次开机**执行一次，执行成功（`exit 0`）后文件会自动删除；执行 `firstboot` 或 `sysupgrade -n` 擦除配置后，下次开机会重新执行一遍。

---

## 四、编译与刷机

完整的从零流程（含 Actions 权限设置、uboot 分区切换、刷后验证）见 **[操作步骤-ax6000.md](操作步骤-ax6000.md)**。

三条最容易出错的：

1. 仓库里改 workflow 的 `CONFIG_FILE:` 时，必须写成 `'ax6000_110m.config'`（忘了改就还是编压缩方案）
2. Fork 的 Actions 需要先在 Actions 页面点横幅「I understand my workflows, go ahead and enable them」启用
3. `Settings → Actions → General → Workflow permissions` 必须选 **Read and write**，否则创建 Release 会 403

---

## 五、110M 大分区说明（重要）

本项目通过给 `filogic.mk` 追加设备定义 + 新建 DTS 的方式实现 110M 布局，**必须与已刷入的 U-Boot 布局匹配**：

| 项目 | 说明 |
| --- | --- |
| 适用 U-Boot | hanwckf / yuzhii 系不死 U-Boot，分区布局选 **`immortalwrt-110m`** |
| ubi 分区 | `0x600000` 起，长度 `0x6e00000`（110 MiB） |
| 刷机文件 | **必须选文件名里带 `-110m` 的 factory.bin** |
| 布局切换 | **只能在 U-Boot 里切**，不能在系统内跨布局 `sysupgrade` |
| 不要用 | ImmortalWrt 官方的 `-ubootmod` 固件 —— 那是 FIT/`fitblk` 引导（`root=/dev/fit0`），需要 ubootmod 模式的 U-Boot，刷到 110M 布局上会砖 |

**刷机前请务必**：确认设备已刷入支持 110M UBI 分区的不死 U-Boot、提前备份重要分区（尤其 `Factory` 射频校准分区）、准备好 U-Boot 恢复或串口救砖方案。刷机有变砖风险，请自行承担。

---

## 六、网络规划

光猫已改为**桥接**、关闭其 DHCP，管理页 `192.168.1.1`；红米 AX6000 作为主路由负责 PPPoE 拨号，LAN 段 `192.168.0.0/24`。

| 设备 | 地址 | 角色 |
| --- | --- | --- |
| 红米 AX6000 | `192.168.0.2` | 主路由（PPPoE + DHCP，地址池 `.100`–`.249`） |
| 小米 AX3000T | 固件默认 `192.168.6.1`，作 AP 后改为 `192.168.0.99` | 纯 AP（LAN↔LAN 有线连接，自身 DHCP 关闭） |

> 光猫桥接后，**从 LAN 侧访问不到光猫的管理页 `192.168.1.1` 是正常现象**（客户端会对同网段地址直接发 ARP，报文不会上送到路由器）。需要进光猫时，直连光猫自己的 Wi-Fi 即可。

---

## 致谢

- 原始项目：[lixiang2017/Redmi-AX6000-110m](https://github.com/lixiang2017/Redmi-AX6000-110m)
- Actions 模板：P3TERX / sky2016cn 的 Actions-OpenWrt 系列
- 110M 大分区方案与不死 U-Boot：[hanwckf/immortalwrt-mt798x](https://github.com/hanwckf/immortalwrt-mt798x)
