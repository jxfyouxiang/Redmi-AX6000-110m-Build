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
| 文件 | `.github/workflows/immortalwrt_110m_24.10.6.yml` |
| 显示名称 | `immortalwrt_110m_24.10.6` |
| 源码 | [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt) **tag `v24.10.6`**（commit `5fa11a1b…`，内核 6.6.133） |
| 配置文件 | `ax6000_110m_24.10.6.config`（由官方 `config.buildinfo` 派生，不是手写 fragment） |
| 触发方式 | 仅 `workflow_dispatch`（手动，带 `abi_strict` 开关） + `repository_dispatch`，**无定时任务** |
| 产物 | `factory.bin` + `sysupgrade.bin` + manifest + profiles.json + **`config.buildinfo`** + **整包 kmods** |
| Release 名 | `RedmiAX6000_110m_v24.10.6_<编译日期>` |

> 旧文件名里的 `compact` 是沿用上游命名，**已彻底弃用**：压缩方案（手写 fragment）会关掉 `CONFIG_ALL_KMODS`，
> 使内核 ABI 哈希与官方分家，官方 kmods 装上去就是 `net_generic()` 空指针 panic。详见「与上游的差异」。

### 与上游的差异

| 项目 | 上游 | 本仓库 |
| --- | --- | --- |
| 使用的配置 | `ax6000_immortalwrt_110m_compact.config`（压缩优先，砍功能换空间） | `ax6000_110m_24.10.6.config`（**从官方 `config.buildinfo` 派生**；官方默认包 + Argon + 代理内核层，不压缩） |
| 源码版本 | `openwrt-24.10` 分支（浮动，每次编可能不是同一份代码） | **tag `v24.10.6`**（冻结；`feeds.conf.default` 里 4 个 feed 也已用 `^commit` 钉死） |
| 内核 ABI | 手写 fragment ⇒ 哈希与官方不同 ⇒ 官方 kmods 全废 | **与官方一致**（`a8b93917…`）⇒ 官方 1067 个 kmod 可直接 `opkg install` |
| 管理地址 | `192.168.16.1` | **`192.168.0.2`** |
| 主机名 | `ImmortalWrt` | **`Redmi_805D`** |
| 默认主题 | `bootstrap` | **`Argon`** |
| 2.4G SSID | `Redmi-2.4G` | **`Redmi_805D`** |
| 5G SSID | `Redmi-5G` | **`Redmi_805D_5G`** |
| Wi-Fi 密码 | `qwer1234` | **`u2hdehyh`** |

---

## 二、固件配置

### 编译内容

- **无线驱动**：ImmortalWrt 官方源码自带的**开源 `mt76`**（非闭源 `mt_wifi`），与 AX3000T 那套闭源驱动方案无关
- **主题**：`luci-theme-argon` + `luci-app-argon-config`（并把 luci 集合的默认主题从 bootstrap 换成 argon）
- **代理支持（内核层）**：`kmod-tun`、`kmod-inet-diag`、`kmod-nft-tproxy`、`kmod-veth`、`kmod-nfnetlink-queue`、`kmod-nft-queue`
  （`kmod-sched-core`／`kmod-sched-bpf`／`kmod-xdp-sockets-diag` 官方镜像本来就带，配置里保持原样）
- **内核选项**：**一行 `CONFIG_KERNEL_*` 都不写**，全部原样继承官方 `config.buildinfo`（包括 `MODULE_ALLOW_BTF_MISMATCH=y`）。
  手写那 15 行 `CONFIG_KERNEL_BPF*` 本身和官方取值相同（**不是**上次 panic 的原因），但"手写包清单"这种做法会连带关掉 `CONFIG_ALL_KMODS`，那才会让内核 ABI 哈希分家
- **用户态依赖**：`bash`、`dnsmasq-full`、`ip-full`、`unzip`、`ca-bundle`、`luci-compat`

**注意**：装进固件的只是「内核层的东西」。`luci-app-openclash`、`luci-app-daed` 的**本体不预装**，刷完后自行 `opkg install` 即可。
本版固件的 vermagic 与官方 24.10.6 完全相同（`a8b93917f464536104594f27d870028d`），所以官方 kmods 池（1067 个包）可以直接装，**不需要** `--force-depends`。

### 默认参数

| 项目 | 配置 |
| --- | --- |
| 管理地址 | `192.168.0.2` |
| 主机名 | `Redmi_805D` |
| 用户名 | `root` |
| 默认密码 | 无 |
| 2.4G Wi-Fi | `Redmi_805D`，WPA2-PSK，加密算法**自动协商**（`psk2`） |
| 5G Wi-Fi | `Redmi_805D_5G`，WPA2-PSK，**强制 AES/CCMP**（`psk2+ccmp`） |
| Wi-Fi 密码 | `u2hdehyh` |
| 国家 / 区域 | `CN` |

首次登录后请立即设置管理密码，并建议修改 Wi-Fi 密码。

> **为什么 2.4G 和 5G 的加密参数不一样？**
> 2.4G 用 `psk2`（算法自动协商）是为了兼容只有 TKIP 的老设备和 IoT 家电；5G 用 `psk2+ccmp` 把算法钉死在 AES，因为**跨设备漫游只发生在 5G 频段**，算法固定能少一类兼容性变量。
> 两台 AP 都不上 WPA3/SAE —— AX3000T 是闭源 `mt_wifi` 驱动，SAE 支持与跨驱动漫游都不可靠。

### 刻意没有做的事

这份配置**不是**手写的 fragment，而是从官方 24.10.6 的 `config.buildinfo` 逐字派生，只做了 3 处 delta：①只勾 110M 这一台设备（关掉 `TARGET_ALL_PROFILES`）；②加 11 个要装进固件的包；③其余 287 行原样照抄 —— 包括 `CONFIG_ALL_KMODS=y`、`CONFIG_ALL_NONSHARED=y`、`CONFIG_TARGET_PER_DEVICE_ROOTFS=y` 和 16 条 `CONFIG_KERNEL_*`。这几条决定了内核 ABI 哈希，动了它们官方 kmods 就废了。以下几项是**有意保持默认**的：

| 选项 | 为什么不开 |
| --- | --- |
| `CONFIG_OPTIMIZE_FOR_SIZE` | 收益极小，反而拖慢运行速度 |
| `CONFIG_STRIP_KERNEL_EXPORTS` | 会裁掉内核导出符号，以后想编译外部模块直接失败 |
| 关 USB / 关 cifs / nfs | 官方默认镜像本来就只有 ~16 MB，砍这些换不到空间，纯丢功能 |
| 语言白名单 `CONFIG_LUCI_LANG_*` | **纯属 no-op**。官方默认镜像本来就只装 zh-cn 的 4 个包（共 210 KB），英文是内建的（根本不存在 `luci-i18n-*-en` 这类包）。反过来把语言全开一次要 **+5.96 MB**（仅这 4 个应用），全部应用 × 全部语言理论上限 **+41.8 MB**。所以这一项保持默认即可 |

### 空间预期

- 固件大小以本次 Release 为准；110 MiB 的分区足够大，没必要再为了省几 MB 去砍功能 —— 砍功能换来的那点空间，代价是内核 ABI 与官方分家
- 刷入后 overlay 预计 **70~85 MB**（以刷完后 `df -h /overlay` 为准）
- 参考：预装 OpenClash + Passwall 本体的固件约 45 MB，overlay 只剩 ~55 MB

---

## 三、仓库结构

```
.
├── .github/
│   ├── dependabot.yml
│   └── workflows/
│       └── immortalwrt_110m_24.10.6.yml           ← 唯一启用
├── Backups/                                      ← 已停用的上游 workflow
│   ├── immortalwrt_110m.yml
│   ├── immortalwrt_110m_compact_25.12.yml
│   ├── immortalwrt_237_110m.yml
│   └── LEDE_110m.yml
├── ax6000_110m_24.10.6.config                    ← 本仓库使用的配置（文件名带版本）
├── customize_immortalwrt_24.10.6.sh              ← 本仓库使用的定制脚本（文件名带版本）
├── ax6000_immortalwrt_110m.config                ← 上游配置，保留备查
├── ax6000_immortalwrt_110m_compact.config        ← 上游配置，保留备查
├── ax6000_LEDE_110m.config                       ← 上游配置，保留备查
├── customize.sh                                  ← 上游脚本，保留备查
├── 操作步骤-ax6000.md                             ← 从零到刷机的完整流程
└── README.md
```

**命名约定**：配置、定制脚本、workflow 三份文件的名字里都带 ImmortalWrt 版本号（`immortalwrt_110m_24.10.6.yml` / `ax6000_110m_24.10.6.config` / `customize_immortalwrt_24.10.6.sh`）。这样做是为了以后能并存：哪天真要试 25.12，新的一套三个文件直接摆进来，不会覆盖 24.10.6 这套 —— 上一版全部叫无版本名的 `ax6000_110m.config` / `customize_immortalwrt.sh`，换个版本就只能原地覆盖，历史配置无处可查。**工作流里通过 `env.CONFIG_FILE` / `env.CUSTOMIZE_SCRIPT` 引用这两个名字，改文件名必须同时改这两行。**

`customize_immortalwrt_24.10.6.sh` 做了四件事（`set -euo pipefail`，每件都先断言目标串存在，对不上就中止编译，不再静默 no-op）：

1. 改默认 LAN IP：`192.168.1.1` → `192.168.0.2`，并回验
2. 改默认主机名：`ImmortalWrt` → `Redmi_805D`（只替换 `hostname='…'` 那一行，不再整文件 `s///g`）
3. 把 luci 集合的默认主题 `luci-theme-bootstrap` 换成 `luci-theme-argon`（找不到时打 `::warning::`，由 config 的包选择兜底）
4. 安装 `/etc/uci-defaults/99-set-default-wifi`，开机自动开好两个频段的 SSID / 加密 / 密码 —— **但加了守卫**：`default_radio0` 已有密码就直接 `exit 0`，所以以后的 `sysupgrade` 不会再把手改过的 WiFi 设置打回默认值

> `uci-defaults` 脚本在**首次开机**执行一次，成功（`exit 0`）后文件自动删除；执行 `firstboot` 或 `sysupgrade -n` 擦除配置后会再执行一遍 —— 上面那个守卫就是为这种情况准备的。**但 hostname（第 2 条）和 LAN IP 是改在源码默认值里的，不受守卫保护**，也正因为如此才不会再被 uci-defaults 覆盖。

---

## 四、编译与刷机

完整的从零流程（含 Actions 权限设置、uboot 分区切换、刷后验证）见 **[操作步骤-ax6000.md](操作步骤-ax6000.md)**。

四条最容易出错的：

1. 仓库根目录必须有 `ax6000_110m_24.10.6.config` 和 `customize_immortalwrt_24.10.6.sh` 两个文件（工作流会显式检查，缺了直接报错退出；**文件名必须与 `env.CONFIG_FILE` / `env.CUSTOMIZE_SCRIPT` 一致**）
2. Fork 的 Actions 需要先在 Actions 页面点横幅「I understand my workflows, go ahead and enable them」启用
3. `Settings → Actions → General → Workflow permissions` 必须选 **Read and write**，否则创建 Release 会 403
4. 跑完先看 `ABI 门` 那一步：出现 ✅ 才说明内核配置与官方一致、官方 kmods 池可用；出现 ⚠️ 就去 artifact 里的 `kernel-config-lines.txt` 排查

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
