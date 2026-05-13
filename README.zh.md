# azure-students-vm-probe

**语言:** [English](README.md) | [한국어](README.ko.md) | [日本語](README.ja.md)

---

自动探测 Azure for Students 订阅中可部署 VM 的区域和规格组合，并在第一个有效候选上创建虚拟机。

## 背景

Azure for Students 订阅在各区域存在配额限制，在实际尝试之前很难知道哪些组合可用。此脚本利用 ARM 模板的 `validate` 功能，在不产生费用的情况下探测可部署的候选项，并可选择性地创建 VM。

## 前提条件

- 已安装 [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) 并完成登录
  ```bash
  az login
  ```
- SSH 公钥文件存在（默认：`~/.ssh/id_ed25519.pub`）

## 快速开始

```bash
# 仅探测（不创建 VM）
DRY_RUN_ONLY=1 bash azure-students-vm-probe.sh

# 探测后在第一个有效候选上创建 VM
bash azure-students-vm-probe.sh
```

## 工作原理

1. 遍历配置的区域列表，为每个区域创建测试资源组
2. 对每个 VM 规格执行 ARM 模板 validate（无实际部署，无费用）
3. 找到第一个有效的区域 + 规格组合后停止探测
4. 若未设置 `DRY_RUN_ONLY`，则使用该组合部署一台 VM
5. 将所有结果写入 TSV 文件

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `REGIONS` | eastus、westus、japaneast、koreacentral 等 12 个区域 | 要探测的 Azure 区域列表（空格分隔） |
| `SIZES` | Standard_B1s、B1ls、B1ms、B2ats_v2、A1_v2 | 要尝试的 VM 规格列表（空格分隔） |
| `ADMIN_USER` | `azureuser` | VM 管理员用户名 |
| `SSH_PUBLIC_KEY_FILE` | `~/.ssh/id_ed25519.pub` | SSH 公钥文件路径 |
| `NAME_PREFIX` | `azvm` | 创建的资源名称前缀 |
| `DRY_RUN_ONLY` | `0` | 设为 `1` 时仅探测，不创建 VM |
| `KEEP_FAILED_RESOURCE_GROUPS` | `0` | 设为 `1` 时保留探测失败的资源组 |
| `RESULTS_FILE` | `./azure-vm-probe-results.tsv` | 结果文件路径 |

## 输出示例

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

## 创建的 Azure 资源

创建 VM 时，将同时部署以下资源：

- **NSG**：允许 SSH（端口 22）入站
- **VNet**：`10.42.0.0/16`
- **公共 IP**：静态，Standard SKU
- **NIC**
- **VM**：Ubuntu 22.04 LTS，OS 磁盘 30GB（Standard_LRS）

## 仅探测特定区域或规格

```bash
REGIONS="koreacentral japaneast" \
SIZES="Standard_B1s Standard_B1ms" \
DRY_RUN_ONLY=1 \
bash azure-students-vm-probe.sh
```

## 注意事项

- 探测过程中会创建并删除测试资源组。使用 `KEEP_FAILED_RESOURCE_GROUPS=1` 可保留它们以供检查。
- VM 创建后将产生费用。使用完毕后请删除资源组：
  ```bash
  az group delete --name <RESOURCE_GROUP> --yes
  ```

## 许可证

MIT
