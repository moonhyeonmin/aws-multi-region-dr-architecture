# AWS 멀티리전 DR 테스트 환경

금융사 재해복구센터 구축 및 전환 설계 과제를 위한 간소화된 AWS 멀티리전 DR 환경입니다.

## 개요

이 프로젝트는 다음과 같은 기능을 제공합니다:

- **멀티 리전 구성**: 서울(Primary)과 도쿄(DR) 리전에 인프라 구축
- **Route 53 기반 트래픽 전환**: Health Check 기반 자동 Failover
- **RDS Cross-Region 복제**: MySQL Read Replica를 통한 데이터 복제
- **간소화된 구성**: 비용 절감을 위한 최소 구성 (t3.micro, 단일 AZ)

## 아키텍처

```
┌─────────────────┐
│   Route 53      │ ← Health Check 기반 트래픽 전환
└────────┬────────┘
         │
    ┌────┴────┐
    │        │
┌───▼───┐ ┌───▼───┐
│ Seoul │ │ Tokyo │
│Primary│ │  DR   │
└───┬───┘ └───┬───┘
    │         │
    │    Cross-Region
    │    Replication
┌───▼───┐ ┌───▼───┐
│ RDS   │ │ RDS   │
│Primary│ │Replica│
└───────┘ └───────┘
```

## 구성 요소

### 인프라 (Terraform)

- **VPC 모듈**: VPC, Subnet, Internet Gateway 구성
- **EC2 모듈**: 웹 서버 인스턴스 및 Security Group
- **RDS 모듈**: MySQL Primary 및 Cross-Region Read Replica
- **Route 53 모듈**: Health Check 및 Failover 라우팅

### 애플리케이션

- **Flask 웹 서버**: Python 기반 웹 애플리케이션
  - Health Check 엔드포인트 (`/health`)
  - 데이터 CRUD API (`/api/data`)
  - 복제 상태 확인 API (`/api/replication-status`)

### 테스트 스크립트

- `test-traffic-switch.sh`: Route 53 트래픽 전환 테스트
- `test-data-replication.sh`: RDS 데이터 복제 확인 테스트
- `simulate-failure.sh`: Primary 장애 시뮬레이션

## 사전 요구사항

- AWS 계정 및 적절한 권한
- Terraform >= 1.0
- AWS CLI (선택사항, 스크립트 사용 시)
- jq (선택사항, JSON 파싱용)

## 설치 방법

### 1. 저장소 클론 (또는 다운로드)

```bash
cd aws-multi-region-dr-architecture
```

### 2. Terraform 변수 설정

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars 파일을 편집하여 db_password 등 설정
```

`terraform.tfvars` 예시:

```hcl
db_name     = "testdb"
db_username = "admin"
db_password = "YourSecurePassword123!"
domain_name = "dr-test.local"
```

### 3. Terraform 초기화 및 적용

```bash
# Terraform 초기화
terraform init

# 플랜 확인
terraform plan

# 인프라 배포 (약 15-20분 소요)
terraform apply
```

**주의사항:**
- RDS Cross-Region Read Replica 생성에는 시간이 걸립니다 (10-15분)
- 비용이 발생합니다 (t3.micro 기준 시간당 약 $0.01-0.02)
- 테스트 완료 후 반드시 `terraform destroy`를 실행하여 리소스를 정리하세요

### 4. 배포 확인

```bash
# 출력 확인
terraform output

# 서울 리전 웹 서버 확인
curl http://$(terraform output -raw seoul_ec2_ip)

# 도쿄 리전 웹 서버 확인
curl http://$(terraform output -raw tokyo_ec2_ip)
```

## 테스트 방법

자세한 테스트 방법은 [TEST_GUIDE.md](./TEST_GUIDE.md)를 참조하세요.

### 빠른 테스트

```bash
# 1. 트래픽 전환 테스트
cd scripts
./test-traffic-switch.sh

# 2. 데이터 복제 테스트
./test-data-replication.sh
```

## 주요 엔드포인트

### 웹 서버

- `http://<EC2_IP>/`: 메인 페이지
- `http://<EC2_IP>/health`: Health Check
- `http://<EC2_IP>/api/data` (GET): 데이터 조회
- `http://<EC2_IP>/api/data` (POST): 데이터 생성 (Primary만)
- `http://<EC2_IP>/api/replication-status` (GET): 복제 상태 (Replica만)

## 리소스 정리

**중요**: 테스트 완료 후 반드시 리소스를 삭제하세요.

```bash
cd terraform
terraform destroy
```

## 비용 추정

대략적인 월간 비용 (24시간 운영 기준):

- EC2 (t3.micro) x 2: ~$15
- RDS (db.t3.micro) x 2: ~$30
- Route 53: ~$0.50
- 데이터 전송: 사용량에 따라 다름

**총 예상 비용**: 월 약 $50-60 (테스트 환경)

실제 비용은 AWS Pricing Calculator를 사용하여 확인하세요.

## 제한사항

이 테스트 환경은 간소화된 구성이므로:

- 단일 Availability Zone (프로덕션에서는 다중 AZ 권장)
- 최소 인스턴스 크기 사용
- Multi-AZ RDS 비활성화
- 백업 및 모니터링 최소 구성

## 문제 해결

### RDS Read Replica 생성 실패

- Primary RDS가 완전히 생성된 후 Replica를 생성해야 합니다
- Terraform의 `depends_on`으로 순서를 보장합니다

### Health Check 실패

- Security Group에서 EC2로의 HTTP(80) 트래픽이 허용되어야 합니다
- 웹 서버가 정상적으로 시작되었는지 확인하세요:
  ```bash
  ssh ec2-user@<EC2_IP>
  sudo systemctl status flask-app
  ```

### 데이터 복제 지연

- Cross-Region 복제는 네트워크 지연이 있을 수 있습니다
- 일반적으로 몇 초에서 수십 초 내 복제됩니다

## 참고 자료

- [AWS Route 53 Health Checks](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/health-checks.html)
- [Amazon RDS Read Replicas](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ReadRepl.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

## 라이선스

이 프로젝트는 교육 및 테스트 목적으로 제공됩니다.

