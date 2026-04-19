"""
IOC Label Mapper for Maltrail Connector.

Maps maltrail file-names to 16 IOC groups across 2 layers (dst-ioc / src-ioc).
Uses a hybrid approach:
  1. CSV lookup (pre-computed mapping for all known files)
  2. Rule-based fallback (regex patterns + known name sets + folder defaults)

Reference: v2-connectors/v2-maltrail/doc/IOC_Label.md

Usage (generate CSV from a cloned maltrail data directory):
  cd v2-connectors/v2-maltrail
  python -m src.trail.label_map --data-dir /opt/connector/data/maltrail/maltrail-new/ --stats

Options:
  --data-dir DIR    Scan maltrail data dir (malware/, malicious/, suspicious/, *.txt)
  --file-list FILE  TSV file with 'folder<TAB>filename' per line
  --output, -o      Output CSV path (default: data/ioc_label_mapping.csv)
  --stats           Print group distribution after generating
"""

from __future__ import annotations

import csv
import logging
import os
import re
from dataclasses import dataclass
from pathlib import Path

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class IOCGroupInfo:
    """Complete classification for one IOC file."""
    layer: str          # "dst-ioc" or "src-ioc"
    group: str          # e.g. "dst.malware", "src.scanner"
    score: int          # x_opencti_score (0-100)
    kill_chain: str     # MITRE ATT&CK phase_name
    tactic_id: str      # MITRE ATT&CK tactic ID, e.g. "TA0002"


# ---------------------------------------------------------------------------
# Score & Kill-chain mapping (16 groups)
# ---------------------------------------------------------------------------

GROUP_META: dict[str, IOCGroupInfo] = {
    "dst.malware":      IOCGroupInfo("dst-ioc", "dst.malware",      80, "execution",             "TA0002"),
    "dst.ransomware":   IOCGroupInfo("dst-ioc", "dst.ransomware",   95, "impact",                "TA0040"),
    "dst.rat":          IOCGroupInfo("dst-ioc", "dst.rat",          90, "command-and-control",   "TA0011"),
    "dst.stealer":      IOCGroupInfo("dst-ioc", "dst.stealer",      85, "credential-access",     "TA0006"),
    "dst.botnet":       IOCGroupInfo("dst-ioc", "dst.botnet",       85, "command-and-control",   "TA0011"),
    "dst.c2":           IOCGroupInfo("dst-ioc", "dst.c2",           90, "command-and-control",   "TA0011"),
    "dst.miner":        IOCGroupInfo("dst-ioc", "dst.miner",        60, "impact",                "TA0040"),
    "dst.exploit_kit":  IOCGroupInfo("dst-ioc", "dst.exploit_kit",  80, "initial-access",        "TA0001"),
    "dst.phishing":     IOCGroupInfo("dst-ioc", "dst.phishing",     75, "initial-access",        "TA0001"),
    "dst.anonymizer":   IOCGroupInfo("dst-ioc", "dst.anonymizer",   50, "defense-evasion",       "TA0005"),
    "dst.suspicious":   IOCGroupInfo("dst-ioc", "dst.suspicious",   40, "resource-development",  "TA0042"),
    "src.scanner":      IOCGroupInfo("src-ioc", "src.scanner",      60, "reconnaissance",        "TA0043"),
    "src.attacker":     IOCGroupInfo("src-ioc", "src.attacker",     90, "initial-access",        "TA0001"),
    "src.bot":          IOCGroupInfo("src-ioc", "src.bot",          55, "reconnaissance",        "TA0043"),
    "src.ddos":         IOCGroupInfo("src-ioc", "src.ddos",         85, "impact",                "TA0040"),
    "src.anonymizer":   IOCGroupInfo("src-ioc", "src.anonymizer",   50, "defense-evasion",       "TA0005"),
}

# ---------------------------------------------------------------------------
# Pattern rules (ordered by priority, first match wins)
# ---------------------------------------------------------------------------

_PATTERN_RULES: list[tuple[re.Pattern, str]] = [
    (re.compile(r"_ransomware$"),       "dst.ransomware"),
    (re.compile(r"rat$"),               "dst.rat"),
    (re.compile(r"_rat$"),              "dst.rat"),
    (re.compile(r"_stealer$"),          "dst.stealer"),
    (re.compile(r"stealer$"),           "dst.stealer"),
    (re.compile(r"_miner$"),            "dst.miner"),
    (re.compile(r"_c2$"),               "dst.c2"),
    (re.compile(r"c2$"),                "dst.c2"),       # e.g. shellcodec2, xiebroc2, aurac2
    (re.compile(r"^ek_"),               "dst.exploit_kit"),
    (re.compile(r"_tds$"),              "dst.exploit_kit"),
    (re.compile(r"_spamtool$"),         "dst.phishing"),
    (re.compile(r"_phishtool$"),        "dst.phishing"),
    (re.compile(r"_scamtool$"),         "dst.phishing"),
]

# ---------------------------------------------------------------------------
# Known-name sets (for names that don't match any pattern)
# ---------------------------------------------------------------------------

KNOWN_RANSOMWARE: set[str] = {
    "akira", "alphav", "avaddon", "avoslocker", "babuk", "blackbasta",
    "blackcat", "blackmatter", "cerber", "clop", "conti", "cuba",
    "darkside", "dharma", "egregor", "gandcrab", "hive", "lockbit",
    "lorenz", "lv", "maze", "medusa", "mespinoza", "nefilim",
    "netwalker", "nokoyawa", "phobos", "play", "pysa", "ragnarok",
    "ransomedvc", "revil", "rhysida", "royal", "ryuk", "sodinokibi",
    "stop", "teslacrypt", "trigona", "vice_society", "wannacry",
    # Additional well-known ransomware
    "8base", "almalocker", "astrolocker", "arcrypter", "arcusmedia",
    "arkana", "badrabbit", "bianlian", "bitpaymer", "blackbyte",
    "blackhunt", "blackkingdom", "bluesky", "braincipher",
    "cactus", "cicada3301", "cring", "crosslock",
    "cryptolocker", "cryptowall", "ctblocker", "daixin",
    "darkangels", "0mega",
}

KNOWN_RAT: set[str] = {
    "agenttesla", "remcos", "nanocore", "warzone", "adwind", "orcus",
    "gh0st", "xworm", "poison_ivy", "bitrat", "limerat", "dcrat",
    "venom", "havex",
    # Additional
    "avemaria", "darkcomet", "bifrost", "bandook",
}

KNOWN_STEALER: set[str] = {
    "redline", "vidar", "raccoon", "lumma", "formbook", "azorult",
    "predator", "pony", "loki", "aurora", "stealc", "rhadamanthys",
    "mystic", "risepro", "meduza",
    # Additional
    "44caliber", "agniane", "arkei", "baldr", "0bj3ctivity",
    "0xthief", "ailurophile", "album",
}

KNOWN_BOTNET: set[str] = {
    "mirai", "hajime", "bashlite", "gafgyt", "mozi", "tsunami",
    "kaiten", "zergeca", "emotet", "trickbot", "qakbot", "icedid",
    "bumblebee", "pikabot", "danabot", "amadey", "smokeloader",
    "guloader", "ursnif", "dridex", "zloader",
    # Additional
    "andromeda", "avalanche", "conficker", "cutwail", "bobax",
    "bondat", "bondnet", "bunitu",
}

KNOWN_C2: set[str] = {
    # From malicious/ folder
    "cobalt_strike", "havoc", "sliver", "mythic", "metasploit",
    "merlin_c2", "brute_ratel", "brc4", "nighthawk", "nimplant",
    "covenant", "viper", "interactsh", "ligolo_tunnel", "python_byob",
    "redguard", "redwarden", "spiderlabs_responder", "wraithnet",
    "coreimpact", "c2_panel", "elf_reversessh", "cyberstrikeai",
    # From malware/ folder (C2 tools filed as malware)
    "cobaltstrike", "cobaltstrike-1", "cobaltstrike-2",
    "archangelc2", "aurac2", "chaosc2",
}

KNOWN_PHISHING: set[str] = {
    "evilginx", "gophish", "georgeginx", "browser_locker", "scareware",
    "perswaysion", "install_capital", "install_cube", "pushbug",
    "katyabot", "supremebot", "sms_flooder", "woof",
}

KNOWN_EXPLOIT_KIT: set[str] = {
    "socgholish", "araneida",
}

# CMS injection / web shell (in malicious/ with *core suffix)
KNOWN_CMS_INJECT: set[str] = {
    "magentocore", "modxcore", "openxcore", "bitrixcore", "prestacore",
    "perfaudcore", "pinnaclecore", "robloxcore", "wp_inject",
}

# ---------------------------------------------------------------------------
# Explicit mapping for suspicious/ folder (28 files)
# ---------------------------------------------------------------------------

SUSPICIOUS_MAP: dict[str, str] = {
    "anonymous_web_proxy":    "dst.anonymizer",
    "i2p":                    "dst.anonymizer",
    "onion":                  "dst.anonymizer",
    "port_proxy":             "dst.anonymizer",
    "dns_tunneling_service":  "dst.anonymizer",
    "blockchain_dns":         "dst.anonymizer",
    "crypto_mining":          "dst.miner",
    "web_shells":             "dst.malware",
    "dprk_silivaccine":       "dst.malware",
    "superfish":              "dst.malware",
    "android_pua":            "dst.suspicious",
    "osx_pua":                "dst.suspicious",
    "pua":                    "dst.suspicious",
    "bad_history":            "dst.suspicious",
    "bad_wpad":               "dst.suspicious",
    "computrace":             "dst.suspicious",
    "connectwise":            "dst.suspicious",
    "dnspod":                 "dst.suspicious",
    "domain":                 "dst.suspicious",
    "dynamic_domain":         "dst.suspicious",
    "free_web_hosting":       "dst.suspicious",
    "ipinfo":                 "dst.suspicious",
    "meshagent":              "dst.suspicious",
    "nezha_rmmtool":          "dst.suspicious",
    "parking_site":           "dst.suspicious",
    "simplehelp":             "dst.suspicious",
    "suspended_domain":       "dst.suspicious",
    "xenarmor":               "dst.suspicious",
}

# ---------------------------------------------------------------------------
# Explicit mapping for malicious/ folder misc items
# ---------------------------------------------------------------------------

MALICIOUS_SPECIFIC: dict[str, str] = {
    "abcsoup":                "dst.malware",
    "android_goldoson":       "dst.malware",
    "android_hiddad":         "dst.malware",
    "arl":                    "dst.malware",
    "bad_proxy":              "dst.malware",
    "bad_script":             "dst.malware",
    "bad_service":            "dst.malware",
    "brchecker":              "dst.malware",
    "chromekatz":             "dst.stealer",
    "domain_shadowing":       "dst.malware",
    "filebroser":             "dst.malware",
    "msau_autouploader":      "dst.malware",
    "proxychanger":           "dst.malware",
    "rogue_dns":              "dst.malware",
}

# ---------------------------------------------------------------------------
# Root-level file mapping (external feeds)
# ---------------------------------------------------------------------------

ROOT_FILE_MAP: dict[str, str] = {
    "mass_scanner":       "src.scanner",
    "mass_scanner_cidr":  "src.scanner",
}

# ---------------------------------------------------------------------------
# Core mapping function
# ---------------------------------------------------------------------------

def classify(filename: str, folder: str) -> IOCGroupInfo:
    """
    Classify a maltrail file into one of 16 IOC groups.

    Args:
        filename: file stem without .txt (e.g. "emotet", "lockbit", "ek_rig")
        folder: source folder ("malware", "malicious", "suspicious", "root")

    Returns:
        IOCGroupInfo with layer, group, score, kill_chain
    """
    name = _normalize(filename)

    # 1. Root-level files (external feeds)
    if folder == "root":
        group = ROOT_FILE_MAP.get(name, "src.scanner")
        return GROUP_META[group]

    # 2. Suspicious/ — explicit table
    if folder == "suspicious":
        group = SUSPICIOUS_MAP.get(name, "dst.suspicious")
        return GROUP_META[group]

    # 3. Malicious/ — check specific overrides first
    if folder == "malicious":
        if name in MALICIOUS_SPECIFIC:
            return GROUP_META[MALICIOUS_SPECIFIC[name]]
        if name in KNOWN_PHISHING:
            return GROUP_META["dst.phishing"]
        if name in KNOWN_C2:
            return GROUP_META["dst.c2"]
        if name in KNOWN_CMS_INJECT:
            return GROUP_META["dst.malware"]
        if name in KNOWN_EXPLOIT_KIT:
            return GROUP_META["dst.exploit_kit"]

    # 4. Pattern rules (apply to all folders)
    for pattern, group in _PATTERN_RULES:
        if pattern.search(name):
            return GROUP_META[group]

    # 5. Known-name sets (no pattern match)
    if name in KNOWN_RANSOMWARE:
        return GROUP_META["dst.ransomware"]
    if name in KNOWN_RAT:
        return GROUP_META["dst.rat"]
    if name in KNOWN_STEALER:
        return GROUP_META["dst.stealer"]
    if name in KNOWN_BOTNET:
        return GROUP_META["dst.botnet"]
    if name in KNOWN_C2:
        return GROUP_META["dst.c2"]
    if name in KNOWN_PHISHING:
        return GROUP_META["dst.phishing"]
    if name in KNOWN_EXPLOIT_KIT:
        return GROUP_META["dst.exploit_kit"]

    # 6. Folder-level defaults
    if folder == "malware":
        return GROUP_META["dst.malware"]
    if folder == "malicious":
        return GROUP_META["dst.malware"]

    # 7. Absolute fallback
    return GROUP_META["dst.malware"]


def _normalize(name: str) -> str:
    """Normalize filename for matching: lowercase, strip variant suffixes."""
    name = name.lower().strip()
    # Strip variant suffixes like "-1", "-2" for matching
    # but keep the original for CSV lookup
    return name


# ---------------------------------------------------------------------------
# CSV-based lookup (primary path at runtime)
# ---------------------------------------------------------------------------

_CSV_CACHE: dict[str, IOCGroupInfo] | None = None
_CSV_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "data", "ioc_label_mapping.csv")


def _load_csv() -> dict[str, IOCGroupInfo]:
    """Load CSV mapping into memory. Key = 'folder/filename'."""
    global _CSV_CACHE
    if _CSV_CACHE is not None:
        return _CSV_CACHE

    _CSV_CACHE = {}
    csv_path = _CSV_PATH
    if not os.path.isfile(csv_path):
        logger.warning("CSV mapping not found at %s, using rule-based only", csv_path)
        return _CSV_CACHE

    with open(csv_path, encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            key = f"{row['folder']}/{row['filename']}"
            group = row["group"]
            if group in GROUP_META:
                _CSV_CACHE[key] = GROUP_META[group]

    logger.info("Loaded %d entries from CSV mapping", len(_CSV_CACHE))
    return _CSV_CACHE


def lookup(filename: str, folder: str) -> IOCGroupInfo:
    """
    Look up IOC group — CSV first, then rule-based fallback.

    This is the main entry point for the connector.
    """
    cache = _load_csv()
    key = f"{folder}/{filename}"
    if key in cache:
        return cache[key]

    # Fallback to rule-based classification
    result = classify(filename, folder)
    logger.debug("CSV miss for %s → rule-based: %s", key, result.group)
    return result


# ---------------------------------------------------------------------------
# CSV generation utility
# ---------------------------------------------------------------------------

def generate_csv(file_list: list[tuple[str, str]], output_path: str) -> int:
    """
    Generate CSV mapping from a list of (folder, filename) tuples.

    Args:
        file_list: list of (folder, filename) e.g. [("malware", "emotet"), ...]
        output_path: path to write CSV

    Returns:
        Number of rows written
    """
    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)

    rows = []
    for folder, filename in file_list:
        info = classify(filename, folder)
        rows.append({
            "folder": folder,
            "filename": filename,
            "layer": info.layer,
            "group": info.group,
            "score": info.score,
            "kill_chain": info.kill_chain,
        })

    # Sort: by folder, then by group, then by filename
    rows.sort(key=lambda r: (r["folder"], r["group"], r["filename"]))

    with open(output_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=["folder", "filename", "layer", "group", "score", "kill_chain"],
        )
        writer.writeheader()
        writer.writerows(rows)

    return len(rows)


# ---------------------------------------------------------------------------
# CLI: generate CSV from a file list or maltrail data directory
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import argparse
    import sys

    logging.basicConfig(level=logging.INFO, format="%(message)s")

    parser = argparse.ArgumentParser(
        description="Generate IOC label mapping CSV for maltrail files."
    )
    parser.add_argument(
        "--data-dir",
        help="Path to maltrail data dir (e.g. /opt/connector/data/maltrail/maltrail-new/)",
    )
    parser.add_argument(
        "--file-list",
        help="Path to TSV file with 'folder\\tfilename' per line",
    )
    parser.add_argument(
        "--output", "-o",
        default=_CSV_PATH,
        help="Output CSV path (default: data/ioc_label_mapping.csv)",
    )
    parser.add_argument(
        "--stats", action="store_true",
        help="Print group statistics after generating",
    )
    args = parser.parse_args()

    file_list: list[tuple[str, str]] = []

    if args.file_list:
        with open(args.file_list, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                parts = line.split("\t")
                if len(parts) == 2:
                    file_list.append((parts[0], parts[1]))
    elif args.data_dir:
        data_path = Path(args.data_dir)
        # Scan folders
        for folder_name in ["malware", "malicious", "suspicious"]:
            folder_path = data_path / folder_name
            if not folder_path.is_dir():
                continue
            for txt_file in sorted(folder_path.glob("*.txt")):
                file_list.append((folder_name, txt_file.stem))
        # Root-level files
        for txt_file in sorted(data_path.glob("*.txt")):
            file_list.append(("root", txt_file.stem))
    else:
        print("Error: provide --data-dir or --file-list", file=sys.stderr)
        sys.exit(1)

    count = generate_csv(file_list, args.output)
    print(f"Generated {count} rows → {args.output}")

    if args.stats:
        from collections import Counter
        stats: Counter[str] = Counter()
        for folder, filename in file_list:
            info = classify(filename, folder)
            stats[info.group] += 1
        print("\n--- Group Statistics ---")
        for group, cnt in sorted(stats.items(), key=lambda x: (-x[1], x[0])):
            meta = GROUP_META[group]
            print(f"  {group:<20s} {cnt:>5d}  (score={meta.score}, {meta.kill_chain})")
        print(f"  {'TOTAL':<20s} {sum(stats.values()):>5d}")
