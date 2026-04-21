
**Label format chuẩn:** `["v2secure", <connector>, "v2-ioc", info.layer, info.group, info.tactic_id]`

| Connector | Connector label | IOCGroupInfo | Labels ví dụ |
|---|---|---|---|
| **v2-maltrail** | `v2-malt` | `IOCGroupInfo` từ `label_map.lookup()` — dynamic theo từng file | `["v2secure", "v2-malt", "v2-ioc", "dst-ioc", "dst.ransomware", "TA0040"]` |
| **v2-botnet** | `v2-botnet` | `_IOC_INFO = IOCGroupInfo("src-ioc", "src.bot", 55, "reconnaissance", "TA0043")` | `["v2secure", "v2-botnet", "v2-ioc", "src-ioc", "src.bot", "TA0043"]` |
| **v2-driver** | `v2-driver` | `_MALICIOUS_INFO` hoặc `_VULNERABLE_INFO` lookup theo `driver.category` | `["v2secure", "v2-driver", "v2-ioc", "dst-ioc", "dst.malware", "TA0002"]` |
| **v2-nvd** | `v2-nvd` | Không phải IOC | `["v2secure", "v2-nvd"]` |

Tất cả `score`, `kill_chain_phases`, `labels` đều được derive từ `IOCGroupInfo` instance, không hardcode rời rạc.