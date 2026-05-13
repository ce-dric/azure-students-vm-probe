---
name: azure-students-vm-probe
description: Azure for Students 구독에서 배포 가능한 VM 리전/사이즈 조합을 ARM validate로 탐색하고, 첫 번째 유효한 후보에 VM을 생성한다.
license: MIT
metadata:
  category: cloud
  locale: ko-KR
  phase: v1
---

# Azure Students VM Probe

## What this skill does

Azure for Students 구독은 리전별 쿼터 제한으로 어떤 VM 사이즈가 어느 리전에서 가능한지 직접 배포해보기 전까지 알기 어렵다.
이 스킬은 ARM 템플릿 `validate`를 활용해 과금 없이 배포 가능한 리전 + 사이즈 조합을 탐색하고, 첫 번째 유효한 후보에 Ubuntu 22.04 LTS VM을 생성한다.

## When to use

- "Azure Student 계정에서 VM 만들어봐"
- "Azure for Students에서 배포 가능한 리전 찾아줘"
- "어느 리전에서 Standard_B1s가 되는지 확인해줘"
- "Azure 학생 계정으로 리눅스 서버 하나 띄워줘"

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) 설치 및 로그인
  ```bash
  az login
  ```
- SSH 공개키 파일 (`~/.ssh/id_ed25519.pub` 또는 `SSH_PUBLIC_KEY_FILE` 환경변수로 지정)
- `azure-students-vm-probe.sh` 스크립트 (이 레포에 포함)

## Required environment variables

- 없음 (기본값으로 동작)
- 선택 사항:

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `REGIONS` | eastus, westus, japaneast 등 12개 | 탐색할 리전 목록 |
| `SIZES` | Standard_B1s, B1ls, B1ms 등 5개 | 시도할 VM 사이즈 목록 |
| `DRY_RUN_ONLY` | `0` | `1`이면 VM 생성 없이 탐색만 |
| `SSH_PUBLIC_KEY_FILE` | `~/.ssh/id_ed25519.pub` | SSH 공개키 경로 |
| `NAME_PREFIX` | `azvm` | 리소스 이름 접두사 |

## Workflow

### 1. 스크립트 준비

스크립트가 없으면 다운로드한다.

```bash
curl -fsSL https://raw.githubusercontent.com/ce-dric/azure-students-vm-probe/main/azure-students-vm-probe.sh \
  -o azure-students-vm-probe.sh
chmod +x azure-students-vm-probe.sh
```

### 2. Azure CLI 로그인 확인

```bash
az account show --query "state" -o tsv
```

`Enabled`가 아니면 `az login`을 안내한다.

### 3. 탐색 먼저 실행 (DRY_RUN)

```bash
DRY_RUN_ONLY=1 bash azure-students-vm-probe.sh
```

결과 테이블에서 `VALID` 행을 확인한다.

### 4. VM 생성

탐색 결과가 만족스러우면 실제 VM을 생성한다.

```bash
bash azure-students-vm-probe.sh
```

출력된 `SSH=...` 명령으로 바로 접속할 수 있다.

### 5. 특정 리전/사이즈로 범위 좁히기

```bash
REGIONS="koreacentral japaneast" \
SIZES="Standard_B1s" \
bash azure-students-vm-probe.sh
```

## Done when

- `azure-vm-probe-results.tsv`에 각 리전/사이즈별 결과가 기록되어 있다
- `DRY_RUN_ONLY=1`이면 VALID 후보가 출력되고 VM은 생성되지 않았다
- VM 생성 시 `PUBLIC_IP`와 `SSH` 접속 명령이 출력되어 있다

## Failure modes

- 모든 리전/사이즈 조합이 `FAIL` — Azure for Students 쿼터 소진 또는 구독 만료
- `RG_FAIL` — 해당 리전에서 리소스 그룹 생성 자체가 불가 (리전 비활성화 또는 정책)
- SSH 공개키 파일 없음 — `SSH_PUBLIC_KEY_FILE` 경로 확인 필요
- Azure CLI 미로그인 — `az login` 실행 필요

## Notes

- VM 생성 후 요금이 발생하므로 사용 후 반드시 리소스 그룹을 삭제한다: `az group delete --name <RG> --yes`
- 탐색 중 생성된 테스트 리소스 그룹은 자동 삭제된다. `KEEP_FAILED_RESOURCE_GROUPS=1`로 유지할 수 있다.
- `jq` 없이 순수 `az` CLI와 `sed`만으로 동작한다.
