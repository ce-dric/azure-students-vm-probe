# azure-students-vm-probe

**Languages:** [한국어](README.ko.md) | [日本語](README.ja.md) | [中文](README.zh.md)

---

Automatically probe Azure for Students subscriptions to find deployable region/VM size combinations, then create a VM on the first valid candidate.

## Background

Azure for Students subscriptions have per-region quota limits that make it hard to know which combinations work without actually trying. This script uses ARM template `validate` to find a deployable candidate without incurring charges, then optionally deploys a single VM.

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) installed and logged in
  ```bash
  az login
  ```
- SSH public key file present (default: `~/.ssh/id_ed25519.pub`)

## Quick Start

```bash
# Probe only — no VM created
DRY_RUN_ONLY=1 bash azure-students-vm-probe.sh

# Probe and deploy a VM on the first valid candidate
bash azure-students-vm-probe.sh
```

## How It Works

1. Iterates over the configured region list and creates a test resource group per region
2. Validates an ARM template for each VM size without deploying (no charge)
3. Stops at the first valid region + size combination
4. If `DRY_RUN_ONLY` is not set, deploys exactly one VM with that combination
5. Writes all results to a TSV file

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REGIONS` | eastus, westus, japaneast, koreacentral, and 8 more | Space-separated list of Azure regions to probe |
| `SIZES` | Standard_B1s, B1ls, B1ms, B2ats_v2, A1_v2 | Space-separated list of VM sizes to try |
| `ADMIN_USER` | `azureuser` | VM administrator username |
| `SSH_PUBLIC_KEY_FILE` | `~/.ssh/id_ed25519.pub` | Path to SSH public key |
| `NAME_PREFIX` | `azvm` | Prefix for all created resource names |
| `DRY_RUN_ONLY` | `0` | Set to `1` to skip actual VM creation |
| `KEEP_FAILED_RESOURCE_GROUPS` | `0` | Set to `1` to retain resource groups after failed probes |
| `RESULTS_FILE` | `./azure-vm-probe-results.tsv` | Path for the TSV results file |

## Example Output

```
[2025-01-01 12:00:00 UTC] Subscription: Azure for Students (...), state=Enabled
[2025-01-01 12:00:05 UTC] Validating eastus / Standard_B1s
[2025-01-01 12:00:08 UTC] First deployable candidate: eastus / Standard_B1s
[2025-01-01 12:00:45 UTC] VM created.

RESOURCE_GROUP=aztest-eastus
LOCATION=eastus
SIZE=Standard_B1s
VM_NAME=azvm-eastus-standardb1s-vm
PUBLIC_IP=20.x.x.x
SSH=ssh -i ~/.ssh/id_ed25519 azureuser@20.x.x.x
```

```
Results:
REGION             SIZE                 STATUS     ERROR_CODE                         MESSAGE
------             ----                 ------     ----------                         -------
eastus             Standard_B1s         VALID
```

## Deployed Azure Resources

When a VM is created, the following resources are provisioned:

- **NSG**: allows inbound SSH (port 22)
- **VNet**: `10.42.0.0/16`
- **Public IP**: Static, Standard SKU
- **NIC**
- **VM**: Ubuntu 22.04 LTS, 30 GB OS disk (Standard_LRS)

## Probe a Specific Region or Size

```bash
REGIONS="koreacentral japaneast" \
SIZES="Standard_B1s Standard_B1ms" \
DRY_RUN_ONLY=1 \
bash azure-students-vm-probe.sh
```

## Notes

- Test resource groups are created and deleted during probing. Use `KEEP_FAILED_RESOURCE_GROUPS=1` to retain them for inspection.
- VMs incur charges after creation. Delete the resource group when done:
  ```bash
  az group delete --name <RESOURCE_GROUP> --yes
  ```

## Use as a k-skill

This repository includes a `SKILL.md` so you can load it as a [k-skill](https://github.com/NomaDamas/k-skill) and let Claude Code run the probe on your behalf.

**Install the skill:**

```bash
mkdir -p ~/.claude/skills/azure-students-vm-probe
cp SKILL.md ~/.claude/skills/azure-students-vm-probe/
```

**Then just ask Claude:**

> "Azure Student 계정에서 배포 가능한 리전 찾아줘"
> "Azure for Students로 VM 하나 만들어줘"

Claude will run the probe, report the results table, and optionally create the VM.

## License

MIT
