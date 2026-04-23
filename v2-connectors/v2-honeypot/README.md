# V2Secure Honeypot Connector for OpenCTI

## Overview

This connector ingests **inbound source-IP observations** captured by the
V2Secure honeypot (CSV log `IP_Reputation.csv`) and pushes them into
OpenCTI as STIX `Indicator` + `IPv4-Addr` observables, following the
[V2 Secure IOC Label Classification](../docs/IOC_Label_Classification.md).

All honeypot IPs are **inbound** (lớp 2 — `src-ioc`).

## Data Source

CSV columns:

```
time, source_ip, ip_reputation, country, protocol, port
```

The `ip_reputation` value is mapped to one of the 5 `src-ioc` groups.

## STIX Mapping

| Honeypot Concept       | STIX Object          | Notes                                |
|------------------------|----------------------|--------------------------------------|
| `source_ip`            | `Indicator`          | Pattern `[ipv4-addr:value = '...']`  |
| `source_ip`            | `IPv4-Addr` (obs.)   | Observable, deterministic UUID       |
| Indicator → Observable | `Relationship`       | `based-on`                           |

## Reputation → IOC Group Mapping

| `ip_reputation`    | Layer    | Group            | Score | MITRE Tactic              |
|--------------------|----------|------------------|-------|---------------------------|
| `Mass Scanner`     | src-ioc  | `src.scanner`    | 60    | reconnaissance (TA0043)   |
| `Known Attacker`   | src-ioc  | `src.attacker`   | 90    | initial-access (TA0001)   |
| `Bot, Crawler`     | src-ioc  | `src.bot`        | 55    | reconnaissance (TA0043)   |
| `Tor Exit Node`    | src-ioc  | `src.anonymizer` | 50    | defense-evasion (TA0005)  |
| `Anonymizer`       | src-ioc  | `src.anonymizer` | 50    | defense-evasion (TA0005)  |
| *(unknown)*        | src-ioc  | `src.attacker`   | 90    | initial-access (TA0001)   |

## Labels

Each STIX object is tagged with a fixed 6-label scheme:

```
["v2secure", "v2-honeypot", "v2-ioc", <layer>, <group>, <tactic_id>]
```

Example: `["v2secure", "v2-honeypot", "v2-ioc", "src-ioc", "src.scanner", "TA0043"]`.

## Configuration

### Environment Variables (secrets — put in `.env`)

| Variable                | Required | Description                      |
|-------------------------|----------|----------------------------------|
| `OPENCTI_URL`           | Yes      | OpenCTI platform URL             |
| `OPENCTI_TOKEN`         | Yes      | OpenCTI API token                |
| `CONNECTOR_ID`          | Yes      | Unique connector UUID            |

### Config File (`config.yml`)

| Parameter                          | Default                                    | Description                              |
|------------------------------------|--------------------------------------------|------------------------------------------|
| `connector.duration_period`        | `PT30M`                                    | Sync interval (ISO 8601)                 |
| `connector.relationship_delay`     | `300`                                      | Delay before sending relationships (sec) |
| `honeypot.file_path`               | `/opt/connector/data/IP_Reputation.csv`    | Path to the honeypot CSV log             |
| `honeypot.bundle_size`             | `500`                                      | IOCs per STIX bundle                     |
| `honeypot.valid_days`              | `90`                                       | Indicator validity period (days)         |

## Running

### Docker Compose

The service is wired up in
[`v2-connectors/docker-compose-connector.yml`](../docker-compose-connector.yml)
as `connector-v2-honeypot`. Add `CONNECTOR_V2_HONEYPOT_ID` to your `.env`
and mount the CSV under `/opt/connector/data/honeypot/`:

```bash
docker compose -f docker-compose-connector.yml up -d connector-v2-honeypot
```

### Local Development

```bash
cd v2-honeypot
pip install -r requirements.txt
cd src
python __main__.py
```

## Architecture

```
v2-honeypot/
├── Dockerfile
├── config.yml
├── config.yml.sample
├── requirements.txt
├── README.md
├── data/
│   └── IP_Reputation.csv          # Sample honeypot log
└── src/
    ├── __main__.py                # Entry point
    ├── connector.py               # Main connector (2-step pipeline)
    ├── config.py                  # Configuration loader
    ├── parsers/
    │   └── honeypot.py            # CSV parsing + reputation classification
    └── stix_builders/
        ├── indicator.py           # STIX Indicator
        ├── observable.py          # STIX IPv4-Addr observable
        └── relationship.py        # based-on
```
