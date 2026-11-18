#!/bin/bash
# ==============================================================================
# Lenovo Yoga 14s ACH 2021 (R7-5800H) macOS 一键完美化调优脚本
# 支持双击直接运行，无需安装 Xcode Command Line Tools 或科学上网环境
# ==============================================================================

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "⚠️  请在笔记本进入 macOS 系统后双击或在终端运行此脚本。"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(dscl . -read "/Users/${REAL_USER}" NFSHomeDirectory | awk '{print $2}')"

echo "========================================================"
echo "  Yoga 14s ACH 2021 黑苹果系统内一键完美化配置工具"
echo "========================================================"
echo ""
echo "本脚本将自动完成以下 5 项调优："
echo "  1. 优化合盖睡眠与电源防耗电参数 (pmset + 关闭虚拟光感自动调光)"
echo "  2. 离线安装联想专属控制面板 ReYogaSMC.app v2.2.1 (Fn+Q 弹窗 / 80% 电池养护)"
echo "  3. 安装 2.8K 90Hz 内屏原厂名称描述文件 (DisplayOverride)"
echo "  4. 修复 Chrome / Edge / Brave / VSCode 在 AMD 核显下的局部红块花屏"
echo "  5. 自检关键黑苹果内核驱动加载状态"
echo ""
echo "🔑 请输入你的开机锁屏密码以授权系统级电源与显示器配置（输入时不显示星号，输完按回车）："
sudo -v

echo ""
echo "▶ [1/5] 正在配置 AMD 笔记本最佳睡眠与防暗唤醒电源策略..."
sudo pmset -a hibernatemode 0 standby 0 autopoweroff 0 proximitywake 0 powernap 0 tcpkeepalive 0 womp 0
sudo defaults write /Library/Preferences/com.apple.iokit.AmbientLightSensor "Automatic Display Enabled" -bool false || true
echo "  ✅ 已关闭不支持的 S4 休眠与后台暗唤醒耗电，并关闭虚拟环境光自动跳亮度。"

echo ""
echo "▶ [2/5] 正在离线安装 ReYogaSMC.app (v2.2.1)..."
APP_ZIP="${SCRIPT_DIR}/ReYogaSMC-App-2.2.1-RELEASE.zip"
if [[ -f "${APP_ZIP}" ]]; then
  killall ReYogaSMC >/dev/null 2>&1 || true
  TMP_EXTRACT="$(mktemp -d)"
  /usr/bin/ditto -x -k "${APP_ZIP}" "${TMP_EXTRACT}"
  if [[ -d "${TMP_EXTRACT}/ReYogaSMC.app" ]]; then
    sudo rm -rf /Applications/ReYogaSMC.app
    sudo mv "${TMP_EXTRACT}/ReYogaSMC.app" /Applications/ReYogaSMC.app
    sudo chown -R "${REAL_USER}:staff" /Applications/ReYogaSMC.app
    sudo xattr -cr /Applications/ReYogaSMC.app || true
    sudo -u "${REAL_USER}" open -a /Applications/ReYogaSMC.app || true
    echo "  ✅ ReYogaSMC.app 已安装至 /Applications 并已启动（可在菜单栏切换 Fn+Q 散热模式与 80% 电池养护）。"
  fi
  rm -rf "${TMP_EXTRACT}"
else
  echo "  ⚠️ 未找到 ${APP_ZIP}，已跳过应用安装。"
fi

echo ""
echo "▶ [3/5] 正在安装 Yoga 14s 2.8K 90Hz 内屏识别描述文件..."
OVERRIDE_DST="/Library/Displays/Contents/Resources/Overrides"
if [[ -d "${SCRIPT_DIR}/DisplayOverride" ]]; then
  sudo mkdir -p "${OVERRIDE_DST}"
  sudo cp -R "${SCRIPT_DIR}/DisplayOverride/"* "${OVERRIDE_DST}/"
  sudo chown -R root:wheel "${OVERRIDE_DST}/DisplayVendorID-e6f" "${OVERRIDE_DST}/DisplayVendorID-30ae" 2>/dev/null || true
  sudo chmod -R 755 "${OVERRIDE_DST}/DisplayVendorID-e6f" "${OVERRIDE_DST}/DisplayVendorID-30ae" 2>/dev/null || true
  echo "  ✅ 内屏型号描述文件已安装（重启系统后在「关于本机 -> 显示器」生效）。"
fi

echo ""
echo "▶ [4/5] 正在为 Chromium 系浏览器与 VSCode 配置防核显红块渲染参数 (禁用 SkiaGraphite)..."
for PROC_NAME in "Google Chrome" "Microsoft Edge" "Brave Browser"; do
  if pgrep -x "${PROC_NAME}" >/dev/null 2>&1; then
    echo "  ℹ️ 检测到 ${PROC_NAME} 正在运行，正在安全请求退出以写入配置..."
    sudo -u "${REAL_USER}" osascript -e "tell application \"${PROC_NAME}\" to quit" >/dev/null 2>&1 || true
    sleep 1
  fi
done

sudo -u "${REAL_USER}" /usr/bin/osascript -l JavaScript - "${REAL_HOME}" <<'JXA'
ObjC.import('Foundation');

function run(argv) {
  var home = argv[0];
  var fm = $.NSFileManager.defaultManager;
  var browsers = [
    { name: "Google Chrome", dir: home + "/Library/Application Support/Google/Chrome" },
    { name: "Microsoft Edge", dir: home + "/Library/Application Support/Microsoft Edge" },
    { name: "Brave Browser", dir: home + "/Library/Application Support/BraveSoftware/Brave-Browser" }
  ];

  browsers.forEach(function(b) {
    if (!fm.fileExistsAtPath(b.dir)) return;
    var localStatePath = b.dir + "/Local State";
    var data = {};
    if (fm.fileExistsAtPath(localStatePath)) {
      var raw = $.NSString.stringWithContentsOfFileEncodingError(localStatePath, $.NSUTF8StringEncoding, null);
      if (raw) {
        try { data = JSON.parse(ObjC.unwrap(raw)); } catch (e) { return; }
      }
    }
    if (!data.browser) data.browser = {};
    var exps = Array.isArray(data.browser.enabled_labs_experiments) ? data.browser.enabled_labs_experiments : [];
    exps = exps.filter(function(x) { return String(x).indexOf("skia-graphite") !== 0; });
    exps.push("skia-graphite@2");
    data.browser.enabled_labs_experiments = exps;

    var out = $(JSON.stringify(data));
    out.writeToFileAtomicallyEncodingError(localStatePath, true, $.NSUTF8StringEncoding, null);

    var cachePath = b.dir + "/GraphiteDawnCache";
    if (fm.fileExistsAtPath(cachePath)) {
      fm.removeItemAtPathError(cachePath, null);
    }
    console.log("  ✅ 已为 " + b.name + " 自动设为 skia-graphite = Disabled 并清理旧缓存。");
  });

  var vscodeArgv = home + "/.vscode/argv.json";
  if (fm.fileExistsAtPath(vscodeArgv)) {
    var vraw = $.NSString.stringWithContentsOfFileEncodingError(vscodeArgv, $.NSUTF8StringEncoding, null);
    if (vraw) {
      var txt = ObjC.unwrap(vraw);
      if (txt.indexOf("SkiaGraphite") === -1) {
        var idx = txt.lastIndexOf("}");
        if (idx > 0) {
          var prefix = txt.slice(0, idx).replace(/\s+$/, "");
          var needsComma = !prefix.endsWith("{") && !prefix.endsWith(",");
          var updated = prefix + (needsComma ? "," : "") + '\n\t"disable-features": "SkiaGraphite"\n}\n';
          $(updated).writeToFileAtomicallyEncodingError(vscodeArgv, true, $.NSUTF8StringEncoding, null);
          console.log("  ✅ 已为 VSCode (~/.vscode/argv.json) 添加 disable-features: SkiaGraphite。");
        }
      } else {
        console.log("  ✅ VSCode 已包含 SkiaGraphite 禁用项，无需重复修改。");
      }
    }
  }
}
JXA

echo ""
echo "▶ [5/5] 正在自检当前内核关键驱动加载状态..."
LOADED_KEXTS="$(kmutil showloaded --list-only 2>/dev/null || kextstat 2>/dev/null || true)"
check_kext() {
  local bundle_id="$1"
  local label="$2"
  if echo "${LOADED_KEXTS}" | grep -q "${bundle_id}"; then
    echo "  ✅ ${label} (${bundle_id}) — 已加载"
  else
    echo "  ⚪ ${label} (${bundle_id}) — 未检测到（若尚未覆盖新 EFI 并 Reset NVRAM 属正常现象）"
  fi
}

check_kext "me.kishorprins.VoodooInput" "I2C 触控板输入引擎"
check_kext "com.alexandred.VoodooI2C" "I2C 总线驱动"
check_kext "org.ChefKiss.ForgedInvariant" "AMD TSC 时钟同步"
check_kext "org.ChefKiss.NootedRed" "Radeon Vega 核显加速"
check_kext "org.reyoga.ReYogaSMC" "联想 EC 散热与电池养护"
check_kext "as.acidanthera.BlueToolFixup" "蓝牙与 AirPods 修复"
check_kext "com.zxystd.AirportItlwm" "Intel 原生状态栏 Wi-Fi"

echo ""
echo "========================================================"
echo "🎉 全部系统内优化已完成！建议重启一次系统让显示器描述文件生效。"
echo "💡 推荐选装：可安装免费软件 BetterDisplay 开启 1680x1050 @ 90Hz HiDPI 黄金缩放。"
echo "========================================================"
