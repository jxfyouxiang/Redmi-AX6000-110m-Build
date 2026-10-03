# AX3000T · ImmortalWrt 官方源码 + 开源 mt76 + 112M 大分区

小米 AX3000T（v1 / MT7531），**yuzhii / hanwckf MTK U-Boot** 的 `immortalwrt-112m` 布局，
改用 **ImmortalWrt 官方源码**（`immortalwrt/immortalwrt` @ `openwrt-24.10`）与
**开源 mt76 驱动**，替换掉 `padavanonly/immortalwrt-mt798x-6.6` 的 MTK 闭源 `mt_wifi`。

**不需要更换 bootloader。**

---

## 为什么这条路走得通

原来的固件来自 237（padavanonly）仓库，用闭源 `mt_wifi`。它有一个未修复的内核 Oops：
漫游引导（RSSI Steering）时调用 `call_usermodehelper()` 传入了野指针，导致

```
__pi_strnlen → copy_strings_kernel → kernel_execve
           → call_usermodehelper_exec_async → ret_from_fork
Unable to handle kernel read from unreadable memory
Kernel panic - not syncing: Oops: Fatal exception
```

崩溃点不在无线数据路径上，而是"内核要启动一个用户态助手"。闭源二进制无法修，
只能永远不进入这条路径 —— 也就是只能用官方开源驱动替换。

### 拆解旧固件的 factory.bin

| 观测项 | 结果 |
| :--- | :--- |
| 文件头 4 字节 | `55 42 49 23` = `"UBI#"` |
| PEB 大小 | 131072 字节（128 KiB） |
| VID 头偏移 | 2048 |
| EC 头数量 | 162 → 162 × 131072 = 文件大小，**精确整除** |
| 卷名 | `kernel` / `rootfs` / `rootfs_data` |
| 尾部 | 无厂商签名或元数据 |

→ 它是一个**裸 UBI 镜像**。U-Boot 启动流程只有：attach UBI → 读 `kernel` 卷 → `bootm`。
**它完全不关心内核里跑的是 mt_wifi 还是 mt76。**

### 对比 237 与官方 ImmortalWrt 的 DTS

| 文件 | 237 | 官方 | 结果 |
| :--- | ---: | ---: | :--- |
| `mt7981b-xiaomi-mi-router-ax3000t.dts` | 694 B | 694 B | 字节一致 |
| `mt7981b-xiaomi-mi-router-ax3000t.dtsi` | 434 B | 434 B | 字节一致 |
| `mt7981b-xiaomi-mi-router-common.dtsi` | 7577 B | 7577 B | 字节一致 |
| `mt7981b-xiaomi-mi-router-ax3000t-mtkuboot.dts` | 486 B | 不存在 | 237 新增 |

**237 为了跑闭源驱动，一个板级 DTS 都没改。** WiFi 走的是
`&wifi { nvmem-cells = <&eeprom_factory_0>; }`，官方树里一模一样，mt76 用的就是它。

### 实机核对的分区表

在正在运行的 237 固件上执行 `cat /proc/mtd`，与 DTS 逐项吻合。
`BL2`/`Nvram`/`Bdata`/`Factory`/`FIP`/`crash`/`crash_log`/`KF` 来自公共 `.dtsi`；
`ubi` 来自 `-mtkuboot.dts` 里 `&partitions` 的**追加**节点，所以在 DT 里排在最后，对应 mtd8：

| mtd | label | 起始 | 大小 | 来源 |
| ---: | :--- | ---: | ---: | :--- |
| 0 | BL2 | 0x000000 | 1 MiB | common.dtsi |
| 1 | Nvram | 0x100000 | 256 KiB | common.dtsi |
| 2 | Bdata | 0x140000 | 256 KiB | common.dtsi |
| 3 | Factory | 0x180000 | 2 MiB | common.dtsi |
| 4 | FIP | 0x380000 | 2 MiB | common.dtsi |
| 5 | crash | 0x580000 | 256 KiB | common.dtsi |
| 6 | crash_log | 0x5C0000 | 256 KiB | common.dtsi |
| **8** | **ubi** | **0x600000** | **0x7000000 = 112 MiB** | **mtkuboot.dts** |
| 7 | KF | 0x7600000 | 256 KiB | common.dtsi |

`0x600000 + 0x7000000 = 0x7600000`，正好是 `KF` 的起点 —— 无重叠、无空洞。
NAND 共 128 MiB（0x8000000），尾部约 9.75 MiB 未使用。

这份分区表就是 `IMAGE_SIZE := 114688k`（= 112 MiB）与 DTS 里
`reg = <0x600000 0x7000000>` 的来源。

### 237 的 -mtkuboot 机型定义

```makefile
define Device/xiaomi_mi-router-ax3000t-mtkuboot
  DEVICE_DTS := mt7981b-xiaomi-mi-router-ax3000t-mtkuboot
  UBINIZE_OPTS := -E 5
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 114688k          # 112 MiB
  KERNEL_IN_UBI := 1
  IMAGES += factory.bin
  IMAGE/factory.bin := append-ubi | check-size $$$$(IMAGE_SIZE)
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
```

**里面一行驱动配置都没有，纯布局。** 所以整个移植只需要加一个 DTS + 这个机型定义，
驱动由官方树自带的 mt76 提供。

---

## 仓库文件

本方案的文件收在 `ax3000t-mt76-112m/` 子目录里，与 AX6000 的编译流程完全隔离：

```
ax3000t-mt76-112m/customize_ax3000t_112m.sh    补丁脚本（自包含，内嵌 DTS）
ax3000t-mt76-112m/ax3000t-mt76-112m.config     config 片段
.github/workflows/build-ax3000t-mt76-112m.yml  云编译（必须放在 .github/workflows/）
```

## 编译

按上面的目录结构推上去，然后
Actions → `Build AX3000T 112M (ImmortalWrt official + mt76)` → Run workflow。

本 workflow 只监听 `workflow_dispatch` 与 `repository_dispatch[ax3000t]`，不带 `push` 触发，
所以改动仓库**不会**顺带跑起 AX6000 的编译，两个机型的流程互不干扰。

### 四道自动断言（都放在烧时间的编译之前）

设计原则：**让失败发生在几分钟内，而不是两个多小时之后。**

| 时机 | 断言 |
| :--- | :--- |
| 检出仓库后 | `customize_ax3000t_112m.sh` 与 `.config` 片段都在仓库里 |
| feeds 装完后 | `package/feeds/{packages,luci}` 存在；`luci-theme-argon`、`luci-app-argon-config`、`luci-app-ttyd`、`luci-app-commands`、`modules/luci-base` 都能 `[ -e ]` 到 |
| `make defconfig` 后 | 选中 `DEVICE_xiaomi_mi-router-ax3000t-mtkuboot`；`kmod-mt7915e` 选中；`kmod-mt_wifi` 不得出现；`luci-theme-argon` / `luci-app-argon-config` / `luci-app-ttyd` / `luci-app-commands` / `luci-i18n-base-zh-cn` / `wpad-openssl` 必须 `=y` |
| 编译之后 | `factory.bin` 头 4 字节必须是 `55424923`（`UBI#`），且大小是 131072 的整数倍。**不满足就失败，不会放出刷不进去的固件。** |

### 这个 workflow 踩过的坑（别踩回去）

1. **`maximize-build-space` 必须排在 `actions/checkout` 之前。**
   它会把一个新卷挂到 `build-mount-path` 上，之前 checkout 下来的内容会被整个遮住
   （不是删掉，是看不见了）。所以它排第一步，checkout 排它之后。
2. **必须跑 `./scripts/feeds update -a && ./scripts/feeds install -a`。**
   `immortalwrt/immortalwrt` 只是核心仓，LuCI / Argon 都在独立的 feeds 仓里。
   漏了这步，`CONFIG_PACKAGE_luci-*` 会被 `make defconfig` **静默丢掉**，
   最后卡死在 `package/install`，白烧两个多小时。
3. **`./scripts/feeds install` 建的是符号链接，不是目录。**
   检查只能用 `[ -e ]`（会跟随符号链接）；用 `find -type d` 一个都找不到
   （符号链接的类型是 `l` 不是 `d`）。
4. **不要拿"推导出来的符号"当门禁。**
   `CONFIG_PACKAGE_luci` 只是 `default-settings-chn` 传递依赖出来的，
   不保证在 `.config` 里写成 `=y`。断言必须钉在**本片段里显式写了、
   且上游确实存在**的包上。这条已经做成机械校验（见下）。

### 关于编译依赖

依赖清单对着 ImmortalWrt 官方的 `init_build_environment.sh` 补齐了
`fakeroot / quilt / sharutils / jq / genisoimage`，并补上了官方脚本里那行
`/usr/include/asm` 软链（少了它编某些内核模块会报 `asm/types.h` 找不到）。

顺带说明：**依赖不是前三次失败的原因** —— 失败的第二轮已经用更早那份清单
把工具链、内核和全部 kmod 都编出来了，它是倒在 `package/install` 的 feeds 缺包上。

### 离线自检脚本

`tools/verify_patch.py` 和 `tools/verify_all.py` 可以在**不联网、不跑 CI** 的情况下
把上面每一条断言都验一遍（前者用真实的 upstream `filogic.mk` 复现补丁逻辑，
后者解析 workflow YAML 并交叉核对 config 片段）。改动这几个文件之后先跑它们。

## 刷机

1. 进现有 U-Boot 的 WebUI 更新页面（通常是 `http://192.168.1.1/uboot.html` 所在的同一台机器）。
2. 刷 `*-squashfs-factory.bin`。

**为什么要先备份**：刷之前记下当前 `factory.bin`（旧固件）放在手边。
新固件如果起不来，进 U-Boot 把旧的重刷回去即可 —— U-Boot 只往 `ubi` 分区写，
碰不到 BL2 / FIP / Factory，所以**不存在换 bootloader 那种变砖风险**。

## 刷完后的验证

```sh
uname -a                      # 应为 openwrt-24.10 内核
dmesg | grep -iE 'mt7915|mt76|mt7981'
ls /sys/kernel/debug/ieee80211/    # 开源驱动才有这个目录
iw dev                             # mt76 支持 nl80211（闭源 mt_wifi 不支持）
```

`iw dev` 能出结果，就说明确实是 mt76 —— 闭源驱动下这条命令会报 `nl80211 not found`。

## 附：为什么不是换成 OpenWrt U-Boot

官方 24.10 的 `-ubootmod` 镜像需要主线 bootloader（FIT / `fitblk`），
和第三方大分区 U-Boot 不兼容，往大分区 U-Boot 里刷会报"文件校验失败"。
ImmortalWrt 23.05 曾经有 "custom U-Boot layout" 变体就是给这种 U-Boot 用的，
24.10 移除了（"因为升主线了，需要刷支持主线的 bootloader"）。

本方案走的是另一条路：**保持大分区 U-Boot 不变，把它的布局定义搬进官方源码。**
