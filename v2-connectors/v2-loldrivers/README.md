# LOLDrivers Connector for OpenCTI

## Overview

This connector imports **vulnerable and malicious Windows driver** data from [LOLDrivers](https://www.loldrivers.io/) (Living Off The Land Drivers) into OpenCTI.

LOLDrivers is a curated list of Windows drivers used by adversaries to bypass security controls and carry out attacks (BYOVD — Bring Your Own Vulnerable Driver).

## Data Source

- **API Endpoint**: `https://www.loldrivers.io/api/drivers.json` (public, no authentication required)
- **Data**: ~536 unique drivers with ~2000+ samples
- **Categories**: Vulnerable drivers and Malicious drivers
- **Update frequency**: Updated regularly by the community

## STIX Mapping

| LOLDrivers Concept | STIX Object | Description |
|---|---|---|
| Driver entry | `Malware` | Represents the driver threat |
| Driver sample (hash) | `Indicator` | STIX pattern with SHA-256/SHA-1/MD5 |
| Driver sample (hash) | `File` (observable) | File observable with hashes |
| Hash → Malware | `Relationship` (indicates) | Indicator indicates Malware |
| Indicator → Observable | `Relationship` (based-on) | Indicator based-on File |

## Configuration

### Environment Variables (secrets — put in `.env`)

| Variable | Required | Description |
|---|---|---|
| `OPENCTI_URL` | Yes | OpenCTI platform URL |
| `OPENCTI_TOKEN` | Yes | OpenCTI API token |
| `CONNECTOR_ID` | Yes | Unique connector UUID |

### Config File (`config.yml`)

| Parameter | Default | Description |
|---|---|---|
| `connector.duration_period` | `P1D` | Sync interval (ISO 8601) |
| `connector.relationship_delay` | `300` | Delay before sending relationships (seconds) |
| `loldrivers.api_url` | `https://www.loldrivers.io/api/drivers.json` | API endpoint |
| `loldrivers.request_timeout` | `60` | HTTP request timeout (seconds) |
| `loldrivers.import_malicious` | `true` | Import malicious drivers |
| `loldrivers.import_vulnerable` | `true` | Import vulnerable drivers |
| `loldrivers.bundle_size` | `50` | Drivers per STIX bundle |
| `loldrivers.create_indicators` | `true` | Create STIX Indicators |
| `loldrivers.create_observables` | `true` | Create File observables |

## Running

### Docker

```bash
docker build -t connector-loldrivers .
docker run --env-file ../.env connector-loldrivers
```

### Docker Compose

Add to `docker-compose-connector.yml`:

```yaml
connector-loldrivers:
  build: ./v2-loldrivers
  network_mode: host
  environment:
    - OPENCTI_URL=http://localhost:8080
    - OPENCTI_TOKEN=${OPENCTI_ADMIN_TOKEN}
    - CONNECTOR_ID=${CONNECTOR_LOLDRIVERS_ID}
    - CONNECTOR_TYPE=EXTERNAL_IMPORT
    - CONNECTOR_NAME=LOLDrivers
    - CONNECTOR_SCOPE=loldrivers
    - CONNECTOR_LOG_LEVEL=info
    - CONNECTOR_DURATION_PERIOD=P1D
  restart: always
```

### Local Development

```bash
cd v2-loldrivers
pip install -r requirements.txt
cd src
python __main__.py
```

## Authentication

**No authentication or API key is required.** The LOLDrivers API is fully public and free to use.

## Architecture

```
v2-loldrivers/
├── Dockerfile
├── config.yml
├── config.yml.sample
├── requirements.txt
├── README.md
└── src/
    ├── __main__.py              # Entry point
    ├── connector.py             # Main connector (3-step pipeline)
    ├── config.py                # Configuration loader
    ├── clients/
    │   └── loldrivers.py        # HTTP API client
    ├── parsers/
    │   └── driver.py            # Parse JSON → DriverEntry
    └── stix_builders/
        ├── indicator.py         # STIX Indicator from hashes
        ├── observable.py        # STIX File observable
        ├── malware.py           # STIX Malware for driver
        └── relationship.py      # based-on, indicates
```
