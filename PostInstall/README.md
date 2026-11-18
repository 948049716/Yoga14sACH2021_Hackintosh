# PostInstall — 进系统后一键完美化工具包

替换好新版 `EFI` 并在 OpenCore 引导菜单按空格执行过一次 **`Reset NVRAM`** 进入 macOS 后，直接双击运行本目录下的 **`optimize_macos.command`** 即可自动完成系统内收尾配置（全程离线可用，不依赖 Xcode 工具或特殊网络环境）：

## 包含内容

1. **`optimize_macos.command`（双击运行）**
   - **睡眠防耗电优化**：自动配置 `pmset` 关闭 AMD 不支持的 S4 休眠镜像、PowerNap 与网络暗唤醒，同时关闭虚拟光感（`SSDT-ALS0`）引起的重启亮度跳变。
   - **安装联想控制中心 `ReYogaSMC.app`（`v2.2.1`）**：自动解压同目录内置的 `ReYogaSMC-App-2.2.1-RELEASE.zip` 到 `/Applications` 并清除隔离属性，支持菜单栏切换 **Fn+Q 省电 / 均衡 / 野兽模式（带屏幕 OSD 弹窗）**、开启 **80% 电池养护模式** 以及查看风扇/CPU 温度。
   - **内屏原厂名称识别（`DisplayOverride/`）**：覆盖 Yoga 14s ACH 2021 两款原厂 2.8K 90Hz 面板（华星 `CSOT MNE007ZA1-1` 与联想 `LEN8A90`）。
   - **根治核显浏览器局部红块花屏**：自动为已安装的 Google Chrome、Microsoft Edge、Brave 与 VSCode 写入禁用 `SkiaGraphite` 配置并清理旧着色器缓存，在**保留完整 4K 硬件加速**的同时消除局部红块闪烁。
   - **内核驱动加载自检**：自动核验触控板、时钟同步、核显、Wi-Fi、蓝牙与联想 EC 驱动是否已正常生效。

2. **首次双击如提示“无法验证开发者”**
   - 打开终端执行一次即可运行：
     ```bash
     bash PostInstall/optimize_macos.command
     ```
