#!/bin/bash
# ==============================================================================
# Lenovo Yoga 14s ACH 2021 (R7-5800H) 无损更新 EFI 引导一键脚本
# 自动挂载 EFI -> 备份原 EFI 到桌面 -> 自动继承原机三码保护 iCloud -> 保护 Windows 双系统引导
# ==============================================================================

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "⚠️  请在笔记本进入 macOS 系统后运行此脚本。"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SRC_EFI="${REPO_ROOT}/EFI"
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(dscl . -read "/Users/${REAL_USER}" NFSHomeDirectory | awk '{print $2}')"

if [[ ! -f "${SRC_EFI}/BOOT/BOOTx64.efi" || ! -f "${SRC_EFI}/OC/OpenCore.efi" || ! -f "${SRC_EFI}/OC/config.plist" ]]; then
  echo "❌ 未找到完整的新版 EFI 目录 (${SRC_EFI})，请保持项目目录结构完整再运行。"
  exit 1
fi

/usr/bin/plutil -lint "${SRC_EFI}/OC/config.plist" >/dev/null

echo "========================================================"
echo "  Yoga 14s ACH 2021 黑苹果无损更新 EFI 引导工具"
echo "  (免重装系统 · 自动备份 · 保留原机 iCloud 三码 · 保护双系统)"
echo "========================================================"
echo ""
echo "🔑 请输入你的开机锁屏密码以授权挂载 EFI 分区（输入时不显示星号，输完按回车）："
sudo -v

TMP_WORK="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_WORK}"
}
trap cleanup EXIT

# 1. 自动识别当前启动磁盘对应的 EFI 分区 (ESP)
diskutil info -plist / > "${TMP_WORK}/root_info.plist"
diskutil list -plist > "${TMP_WORK}/all_disks.plist"
diskutil list -plist internal > "${TMP_WORK}/internal_disks.plist"

ESP_DEV="$(/usr/bin/osascript -l JavaScript - "${TMP_WORK}/root_info.plist" "${TMP_WORK}/all_disks.plist" "${TMP_WORK}/internal_disks.plist" <<'JXA'
ObjC.import('Foundation');

function dictFromPlist(path) {
  var d = $.NSDictionary.dictionaryWithContentsOfFile(path);
  return d ? ObjC.deepUnwrap(d) : {};
}

function wholeDiskOf(devId) {
  if (!devId) return "";
  var m = String(devId).match(/^(disk\d+)/);
  return m ? m[1] : "";
}

function findEfiOnWholeDisk(listObj, targetDisk) {
  var all = listObj.AllDisksAndPartitions || [];
  for (var i = 0; i < all.length; i++) {
    var entry = all[i];
    if (entry.DeviceIdentifier === targetDisk || !targetDisk) {
      var parts = entry.Partitions || [];
      for (var j = 0; j < parts.length; j++) {
        if (parts[j].Content === "EFI" && parts[j].DeviceIdentifier) {
          return parts[j].DeviceIdentifier;
        }
      }
    }
  }
  return "";
}

function findPhysicalWholeFromContainers(listObj, containerDisk) {
  if (!containerDisk) return "";
  var all = listObj.AllDisksAndPartitions || [];
  for (var i = 0; i < all.length; i++) {
    var entry = all[i];
    if (entry.DeviceIdentifier === containerDisk && Array.isArray(entry.APFSPhysicalStores) && entry.APFSPhysicalStores.length > 0) {
      var s0 = entry.APFSPhysicalStores[0];
      return wholeDiskOf(s0.DeviceIdentifier || s0.APFSPhysicalStore);
    }
  }
  return "";
}

function run(argv) {
  var rootInfo = dictFromPlist(argv[0]);
  var allDisks = dictFromPlist(argv[1]);
  var internalDisks = dictFromPlist(argv[2]);
  var physWhole = "";

  if (Array.isArray(rootInfo.APFSPhysicalStores) && rootInfo.APFSPhysicalStores.length > 0) {
    var store0 = rootInfo.APFSPhysicalStores[0];
    physWhole = wholeDiskOf(store0.APFSPhysicalStore || store0.DeviceIdentifier);
  }
  if (!physWhole && rootInfo.ParentWholeDisk) {
    physWhole = findPhysicalWholeFromContainers(allDisks, rootInfo.ParentWholeDisk) || wholeDiskOf(rootInfo.ParentWholeDisk);
  }

  var esp = physWhole ? findEfiOnWholeDisk(allDisks, physWhole) : "";
  if (!esp) {
    esp = findEfiOnWholeDisk(internalDisks, "");
  }
  return esp;
}
JXA
)"

if [[ -z "${ESP_DEV}" ]]; then
  echo ""
  echo "⚠️ 未能自动定位内置磁盘的 EFI 分区，当前磁盘列表如下："
  diskutil list
  read -r -p "请手动输入 EFI 分区代号（例如 disk0s1）: " ESP_DEV
fi
ESP_DEV="${ESP_DEV#/dev/}"

if [[ -z "${ESP_DEV}" ]]; then
  echo "❌ 未指定有效的 EFI 分区代号，已退出。"
  exit 1
fi

echo ""
echo "🔍 检测到目标 EFI 引导分区: /dev/${ESP_DEV}"
read -r -p "确认备份原 EFI 并将新版引导写入 /dev/${ESP_DEV} 吗？[Y/n]: " CONFIRM_ESP
CONFIRM_ESP="${CONFIRM_ESP:-Y}"
if [[ ! "${CONFIRM_ESP}" =~ ^[Yy]$ ]]; then
  echo "已取消操作。"
  exit 0
fi

# 2. 挂载 EFI 分区并获取真实挂载点（兼容 /Volumes/EFI 1 及 root 0700 挂载权限）
echo ""
echo "▶ [1/4] 正在挂载 /dev/${ESP_DEV}..."
sudo diskutil mount "/dev/${ESP_DEV}" >/dev/null
diskutil info -plist "/dev/${ESP_DEV}" > "${TMP_WORK}/esp_info.plist"
MOUNT_POINT="$(/usr/libexec/PlistBuddy -c "Print :MountPoint" "${TMP_WORK}/esp_info.plist" 2>/dev/null || true)"

if [[ -z "${MOUNT_POINT}" ]] || ! sudo test -d "${MOUNT_POINT}"; then
  echo "❌ 挂载 /dev/${ESP_DEV} 失败，请检查磁盘状态。"
  exit 1
fi
echo "  ✅ 已挂载于: ${MOUNT_POINT}"

# 3. 完整备份现有 EFI 到桌面
echo ""
echo "▶ [2/4] 正在备份电脑原有 EFI..."
BACKUP_DIR="${REAL_HOME}/Desktop/EFI_Backup_$(date +%Y%m%d_%H%M%S)"
OLD_CFG=""
if sudo test -d "${MOUNT_POINT}/EFI"; then
  mkdir -p "${BACKUP_DIR}"
  sudo cp -R "${MOUNT_POINT}/EFI" "${BACKUP_DIR}/EFI"
  sudo chown -R "${REAL_USER}:staff" "${BACKUP_DIR}"
  if [[ ! -d "${BACKUP_DIR}/EFI" ]]; then
    echo "❌ 备份原 EFI 失败，已中止写入以保护原引导！"
    exit 1
  fi
  if [[ -f "${BACKUP_DIR}/EFI/OC/config.plist" ]]; then
    OLD_CFG="${BACKUP_DIR}/EFI/OC/config.plist"
  fi
  echo "  ✅ 原 EFI 已完整备份至桌面: ${BACKUP_DIR}/EFI"
  echo "     （建议顺手将此备份文件夹也复制一份到 FAT32 U 盘做应急引导备份）"
else
  echo "  ℹ️ 当前 EFI 分区尚无 EFI 文件夹，将直接全新写入。"
fi

# 4. 准备临时副本并自动继承原机三码 (PlatformInfo -> Generic)
echo ""
echo "▶ [3/4] 正在准备新版 EFI 并核对原机 Apple ID / iCloud 三码..."
STAGE_EFI="${TMP_WORK}/StageEFI"
cp -R "${SRC_EFI}" "${STAGE_EFI}"
STAGE_CFG="${STAGE_EFI}/OC/config.plist"

if [[ -n "${OLD_CFG}" && -f "${OLD_CFG}" ]] && /usr/bin/plutil -lint "${OLD_CFG}" >/dev/null 2>&1; then
  MIGRATED_KEYS=()
  for KEY in SystemProductName SystemSerialNumber MLB SystemUUID; do
    OLD_VAL="$(/usr/libexec/PlistBuddy -c "Print :PlatformInfo:Generic:${KEY}" "${OLD_CFG}" 2>/dev/null || true)"
    NEW_VAL="$(/usr/libexec/PlistBuddy -c "Print :PlatformInfo:Generic:${KEY}" "${STAGE_CFG}" 2>/dev/null || true)"
    if [[ -n "${OLD_VAL}" && "${OLD_VAL}" != "${NEW_VAL}" ]]; then
      /usr/libexec/PlistBuddy -c "Set :PlatformInfo:Generic:${KEY} '${OLD_VAL}'" "${STAGE_CFG}"
      MIGRATED_KEYS+=("${KEY}")
    fi
  done

  OLD_ROM_B64="$(/usr/bin/plutil -extract PlatformInfo.Generic.ROM raw -o - "${OLD_CFG}" 2>/dev/null || true)"
  NEW_ROM_B64="$(/usr/bin/plutil -extract PlatformInfo.Generic.ROM raw -o - "${STAGE_CFG}" 2>/dev/null || true)"
  if [[ -n "${OLD_ROM_B64}" && "${OLD_ROM_B64}" != "${NEW_ROM_B64}" ]]; then
    printf "%s" "${OLD_ROM_B64}" | /usr/bin/base64 -D > "${TMP_WORK}/old_rom.bin"
    if [[ -s "${TMP_WORK}/old_rom.bin" ]]; then
      /usr/libexec/PlistBuddy -c "Import :PlatformInfo:Generic:ROM '${TMP_WORK}/old_rom.bin'" "${STAGE_CFG}"
      MIGRATED_KEYS+=("ROM")
    fi
  fi

  if [[ ${#MIGRATED_KEYS[@]} -gt 0 ]]; then
    echo "  ✅ 已自动从原机继承三码字段 (${MIGRATED_KEYS[*]})，确保已登录的 Apple ID / iCloud 不掉线！"
  else
    echo "  ✅ 原机三码与仓库一致，已完整保留。"
  fi
else
  echo "  ℹ️ 未检测到旧版 config.plist，已使用当前配置中的三码。"
fi

# 写入前严格校验生成的 config.plist 合法性
/usr/bin/plutil -lint "${STAGE_CFG}" >/dev/null
dot_clean -m "${STAGE_EFI}" 2>/dev/null || find "${STAGE_EFI}" -name '._*' -delete 2>/dev/null || true

# 5. 安全覆盖 EFI/BOOT 与 EFI/OC（绝不触碰 EFI/Microsoft）
echo ""
echo "▶ [4/4] 正在写入新版 EFI/BOOT 与 EFI/OC..."
sudo mkdir -p "${MOUNT_POINT}/EFI"
if sudo test -d "${MOUNT_POINT}/EFI/Microsoft"; then
  echo "  🛡️ 检测到 Windows 双系统引导目录 (EFI/Microsoft)，已安全保留！"
fi

sudo rm -rf "${MOUNT_POINT}/EFI/BOOT" "${MOUNT_POINT}/EFI/OC"
sudo cp -R "${STAGE_EFI}/BOOT" "${MOUNT_POINT}/EFI/BOOT"
sudo cp -R "${STAGE_EFI}/OC" "${MOUNT_POINT}/EFI/OC"
sudo dot_clean -m "${MOUNT_POINT}/EFI/BOOT" "${MOUNT_POINT}/EFI/OC" 2>/dev/null || true

# 写入后二次校验磁盘上的关键文件
if ! sudo test -f "${MOUNT_POINT}/EFI/BOOT/BOOTx64.efi" || ! sudo test -f "${MOUNT_POINT}/EFI/OC/OpenCore.efi"; then
  echo "❌ 写入校验异常！请勿重启，可用桌面备份 ${BACKUP_DIR}/EFI 恢复。"
  exit 1
fi
sudo /usr/bin/plutil -lint "${MOUNT_POINT}/EFI/OC/config.plist" >/dev/null
sync
sudo diskutil unmount "/dev/${ESP_DEV}" >/dev/null || true
echo "  ✅ 新版 OpenCore 1.0.8 引导与驱动已安全写入并卸载 EFI 分区！"

echo ""
read -r -p "是否现在顺便执行系统内完美化调优 (安装 ReYogaSMC / 睡眠优化 / 修复浏览器红块)？[Y/n]: " RUN_OPT
RUN_OPT="${RUN_OPT:-Y}"
if [[ "${RUN_OPT}" =~ ^[Yy]$ ]]; then
  echo ""
  bash "${SCRIPT_DIR}/optimize_macos.command"
fi

echo ""
echo "========================================================"
echo "🎉 更新全部完成！无需重装系统，接下来只需最后一步："
echo "👉 重启电脑 -> 在 OpenCore 引导界面按【空格键】-> 选择一次【Reset NVRAM】即可！"
echo "========================================================"
