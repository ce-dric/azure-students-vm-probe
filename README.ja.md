# azure-students-vm-probe

**言語:** [English](README.md) | [한국어](README.ko.md) | [中文](README.zh.md)

---

Azure for Students サブスクリプションで VM をデプロイ可能なリージョンとサイズの組み合わせを自動的に探索し、最初の有効な候補に VM を作成するスクリプトです。

## 背景

Azure for Students サブスクリプションはリージョンごとにクォータ制限があり、実際に試してみるまでどの組み合わせが使えるかわかりません。このスクリプトは ARM テンプレートの `validate` を使い、課金なしでデプロイ可能な候補を探索し、必要に応じて VM を作成します。

## 前提条件

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) のインストールとログイン
  ```bash
  az login
  ```
- SSH 公開鍵ファイルが存在すること（デフォルト: `~/.ssh/id_ed25519.pub`）

## クイックスタート

```bash
# 探索のみ（VM は作成しない）
DRY_RUN_ONLY=1 bash azure-students-vm-probe.sh

# 探索後、最初の有効な候補に VM を作成
bash azure-students-vm-probe.sh
```

## 動作の流れ

1. 設定されたリージョン一覧を順に処理し、リージョンごとにテスト用リソースグループを作成
2. 各 VM サイズに対して ARM テンプレートの validate を実行（デプロイなし、課金なし）
3. 最初に有効なリージョン + サイズの組み合わせが見つかった時点で探索終了
4. `DRY_RUN_ONLY` が設定されていない場合、その組み合わせで VM を 1 台デプロイ
5. 全結果を TSV ファイルに保存

## 環境変数

| 変数 | デフォルト値 | 説明 |
|------|-------------|------|
| `REGIONS` | eastus, westus, japaneast, koreacentral など 12 リージョン | 探索する Azure リージョンのリスト（スペース区切り） |
| `SIZES` | Standard_B1s, B1ls, B1ms, B2ats_v2, A1_v2 | 試す VM サイズのリスト（スペース区切り） |
| `ADMIN_USER` | `azureuser` | VM 管理者ユーザー名 |
| `SSH_PUBLIC_KEY_FILE` | `~/.ssh/id_ed25519.pub` | SSH 公開鍵ファイルのパス |
| `NAME_PREFIX` | `azvm` | 作成するリソース名のプレフィックス |
| `DRY_RUN_ONLY` | `0` | `1` に設定すると VM を作成せず探索のみ実行 |
| `KEEP_FAILED_RESOURCE_GROUPS` | `0` | `1` に設定すると失敗したリソースグループを保持 |
| `RESULTS_FILE` | `./azure-vm-probe-results.tsv` | 結果を保存するファイルのパス |

## 出力例

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

## 作成される Azure リソース

VM 作成時に以下のリソースがプロビジョニングされます:

- **NSG**: SSH（ポート 22）のインバウンドを許可
- **VNet**: `10.42.0.0/16`
- **パブリック IP**: Static、Standard SKU
- **NIC**
- **VM**: Ubuntu 22.04 LTS、OS ディスク 30GB（Standard_LRS）

## 特定のリージョン・サイズのみ探索する

```bash
REGIONS="koreacentral japaneast" \
SIZES="Standard_B1s Standard_B1ms" \
DRY_RUN_ONLY=1 \
bash azure-students-vm-probe.sh
```

## 注意事項

- 探索中にテスト用リソースグループが作成・削除されます。`KEEP_FAILED_RESOURCE_GROUPS=1` で保持できます。
- VM 作成後は料金が発生します。使用後はリソースグループを削除してください:
  ```bash
  az group delete --name <RESOURCE_GROUP> --yes
  ```

## ライセンス

MIT
