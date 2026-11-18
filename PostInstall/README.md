# PostInstall — 免重装无损更新 EFI 与系统内完美化工具包

如果你电脑上**已经刷入了旧版黑苹果系统**，无需重装系统、不会丢失任何软件数据或退出 Apple ID / iCloud，直接下载本项目完整压缩包解压后运行本目录脚本即可一键升级。

---

## 一、全自动无损更新（推荐）

先临时插一个外接鼠标进入当前 macOS，打开「终端」输入 `bash `（后面带空格），将 **`PostInstall/update_efi.command`** 拖入终端按回车（或直接双击运行）：

```bash
bash PostInstall/update_efi.command
```

**`update_efi.command` 会自动安全完成以下全套流程：**
1. 自动识别并挂载内置硬盘的 `EFI` 引导分区；
2. 先将电脑原有的整个 `EFI` 文件夹完整备份到桌面（`~/Desktop/EFI_Backup_日期时间/EFI`，建议顺手再拷一份到 FAT32 U 盘以防万一）；
3. 自动对比并继承你原机 `EFI/OC/config.plist` 中的三码（`SystemProductName` / `SystemSerialNumber` / `MLB` / `SystemUUID` / `ROM`）并用系统 `plutil` 严格校验，**确保已登录的 Apple ID / iCloud 100% 不掉线**；
4. **仅更新 `EFI/BOOT` 与 `EFI/OC`**（若电脑保留了 Windows 双系统，自动保护 `EFI/Microsoft` 引导不被触碰）；
5. 完成后提示一键联动执行同目录的 **`optimize_macos.command`**（安装 `ReYogaSMC.app`、优化 `pmset` 睡眠防掉电、安装 2.8K 内屏型号文件、修复 Chrome/Edge/VSCode 核显红块）。

> **最后一步**：脚本跑完后**重启电脑**，在 OpenCore 图标界面用笔记本自带键盘按一下**空格键**，选择 **`Reset NVRAM`**，重启进入桌面即全部生效！

---

## 二、手动更新步骤（备用：macOS 终端或 Windows 下操作）

如果你习惯手动拷贝（或当前在 Windows 双系统下用 `DiskGenius` 操作）：

1. **挂载并备份原 EFI**
   - **macOS 下**：终端运行 `diskutil list` 找到类型为 `EFI` 的分区（通常为 `disk0s1`），执行 `sudo diskutil mount disk0s1`，先把访达左侧 `EFI` 盘里的 `EFI` 文件夹备份到 FAT32 U 盘。
   - **Windows 下**：打开 `DiskGenius`，选中硬盘最前面的 `ESP (EFI)` 分区，右键将原有的 `EFI` 文件夹复制到桌面或 U 盘备份。
2. **保留个人三码（如曾改过）**
   - 如果你当初自行生成过三码，把原 `EFI/OC/config.plist` 里的 `PlatformInfo -> Generic` 段落复制到新版 `EFI/OC/config.plist` 对应位置；若一直使用仓库默认文件则无需修改。
3. **只替换 `BOOT` 和 `OC`**
   - 删除 EFI 分区 `EFI/` 目录下的 **`BOOT`** 和 **`OC`** 两个文件夹（⚠️ **切勿删除 `Microsoft` 文件夹**，否则会影响 Windows 启动），将本项目中的 `EFI/BOOT` 和 `EFI/OC` 复制进去（Windows `DiskGenius` 下按「复制到当前分区」并保存更改）。
4. **重置一次 NVRAM 并执行系统内收尾**
   - 重启电脑，在 OpenCore 引导界面按**空格键**选择 **`Reset NVRAM`**；
   - 进入 macOS 后运行系统调优脚本：
     ```bash
     bash PostInstall/optimize_macos.command
     ```

---

## 三、`optimize_macos.command` 单项说明（可随时独立重复运行）

- **睡眠防耗电优化**：自动配置 `pmset` 关闭 AMD 不支持的 S4 休眠镜像、PowerNap 与网络暗唤醒，同时关闭虚拟光感（`SSDT-ALS0`）引起的重启亮度跳变。
- **离线安装联想控制中心 `ReYogaSMC.app`（`v2.2.1`）**：自动解压同目录内置的 `ReYogaSMC-App-2.2.1-RELEASE.zip` 到 `/Applications`，支持菜单栏切换 **Fn+Q 省电 / 均衡 / 野兽模式（带屏幕 OSD 弹窗）**、开启 **80% 电池养护模式** 以及查看风扇/CPU 温度。
- **内屏原厂名称识别（`DisplayOverride/`）**：覆盖 Yoga 14s ACH 2021 两款原厂 2.8K 90Hz 面板（华星 `CSOT MNE007ZA1-1` 与联想 `LEN8A90`）。
- **根治核显浏览器局部红块花屏**：自动为已安装的 Google Chrome、Microsoft Edge、Brave 与 VSCode 写入禁用 `SkiaGraphite` 配置并清理旧着色器缓存，在**保留完整 4K 硬件加速**的同时消除局部红块闪烁。
- **内核驱动加载自检**：自动核验触控板、时钟同步、核显、Wi-Fi、蓝牙与联想 EC 驱动是否已正常生效。
