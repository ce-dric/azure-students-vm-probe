#!/usr/bin/env bash
set -euo pipefail

# Probe Azure for Students VM deployability across allowed lightweight regions/sizes.
# Uses az CLI only; jq is not required.
# It validates an ARM deployment for each region/size and creates only the first
# successful candidate unless DRY_RUN_ONLY=1 is set.

REGIONS="${REGIONS:-eastus eastus2 westus westus2 centralus southcentralus southeastasia japaneast japanwest koreacentral australiaeast francecentral}"
SIZES="${SIZES:-Standard_B1s Standard_B1ls Standard_B1ms Standard_B2ats_v2 Standard_A1_v2}"

ADMIN_USER="${ADMIN_USER:-azureuser}"
SSH_PUBLIC_KEY_FILE="${SSH_PUBLIC_KEY_FILE:-$HOME/.ssh/id_ed25519.pub}"
NAME_PREFIX="${NAME_PREFIX:-azvm}"
DRY_RUN_ONLY="${DRY_RUN_ONLY:-0}"
KEEP_FAILED_RESOURCE_GROUPS="${KEEP_FAILED_RESOURCE_GROUPS:-0}"

RESULTS_FILE="${RESULTS_FILE:-./azure-vm-probe-results.tsv}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$*"
}

safe_name() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-'
}

write_template() {
  local template_file="$1"
  cat >"$template_file" <<'JSON'
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": { "type": "string" },
    "vmSize": { "type": "string" },
    "adminUsername": { "type": "string" },
    "sshPublicKey": { "type": "string" },
    "namePrefix": { "type": "string" }
  },
  "variables": {
    "vnetName": "[concat(parameters('namePrefix'), '-vnet')]",
    "nsgName": "[concat(parameters('namePrefix'), '-nsg')]",
    "pipName": "[concat(parameters('namePrefix'), '-pip')]",
    "nicName": "[concat(parameters('namePrefix'), '-nic')]",
    "vmName": "[concat(parameters('namePrefix'), '-vm')]",
    "subnetName": "default"
  },
  "resources": [
    {
      "type": "Microsoft.Network/networkSecurityGroups",
      "apiVersion": "2023-09-01",
      "name": "[variables('nsgName')]",
      "location": "[parameters('location')]",
      "properties": {
        "securityRules": [
          {
            "name": "AllowSSH",
            "properties": {
              "priority": 1000,
              "protocol": "Tcp",
              "access": "Allow",
              "direction": "Inbound",
              "sourceAddressPrefix": "*",
              "sourcePortRange": "*",
              "destinationAddressPrefix": "*",
              "destinationPortRange": "22"
            }
          }
        ]
      }
    },
    {
      "type": "Microsoft.Network/virtualNetworks",
      "apiVersion": "2023-09-01",
      "name": "[variables('vnetName')]",
      "location": "[parameters('location')]",
      "properties": {
        "addressSpace": {
          "addressPrefixes": [ "10.42.0.0/16" ]
        },
        "subnets": [
          {
            "name": "[variables('subnetName')]",
            "properties": {
              "addressPrefix": "10.42.1.0/24",
              "networkSecurityGroup": {
                "id": "[resourceId('Microsoft.Network/networkSecurityGroups', variables('nsgName'))]"
              }
            }
          }
        ]
      },
      "dependsOn": [
        "[resourceId('Microsoft.Network/networkSecurityGroups', variables('nsgName'))]"
      ]
    },
    {
      "type": "Microsoft.Network/publicIPAddresses",
      "apiVersion": "2023-09-01",
      "name": "[variables('pipName')]",
      "location": "[parameters('location')]",
      "sku": {
        "name": "Standard"
      },
      "properties": {
        "publicIPAllocationMethod": "Static"
      }
    },
    {
      "type": "Microsoft.Network/networkInterfaces",
      "apiVersion": "2023-09-01",
      "name": "[variables('nicName')]",
      "location": "[parameters('location')]",
      "properties": {
        "ipConfigurations": [
          {
            "name": "ipconfig1",
            "properties": {
              "privateIPAllocationMethod": "Dynamic",
              "subnet": {
                "id": "[resourceId('Microsoft.Network/virtualNetworks/subnets', variables('vnetName'), variables('subnetName'))]"
              },
              "publicIPAddress": {
                "id": "[resourceId('Microsoft.Network/publicIPAddresses', variables('pipName'))]"
              }
            }
          }
        ]
      },
      "dependsOn": [
        "[resourceId('Microsoft.Network/virtualNetworks', variables('vnetName'))]",
        "[resourceId('Microsoft.Network/publicIPAddresses', variables('pipName'))]"
      ]
    },
    {
      "type": "Microsoft.Compute/virtualMachines",
      "apiVersion": "2023-09-01",
      "name": "[variables('vmName')]",
      "location": "[parameters('location')]",
      "properties": {
        "hardwareProfile": {
          "vmSize": "[parameters('vmSize')]"
        },
        "storageProfile": {
          "imageReference": {
            "publisher": "Canonical",
            "offer": "0001-com-ubuntu-server-jammy",
            "sku": "22_04-lts",
            "version": "latest"
          },
          "osDisk": {
            "createOption": "FromImage",
            "diskSizeGB": 30,
            "managedDisk": {
              "storageAccountType": "Standard_LRS"
            }
          }
        },
        "osProfile": {
          "computerName": "[variables('vmName')]",
          "adminUsername": "[parameters('adminUsername')]",
          "linuxConfiguration": {
            "disablePasswordAuthentication": true,
            "ssh": {
              "publicKeys": [
                {
                  "path": "[concat('/home/', parameters('adminUsername'), '/.ssh/authorized_keys')]",
                  "keyData": "[parameters('sshPublicKey')]"
                }
              ]
            }
          }
        },
        "networkProfile": {
          "networkInterfaces": [
            {
              "id": "[resourceId('Microsoft.Network/networkInterfaces', variables('nicName'))]"
            }
          ]
        }
      },
      "dependsOn": [
        "[resourceId('Microsoft.Network/networkInterfaces', variables('nicName'))]"
      ]
    }
  ],
  "outputs": {
    "vmName": {
      "type": "string",
      "value": "[variables('vmName')]"
    }
  }
}
JSON
}

extract_error_code() {
  local file="$1"
  local code
  code="$(sed -n 's/.*"code"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | head -n 1 || true)"
  if [ -z "$code" ]; then
    code="$(sed -n 's/.*Code:[[:space:]]*\([^ ]*\).*/\1/p' "$file" | head -n 1 || true)"
  fi
  printf '%s' "${code:-UNKNOWN}"
}

extract_error_message() {
  local file="$1"
  local msg
  msg="$(sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' "$file" | head -n 1 || true)"
  if [ -z "$msg" ]; then
    msg="$(tr '\n' ' ' <"$file" | sed 's/[[:space:]][[:space:]]*/ /g' | cut -c 1-220)"
  else
    msg="$(printf '%s' "$msg" | cut -c 1-220)"
  fi
  printf '%s' "$msg"
}

record_result() {
  local region="$1"
  local size="$2"
  local status="$3"
  local code="$4"
  local message="$5"

  printf '%s\t%s\t%s\t%s\t%s\n' "$region" "$size" "$status" "$code" "$message" >>"$RESULTS_FILE"
}

print_results_table() {
  echo
  echo "Results:"
  awk -F '\t' '
    BEGIN {
      printf "%-18s %-20s %-10s %-34s %s\n", "REGION", "SIZE", "STATUS", "ERROR_CODE", "MESSAGE"
      printf "%-18s %-20s %-10s %-34s %s\n", "------", "----", "------", "----------", "-------"
    }
    NR > 1 {
      printf "%-18s %-20s %-10s %-34s %s\n", $1, $2, $3, $4, $5
    }
  ' "$RESULTS_FILE"
}

cleanup_group() {
  local rg="$1"

  if [ "$KEEP_FAILED_RESOURCE_GROUPS" = "1" ]; then
    log "Keeping resource group: $rg"
    return 0
  fi

  az group delete --name "$rg" --yes --no-wait >/dev/null 2>&1 || true
}

main() {
  require_cmd az

  if [ ! -f "$SSH_PUBLIC_KEY_FILE" ]; then
    echo "SSH public key file not found: $SSH_PUBLIC_KEY_FILE" >&2
    exit 1
  fi

  local tmpdir template_file ssh_key subscription_id subscription_name subscription_state
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/azure-vm-probe.XXXXXX")"
  template_file="$tmpdir/template.json"
  write_template "$template_file"
  ssh_key="$(cat "$SSH_PUBLIC_KEY_FILE")"

  trap "rm -rf '$tmpdir'" EXIT

  subscription_id="$(az account show --query id -o tsv)"
  subscription_name="$(az account show --query name -o tsv)"
  subscription_state="$(az account show --query state -o tsv)"

  log "Subscription: $subscription_name ($subscription_id), state=$subscription_state"
  if [ "$subscription_state" != "Enabled" ]; then
    echo "Subscription is not Enabled; aborting." >&2
    exit 1
  fi

  log "Available physical locations in this cloud:"
  az account list-locations --query "[?metadata.regionType=='Physical'].name" -o tsv | sed 's/^/  - /'

  printf 'region\tsize\tstatus\terror_code\tmessage\n' >"$RESULTS_FILE"

  local found_region="" found_size="" found_rg="" found_prefix=""
  local region size rg prefix validate_out code msg

  for region in $REGIONS; do
    rg="aztest-$region"
    log "Ensuring test resource group: $rg ($region)"
    if ! az group create --name "$rg" --location "$region" -o none 2>"$tmpdir/group-$region.err"; then
      code="$(extract_error_code "$tmpdir/group-$region.err")"
      msg="$(extract_error_message "$tmpdir/group-$region.err")"
      for size in $SIZES; do
        record_result "$region" "$size" "RG_FAIL" "$code" "$msg"
      done
      cleanup_group "$rg"
      continue
    fi

    for size in $SIZES; do
      prefix="$(safe_name "${NAME_PREFIX}-${region}-${size}")"
      prefix="$(printf '%s' "$prefix" | cut -c 1-40)"
      validate_out="$tmpdir/validate-$region-$size.err"

      log "Validating $region / $size"
      if az deployment group validate \
        --resource-group "$rg" \
        --template-file "$template_file" \
        --parameters \
          location="$region" \
          vmSize="$size" \
          adminUsername="$ADMIN_USER" \
          sshPublicKey="$ssh_key" \
          namePrefix="$prefix" \
        -o none 2>"$validate_out"; then
        record_result "$region" "$size" "VALID" "" ""
        found_region="$region"
        found_size="$size"
        found_rg="$rg"
        found_prefix="$prefix"
        break 2
      fi

      code="$(extract_error_code "$validate_out")"
      msg="$(extract_error_message "$validate_out")"
      record_result "$region" "$size" "FAIL" "$code" "$msg"
    done

    cleanup_group "$rg"
  done

  print_results_table

  if [ -z "$found_region" ]; then
    log "No deployable candidate found."
    exit 2
  fi

  log "First deployable candidate: $found_region / $found_size"
  if [ "$DRY_RUN_ONLY" = "1" ]; then
    log "DRY_RUN_ONLY=1, skipping actual VM creation."
    echo "Candidate resource group: $found_rg"
    exit 0
  fi

  log "Creating exactly one VM for candidate $found_region / $found_size"
  az deployment group create \
    --resource-group "$found_rg" \
    --template-file "$template_file" \
    --parameters \
      location="$found_region" \
      vmSize="$found_size" \
      adminUsername="$ADMIN_USER" \
      sshPublicKey="$ssh_key" \
      namePrefix="$found_prefix" \
    -o none

  local vm_name public_ip
  vm_name="${found_prefix}-vm"
  public_ip="$(az vm show -d --resource-group "$found_rg" --name "$vm_name" --query publicIps -o tsv)"

  log "VM created."
  echo "RESOURCE_GROUP=$found_rg"
  echo "LOCATION=$found_region"
  echo "SIZE=$found_size"
  echo "VM_NAME=$vm_name"
  echo "PUBLIC_IP=$public_ip"
  echo "SSH=ssh -i ${SSH_PUBLIC_KEY_FILE%.pub} $ADMIN_USER@$public_ip"
}

main "$@"
