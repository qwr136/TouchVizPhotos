#!/usr/bin/env python3
"""deb 静态门禁（Python 标准库）。

用法: verify_deb.py --project DIR --scheme roothide --expected-version 1.0 a.deb
校验容器、元数据、布局、Filter、面板引用及双架构 Mach-O 结构；
不证明代码签名、所有动态依赖可加载、指令语义或真机行为。
"""

import argparse
import bz2
import gzip
import io
import json
import lzma
import plistlib
import re
import struct
import sys
import tarfile
from pathlib import Path, PurePosixPath


ARCHITECTURES = {"rootful": "iphoneos-arm", "rootless": "iphoneos-arm64",
                 "roothide": "iphoneos-arm64e"}


def read_ar(raw):
    if raw[:8] != b"!<arch>\n":
        raise ValueError("不是 ar 归档")
    members, pos = {}, 8
    while pos < len(raw):
        if pos + 60 > len(raw):
            raise ValueError("ar header 截断")
        header = raw[pos:pos + 60]
        if header[58:60] != b"`\n":
            raise ValueError("ar header 尾标记损坏")
        name = header[:16].decode("ascii").strip()
        size_text = header[48:58].decode("ascii").strip()
        if not size_text.isdecimal():
            raise ValueError("ar size 非法")
        size = int(size_text)
        end = pos + 60 + size
        if end + size % 2 > len(raw):
            raise ValueError("ar member 截断")
        body = raw[pos + 60:end]
        if size % 2 and raw[end:end + 1] != b"\n":
            raise ValueError("ar 对齐填充损坏")
        if name.startswith("#1/"):
            length = int(name[3:])
            if not 0 < length <= len(body):
                raise ValueError("ar 扩展名称越界")
            name, body = body[:length].decode("ascii").rstrip("\x00"), body[length:]
        else:
            name = name.rstrip("/")
        if not name or name in members:
            raise ValueError("ar 名称为空或重复: " + name)
        members[name] = body
        pos = end + size % 2
    return members


def tar_open(blob):
    return tarfile.open(fileobj=io.BytesIO(blob), mode="r:*")


def read_tar(name, blob):
    # 先完整解压，避免 tar 提前遇到 EOF 而漏掉压缩流 CRC/尾部损坏。
    if name.endswith(".gz"):
        blob = gzip.decompress(blob)
    elif name.endswith((".xz", ".lzma")):
        blob = lzma.decompress(blob)
    elif name.endswith(".bz2"):
        blob = bz2.decompress(blob)
    elif not name.endswith(".tar"):
        raise ValueError("不支持的 tar 压缩格式: " + name)
    if len(blob) % 512:
        raise ValueError("tar block 截断")
    entries, seen = {}, set()
    with tarfile.open(fileobj=io.BytesIO(blob), mode="r:") as tar:
        for member in tar:
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or "\\" in member.name:
                raise ValueError("tar 路径非法: " + member.name)
            key = str(path)
            if key == "." and member.isdir():
                continue
            if key in seen or key == "." or member.size < 0:
                raise ValueError("tar 路径重复或 member 非法: " + key)
            seen.add(key)
            if member.isdir():
                continue
            if member.isfile():
                data = tar.extractfile(member).read()
                if len(data) != member.size:
                    raise ValueError("tar 文件截断: " + key)
                entries[key] = data
            elif member.issym() or member.islnk():
                entries[key] = None  # 核心产物必须是可直接检查的普通文件。
            else:
                raise ValueError("tar 文件类型非法: " + key)
        if (blob[tar.offset:tar.offset + 1024] != b"\0" * 1024
                or any(blob[tar.offset:])):
            raise ValueError("tar 结束块缺失或存在尾随数据")
    return entries


def parse_control(blob):
    if blob is None:
        raise ValueError("缺少普通文件 control")
    result, current, ended = {}, None, False
    for line in blob.decode("utf-8").splitlines():
        if not line:
            ended = bool(result)
            continue
        if ended:
            raise ValueError("control 包含多个 stanza")
        if line[0].isspace():
            if current is None:
                raise ValueError("control 孤立续行")
            result[current] += " " + line.strip()
            continue
        key, separator, value = line.partition(":")
        key = key.lower()
        if not separator or not re.fullmatch(r"[a-z0-9][a-z0-9-]*", key) or key in result:
            raise ValueError("control 字段损坏或重复: " + key)
        result[key], current = value.strip(), key
    return result


def dependencies(text):
    # A | B 仅能保证其中一个；必须依赖只接受独立的逗号组，不能子串匹配。
    required = set()
    atom = r"([a-z0-9][a-z0-9+.-]*(?::[a-z0-9-]+)?)(?:\s*\((?:<<|<=|=|>=|>>)\s*[^()]+\))?"
    for group in text.split(","):
        choices = [item.strip() for item in group.split("|")]
        parsed = [re.fullmatch(atom, item) for item in choices]
        if not all(parsed):
            raise ValueError("Depends 语法非法: " + group)
        if len(parsed) == 1:
            required.add(parsed[0].group(1))
    return required


def macho(blob, cpu, subtype, kinds=(6,)):
    endian = {b"\xcf\xfa\xed\xfe": "<", b"\xfe\xed\xfa\xcf": ">"}.get(blob[:4])
    if endian is None or len(blob) < 32:
        raise ValueError("slice 不是完整的 64-bit Mach-O")
    _, inner_cpu, inner_sub, kind, count, size, _, reserved = struct.unpack(endian + "8I", blob[:32])
    if (inner_cpu, inner_sub) != (cpu, subtype):
        raise ValueError("FAT 与内部 Mach-O CPU/subtype 不一致")
    if kind not in kinds or reserved or not count or count > size // 8 or size > len(blob) - 32:
        raise ValueError("Mach-O 非 MH_DYLIB 或加载命令表越界")
    pos, limit, identity, segments = 32, 32 + size, 0, 0
    for _ in range(count):
        if pos + 8 > limit:
            raise ValueError("Mach-O load command header 越界")
        command, length = struct.unpack_from(endian + "II", blob, pos)
        if length < 8 or length % 8 or pos + length > limit:
            raise ValueError("Mach-O load command size/边界非法")
        if command in (0xc, 0xd, 0x18 | 0x80000000, 0x1f | 0x80000000,
                       0x20, 0x23 | 0x80000000):
            if length < 24:
                raise ValueError("Mach-O dylib command 截断")
            start = struct.unpack_from(endian + "I", blob, pos + 8)[0]
            if not 24 <= start < length or not blob[pos + start:pos + length].split(b"\0", 1)[0]:
                raise ValueError("Mach-O dylib 名称偏移非法")
            if b"\0" not in blob[pos + start:pos + length]:
                raise ValueError("Mach-O dylib 名称未终止")
            identity += command == 0xd
        if command == 0x19:  # LC_SEGMENT_64
            if length < 72:
                raise ValueError("Mach-O segment command 截断")
            fileoff, filesize = struct.unpack_from(endian + "QQ", blob, pos + 40)
            sections = struct.unpack_from(endian + "I", blob, pos + 64)[0]
            if length != 72 + 80 * sections or fileoff + filesize > len(blob):
                raise ValueError("Mach-O segment/section 越界")
            segments += 1
        if command == 0x1d:  # LC_CODE_SIGNATURE：只检查范围，不声称验签。
            if length != 16:
                raise ValueError("Mach-O signature command 长度非法")
            offset, size = struct.unpack_from(endian + "II", blob, pos + 8)
            if offset + size > len(blob):
                raise ValueError("Mach-O signature 数据越界")
        pos += length
    if pos != limit or not segments or identity != (1 if kind == 6 else 0):
        raise ValueError("Mach-O sizeofcmds/segment 不完整或 LC_ID_DYLIB 数量错误")


def slices(blob, *, kinds=(6,)):
    formats = {b"\xca\xfe\xba\xbe": (">", False), b"\xbe\xba\xfe\xca": ("<", False),
               b"\xca\xfe\xba\xbf": (">", True), b"\xbf\xba\xfe\xca": ("<", True)}
    if len(blob) < 8 or blob[:4] not in formats:
        raise ValueError("必须为包含 arm64/arm64e 的 FAT dylib，薄 dylib 不符合模板")
    endian, wide = formats[blob[:4]]
    count = struct.unpack_from(endian + "I", blob, 4)[0]
    step = 32 if wide else 20
    table_end = 8 + count * step
    if not 0 < count <= 64 or table_end > len(blob):
        raise ValueError("FAT 架构表越界或计数非法")
    names, ranges = [], []
    for index in range(count):
        row = struct.unpack_from(endian + ("IIQQII" if wide else "IIIII"), blob, 8 + index * step)
        cpu, subtype, offset, size, align = row[:5]
        if wide and row[5] != 0:
            raise ValueError("FAT64 reserved 非零")
        if (cpu != 0x100000c or (subtype & 0xffffff) not in (0, 2)):
            raise ValueError("FAT CPU/subtype 不是 arm64 或 arm64e")
        name = "arm64e" if (subtype & 0xffffff) == 2 else "arm64"
        if name in names:
            raise ValueError("FAT 架构重复: " + name)
        if (align > 31 or offset < table_end or offset % (1 << align)
                or size < 32 or offset + size > len(blob)):
            raise ValueError("FAT slice 边界/对齐非法")
        if any(offset < end and start < offset + size for start, end in ranges):
            raise ValueError("FAT slice 重叠")
        macho(blob[offset:offset + size], cpu, subtype, kinds)
        names.append(name)
        ranges.append((offset, offset + size))
    if set(names) != {"arm64", "arm64e"}:
        raise ValueError("缺少 arm64 或 arm64e slice")
    return sorted(names)


def load_plist(files, name):
    if not isinstance(files.get(name), bytes):
        raise ValueError("缺少普通文件 plist: " + name)
    value = plistlib.loads(files[name])
    if not isinstance(value, dict):
        raise ValueError("plist 根节点必须为 dict: " + name)
    return value


def _validate(path, manifest, scheme, expected_version):
    problems = []
    if manifest is not None and not isinstance(manifest, dict):
        raise ValueError("manifest 必须为 tweak.json 字典")
    meta = manifest or {}
    declared = meta.get("scheme")
    if scheme and declared and scheme != declared:
        problems.append("scheme 与 manifest 不一致")
    scheme = scheme or declared
    members = read_ar(Path(path).read_bytes())
    names = list(members)
    if (len(names) < 3 or names[0] != "debian-binary" or members[names[0]] != b"2.0\n"
            or not re.fullmatch(r"control\.tar(?:\.(?:gz|xz|bz2|lzma))?", names[1])
            or not re.fullmatch(r"data\.tar(?:\.(?:gz|xz|bz2|lzma))?", names[2])
            or any(n.startswith(("control.tar", "data.tar")) for n in names[3:])):
        raise ValueError("deb 必须按顺序含唯一 debian-binary 2.0 / control.tar / data.tar")
    control = parse_control(read_tar(names[1], members[names[1]]).get("control"))
    files = read_tar(names[2], members[names[2]])
    package, version, architecture = (control.get(key, "") for key in ("package", "version", "architecture"))
    if not re.fullmatch(r"[a-z0-9][a-z0-9+.-]+", package):
        problems.append("control Package 缺少或非法")
    if not re.fullmatch(r"\d[A-Za-z0-9.+:~\-]*", version):
        problems.append("control Version 缺少或非法")
    if manifest is not None and (not meta.get("package") or package != meta["package"]):
        problems.append("control Package 与 manifest 不一致")
    wanted_version = expected_version if expected_version is not None else meta.get("version")
    if wanted_version is not None and version != str(wanted_version):
        problems.append("control Version 与 expected-version 不一致")
    if scheme is None:
        scheme = next((key for key, value in ARCHITECTURES.items() if value == architecture), None)
    if scheme not in ARCHITECTURES:
        problems.append("scheme/Architecture 无法识别")
    elif architecture != ARCHITECTURES[scheme]:
        problems.append("control Architecture 与 scheme 不一致")
    depends = dependencies(control["depends"]) if control.get("depends") else set()
    needed = {"mobilesubstrate"} | ({"roothide"} if scheme == "roothide" else set())
    if scheme != "roothide" and "roothide" in depends:
        problems.append("非 roothide scheme 含 roothide 依赖")
    prefix = "var/jb/" if scheme == "rootless" else ""
    for name in files:
        if (name.startswith("var/jb/") and scheme != "rootless"
                or name.startswith("Library/") and scheme == "rootless"):
            problems.append("安装布局与 scheme 不一致: " + name)
    injection_dirs = {prefix + "Library/" + suffix for suffix in
                      ("MobileSubstrate/DynamicLibraries", "TweakInject")}
    dylibs = [name for name in files if name.endswith(".dylib") and str(PurePosixPath(name).parent) in injection_dirs]
    if not dylibs:
        problems.append("未找到注入用 dylib")
    class_prefix = meta.get("class_prefix")
    if class_prefix and not any(PurePosixPath(n).name == class_prefix + ".dylib" for n in dylibs):
        problems.append("缺少 manifest 对应的注入 dylib")
    for name in dylibs:
        try:
            found = slices(files[name] or b"")
            print("  dylib: " + name + " -> " + ", ".join(found))
        except (ValueError, struct.error) as error:
            problems.append(name + ": " + str(error))
        try:
            data = load_plist(files, name[:-6] + ".plist")
            if "Filter" not in data or not isinstance(data["Filter"], dict):
                raise ValueError("缺少有效 Filter 字典")
            filters = data["Filter"]
            if not filters:
                if meta.get("allow_all_processes") is not True:
                    raise ValueError("空 Filter 必须由 manifest allow_all_processes=true 显式授权")
                print("  [WARN] 显式空 Filter，将注入所有进程: " + name)
            else:
                if set(filters) != {"Bundles"}:
                    raise ValueError("当前门禁仅支持 Bundles Filter；定制过滤条件需同步更新门禁")
                bundles = filters["Bundles"]
                if not isinstance(bundles, list) or not bundles or not all(isinstance(item, str) and item for item in bundles):
                    raise ValueError("Filter Bundles 必须为非空字符串列表")
                bundle = meta.get("bundle")
                if bundle and bundle not in bundles:
                    raise ValueError("Filter Bundles 与 manifest bundle 不一致")
        except Exception as error:
            problems.append(name + " Filter: " + str(error))
    prefs_base = prefix + "Library/PreferenceBundles/"
    loader_base = prefix + "Library/PreferenceLoader/Preferences/"
    entries = [name for name in files if name.startswith(loader_base) and name.endswith(".plist")]
    has_prefs = bool(entries or any(name.startswith(prefs_base) for name in files))
    enabled = bool(meta.get("preferences")) if manifest is not None else has_prefs or "preferenceloader" in depends
    if manifest is not None and not enabled and has_prefs:
        problems.append("manifest 未启用 preferences 但包内含面板")
    if enabled:
        needed.add("preferenceloader")
        expected_bundle = class_prefix + "Prefs" if class_prefix else None
        expected_entry = loader_base + expected_bundle + ".plist" if expected_bundle else None
        if not entries or expected_entry and expected_entry not in entries:
            problems.append("缺少 PreferenceLoader 入口")
        for name in entries:
            try:
                entry = load_plist(files, name).get("entry")
                if not isinstance(entry, dict):
                    raise ValueError("PreferenceLoader entry 缺失")
                bundle = entry.get("bundle")
                if not isinstance(bundle, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", bundle):
                    raise ValueError("PreferenceLoader bundle 非法")
                if expected_bundle and bundle != expected_bundle:
                    raise ValueError("PreferenceLoader bundle 与 manifest 不一致")
                base = prefs_base + bundle + ".bundle/"
                info = load_plist(files, base + "Info.plist")
                executable = info.get("CFBundleExecutable")
                if not isinstance(executable, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", executable):
                    raise ValueError("PreferenceBundle CFBundleExecutable 非法")
                if executable != bundle or info.get("CFBundlePackageType") != "BNDL":
                    raise ValueError("PreferenceBundle executable/type 不匹配")
                if not entry.get("detail") or info.get("NSPrincipalClass") != entry["detail"]:
                    raise ValueError("PreferenceBundle principal class 不匹配")
                if class_prefix and entry["detail"] != class_prefix + "RootListController":
                    raise ValueError("PreferenceLoader detail 与 manifest 不一致")
                if meta.get("package") and info.get("CFBundleIdentifier") != meta["package"] + ".preferences":
                    raise ValueError("PreferenceBundle identifier 不匹配")
                slices(files.get(base + executable) or b"", kinds=(6, 8))
                resource = base + (class_prefix + "Root.plist" if class_prefix else "Root.plist")
                if class_prefix:
                    resources = [resource]
                else:
                    resources = [n for n in files if n.startswith(base) and n.endswith(".plist") and n != base + "Info.plist"]
                if not resources:
                    raise ValueError("缺少 PreferenceBundle 配置 plist")
                for resource in resources:
                    if not isinstance(load_plist(files, resource).get("items"), list):
                        raise ValueError("PreferenceBundle plist 缺少 items")
            except Exception as error:
                problems.append(name + ": " + str(error))
    elif "preferenceloader" in depends:
        problems.append("preferences 未启用但含 preferenceloader 依赖")
    for dependency in sorted(needed - depends):
        problems.append("缺少必须依赖 " + dependency + "（不能由 alternatives 替代）")
    print(f"  包名: {package}  版本: {version}  架构: {architecture}  scheme: {scheme}")
    return problems


def validate_deb(path, *, manifest=None, scheme=None, expected_version=None):
    """返回错误列表；授权的空 Filter 打印 WARN。解析失败也作为错误返回。"""
    try:
        return _validate(path, manifest, scheme, expected_version)
    except Exception as error:
        return ["deb 解析失败: " + str(error)]


def check(path, *, manifest=None, scheme=None, expected_version=None):
    return validate_deb(path, manifest=manifest, scheme=scheme, expected_version=expected_version)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, help="含 tweak.json 的工程目录")
    parser.add_argument("--scheme", choices=sorted(ARCHITECTURES))
    parser.add_argument("--expected-version")
    parser.add_argument("paths", nargs="+", help="待核验 deb")
    args = parser.parse_args(argv)
    manifest = None
    if args.project:
        try:
            manifest = json.loads((args.project / "tweak.json").read_text(encoding="utf-8"))
            if not isinstance(manifest, dict):
                raise ValueError("tweak.json 根节点必须为 object")
        except Exception as error:
            print("[FAIL] 无法读取 project manifest: " + str(error))
            return 1
    failed = 0
    for path in args.paths:
        print(f"核验 {path}")
        problems = validate_deb(path, manifest=manifest, scheme=args.scheme, expected_version=args.expected_version)
        if problems:
            failed += 1
            for item in problems:
                print("  [FAIL] " + item)
        else:
            print("  [OK]")
    print(f"\n核验结果: {len(args.paths) - failed}/{len(args.paths)} 通过")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
