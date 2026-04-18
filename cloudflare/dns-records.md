# PMOVES Cloudflare DNS Inventory

## Domain Mapping

| Subdomain | Target Service | Port | Tunnel Route | Status |
|-----------|---------------|------|-------------|--------|
| `headscale.pmoves.ai` | Headscale control plane | 8096 | Yes | Planned |
| `headscale-ui.pmoves.ai` | Headscale admin UI | 8196 | Yes | Planned |
| `api.pmoves.ai` | Agent Zero API | 8080 | Yes | Planned |
| `llm.pmoves.ai` | TensorZero Gateway | 3030 | Yes | Planned |
| `grafana.pmoves.ai` | Grafana dashboards | 3000 | Yes | Planned |
| `rag.pmoves.ai` | Hi-RAG v2 Gateway | 8086 | Yes | Planned |

## Notes

- All routes go through a single Cloudflare Tunnel
- The tunnel terminates at the VPS (Hostinger), which is on the tailnet
- Internal services are accessible via Tailscale IP or Docker network name
- TLS is terminated at Cloudflare edge; internal traffic is HTTP
- Update `tunnel-config.yml` when adding new services

## Cloudflare Zones

List your Cloudflare zones/domains here:

| Domain | Zone ID | Purpose |
|--------|---------|---------|
| `pmoves.ai` | `<ZONE_ID>` | Primary PMOVES domain |
| *(add more)* | | |
