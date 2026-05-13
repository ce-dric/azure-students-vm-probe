# azure-students-vm-probe

Azure for Students 계정에서 실제로 VM을 배포할 수 있는 리전과 사이즈 조합을 자동으로 탐색하고, 첫 번째로 유효한 조합에 VM을 생성해주는 스크립트입니다.

## 배경

Azure for Students 구독은 리전별 쿼터 제한이 있어 VM을 배포하기 전까지 어떤 조합이 가능한지 알기 어렵습니다.  
이 스크립트는 ARM 템플릿 `validate`를 활용해 실제 과금 없이 배포 가능한 후보를 빠르게 찾아줍니다.

## 사전 조건

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) 설치 및 로그인 완료
  ```bash
  az login
  ```
- SSH 공개키 파일 존재 (기본값: `~/.ssh/id_ed25519.pub`)

## 빠른 시작

```bash
# 탐색만 수행 (VM 실제 생성 안 함)
DRY_RUN_ONLY=1 bash azure-students-vm-probe.sh

# 탐색 후 첫 번째 유효한 조합에 VM 바로 생성
bash azure-students-vm-probe.sh
```

## 동작 방식

1. 지정된 리전 목록을 순회하며 테스트용 리소스 그룹 생성
2. 각 리전에서 VM 사이즈 목록을 ARM 템플릿으로 **validate** (과금 없음)
3. 첫 번째로 유효한 리전 + 사이즈 조합 발견 시 탐색 종료
4. `DRY_RUN_ONLY=1`이 아니면 해당 조합으로 VM 1개를 실제 배포
5. 모든 결과를 TSV 파일로 저장

## 환경변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `REGIONS` | eastus, westus, japaneast, koreacentral 등 12개 | 탐색할 Azure 리전 목록 |
| `SIZES` | Standard_B1s, B1ls, B1ms, B2ats_v2, A1_v2 | 시도할 VM 사이즈 목록 |
| `ADMIN_USER` | `azureuser` | VM 관리자 계정명 |
| `SSH_PUBLIC_KEY_FILE` | `~/.ssh/id_ed25519.pub` | SSH 공개키 파일 경로 |
| `NAME_PREFIX` | `hermesbot` | 생성되는 리소스 이름 접두사 |
| `DRY_RUN_ONLY` | `0` | `1`로 설정 시 VM 생성 없이 탐색만 수행 |
| `KEEP_FAILED_RESOURCE_GROUPS` | `0` | `1`로 설정 시 실패한 리소스 그룹 유지 |
| `RESULTS_FILE` | `./azure-vm-probe-results.tsv` | 결과 저장 파일 경로 |

## 출력 예시

```
[2025-01-01 12:00:00 UTC] Subscription: Azure for Students (...), state=Enabled
[2025-01-01 12:00:05 UTC] Validating eastus / Standard_B1s
[2025-01-01 12:00:08 UTC] First deployable candidate: eastus / Standard_B1s
[2025-01-01 12:00:45 UTC] VM created.

RESOURCE_GROUP=aztest-eastus
LOCATION=eastus
SIZE=Standard_B1s
VM_NAME=hermesbot-eastus-standardb1s-vm
PUBLIC_IP=20.x.x.x
SSH=ssh -i ~/.ssh/id_ed25519 azureuser@20.x.x.x
```

```
Results:
REGION             SIZE                 STATUS     ERROR_CODE                         MESSAGE
------             ----                 ------     ----------                         -------
eastus             Standard_B1s         VALID
```

## 배포되는 Azure 리소스

VM 생성 시 다음 리소스가 함께 생성됩니다:

- **NSG**: SSH(포트 22) 인바운드 허용
- **VNet**: `10.42.0.0/16`
- **공인 IP**: Static, Standard SKU
- **NIC**
- **VM**: Ubuntu 22.04 LTS, OS 디스크 30GB (Standard_LRS)

## 특정 리전/사이즈만 탐색하기

```bash
REGIONS="koreacentral japaneast" \
SIZES="Standard_B1s Standard_B1ms" \
DRY_RUN_ONLY=1 \
bash azure-students-vm-probe.sh
```

## 주의사항

- 탐색 과정에서 리소스 그룹이 생성/삭제됩니다. `KEEP_FAILED_RESOURCE_GROUPS=1`로 유지할 수 있습니다.
- VM이 생성된 후에는 요금이 발생할 수 있습니다. 사용 후 리소스 그룹을 삭제하세요.
  ```bash
  az group delete --name <RESOURCE_GROUP> --yes
  ```

## 라이선스

MIT
