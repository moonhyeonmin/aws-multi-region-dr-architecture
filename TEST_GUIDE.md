# DR 테스트 가이드

이 문서는 AWS 멀티리전 DR 환경의 테스트 방법을 설명합니다.

## 테스트 전 확인사항

### 1. 인프라 배포 확인

```bash
cd terraform
terraform output
```

다음 정보가 출력되어야 합니다:
- `seoul_ec2_ip`: 서울 리전 EC2 IP
- `tokyo_ec2_ip`: 도쿄 리전 EC2 IP
- `seoul_rds_endpoint`: 서울 리전 RDS 엔드포인트
- `tokyo_rds_endpoint`: 도쿄 리전 RDS 엔드포인트
- `route53_domain`: Route 53 도메인 이름

### 2. 웹 서버 동작 확인

```bash
# 서울 리전
curl http://$(terraform output -raw seoul_ec2_ip)/health

# 도쿄 리전
curl http://$(terraform output -raw tokyo_ec2_ip)/health
```

둘 다 `"status": "healthy"` 응답이 나와야 합니다.

### 3. RDS 복제 상태 확인

```bash
# 도쿄 리전에서 복제 상태 확인
curl http://$(terraform output -raw tokyo_ec2_ip)/api/replication-status
```

`slave_io_running`과 `slave_sql_running`이 모두 `"Yes"`여야 합니다.

## 테스트 시나리오

### 시나리오 1: Route 53 트래픽 전환 테스트

**목적**: Primary 리전 장애 시 자동으로 Secondary 리전으로 트래픽이 전환되는지 확인

#### 단계

1. **초기 상태 확인**
   ```bash
   cd scripts
   ./test-traffic-switch.sh
   ```

2. **Primary 장애 시뮬레이션**
   - AWS Console에서 Seoul 리전의 EC2 Security Group으로 이동
   - Inbound 규칙에서 HTTP (80) 규칙을 제거 또는 차단
   - 또는 스크립트 안내를 따라 진행

3. **Failover 확인**
   - 스크립트가 자동으로 DNS 전환을 확인합니다
   - 약 2-3분 내에 Secondary로 트래픽이 전환됩니다

4. **복구 테스트**
   - Security Group 규칙을 다시 추가
   - Health Check가 복구를 감지하면 다시 Primary로 트래픽이 돌아갑니다

#### 예상 결과

- Primary 장애 발생 시 Route 53이 자동으로 Secondary로 트래픽 전환
- DNS TTL(60초) 내에 전환이 완료됨
- Health Check가 정상화되면 자동으로 Primary로 복귀

---

### 시나리오 2: RDS 데이터 복제 테스트

**목적**: Primary RDS에 작성된 데이터가 Cross-Region Read Replica로 정상적으로 복제되는지 확인

#### 단계

1. **데이터 복제 테스트 실행**
   ```bash
   cd scripts
   ./test-data-replication.sh
   ```

2. **수동 테스트 (선택사항)**
   ```bash
   # Primary에 데이터 생성
   PRIMARY_IP=$(terraform -chdir=../terraform output -raw seoul_ec2_ip)
   curl -X POST http://$PRIMARY_IP/api/data \
     -H "Content-Type: application/json" \
     -d '{"message": "Test Message"}'

   # Secondary에서 데이터 확인 (복제 대기)
   SECONDARY_IP=$(terraform -chdir=../terraform output -raw tokyo_ec2_ip)
   sleep 10
   curl http://$SECONDARY_IP/api/data
   ```

#### 예상 결과

- Primary에 생성한 데이터가 10-30초 내에 Secondary에 복제됨
- Secondary에서 데이터 조회 가능 (Read Replica이므로 쓰기 불가)
- 복제 지연 시간(Seconds Behind Master) 확인 가능

---

### 시나리오 3: 장애 시뮬레이션

**목적**: 다양한 장애 시나리오를 통한 DR 전환 과정 확인

#### 방법 1: Security Group 규칙 제거 (권장)

```bash
cd scripts
./simulate-failure.sh
# 옵션 1 선택
```

- 가장 빠르고 안전한 방법
- 즉시 복구 가능

#### 방법 2: EC2 인스턴스 중지

```bash
# AWS CLI 사용
aws ec2 stop-instances \
  --instance-ids <SEOUL_INSTANCE_ID> \
  --region ap-northeast-2
```

- 인스턴스 재시작 필요 (1-2분 소요)
- 비용은 계속 발생

#### 방법 3: RDS 인스턴스 중지 (비추천)

- RDS 재시작에 시간이 오래 걸립니다 (10-15분)
- 테스트 환경에서는 권장하지 않습니다

---

## 수동 테스트 방법

### 1. Health Check 수동 확인

```bash
# Primary
curl http://<SEOUL_IP>/health | jq

# Secondary
curl http://<TOKYO_IP>/health | jq
```

### 2. 데이터 CRUD 테스트

```bash
PRIMARY_IP=$(terraform -chdir=terraform output -raw seoul_ec2_ip)
SECONDARY_IP=$(terraform -chdir=terraform output -raw tokyo_ec2_ip)

# Primary에 데이터 생성
curl -X POST http://$PRIMARY_IP/api/data \
  -H "Content-Type: application/json" \
  -d '{"message": "Manual Test"}'

# Primary에서 조회
curl http://$PRIMARY_IP/api/data | jq

# Secondary에서 조회 (복제 확인)
curl http://$SECONDARY_IP/api/data | jq
```

### 3. Route 53 DNS 확인

```bash
DOMAIN=$(terraform -chdir=terraform output -raw route53_domain)

# DNS 해석 확인
dig +short $DOMAIN @8.8.8.8

# 또는 nslookup
nslookup $DOMAIN 8.8.8.8
```

### 4. 복제 상태 상세 확인

```bash
SECONDARY_IP=$(terraform -chdir=terraform output -raw tokyo_ec2_ip)
curl http://$SECONDARY_IP/api/replication-status | jq
```

**중요 필드:**
- `slave_io_running`: "Yes" (복제 IO 스레드 실행 중)
- `slave_sql_running`: "Yes" (복제 SQL 스레드 실행 중)
- `seconds_behind_master`: 지연 시간 (초 단위)
- `master_host`: Primary RDS 주소

## 성능 기준

### 트래픽 전환

- **감지 시간**: Health Check 실패 후 약 30초-1분
- **전환 완료**: DNS TTL(60초) 고려 시 약 2-3분
- **목표**: 5분 이내 전환 완료

### 데이터 복제

- **일반 지연**: 10-30초
- **최대 지연**: 네트워크 상황에 따라 1분 이상 가능
- **목표**: 1분 이내 복제 완료

## 문제 해결

### 트래픽이 전환되지 않음

1. **Health Check 설정 확인**
   ```bash
   # AWS Console에서 Route 53 Health Check 확인
   # 또는 AWS CLI
   aws route53 list-health-checks
   ```

2. **Security Group 확인**
   - Route 53 Health Check IP 대역에서 접근 가능한지 확인
   - AWS Health Check IP: https://ip-ranges.amazonaws.com/ip-ranges.json

3. **웹 서버 로그 확인**
   ```bash
   ssh ec2-user@<EC2_IP>
   sudo journalctl -u flask-app -f
   ```

### 데이터 복제가 안 됨

1. **RDS 복제 상태 확인**
   ```bash
   aws rds describe-db-instances \
     --db-instance-identifier <REPLICA_ID> \
     --region ap-northeast-1
   ```

2. **네트워크 연결 확인**
   - VPC Peering 또는 Transit Gateway 필요 없음 (Public RDS 사용 시)
   - Security Group 규칙 확인

3. **RDS 로그 확인**
   ```bash
   aws rds describe-db-log-files \
     --db-instance-identifier <REPLICA_ID> \
     --region ap-northeast-1
   ```

### 웹 서버가 응답하지 않음

1. **인스턴스 상태 확인**
   ```bash
   aws ec2 describe-instance-status \
     --instance-ids <INSTANCE_ID> \
     --region ap-northeast-2
   ```

2. **애플리케이션 로그 확인**
   ```bash
   ssh ec2-user@<EC2_IP>
   sudo tail -f /var/log/user-data.log
   sudo systemctl status flask-app
   ```

3. **수동 재시작**
   ```bash
   sudo systemctl restart flask-app
   ```

## 테스트 체크리스트

- [ ] 인프라 배포 완료
- [ ] Primary 웹 서버 Health Check 통과
- [ ] Secondary 웹 서버 Health Check 통과
- [ ] RDS 복제 상태 정상
- [ ] Route 53 DNS 해석 확인
- [ ] 트래픽 전환 테스트 성공
- [ ] 데이터 복제 테스트 성공
- [ ] 장애 시뮬레이션 테스트 완료
- [ ] 리소스 정리 (`terraform destroy`)

## 주의사항

1. **비용 관리**
   - 테스트 완료 후 즉시 리소스 삭제
   - RDS 인스턴스를 중지하지 말고 삭제 (중지해도 비용 발생)

2. **보안**
   - Public RDS는 테스트 목적이며, 프로덕션에서는 사용하지 마세요
   - 비밀번호는 강력하게 설정하고 공유하지 마세요

3. **제한사항**
   - 이 환경은 테스트 목적으로만 사용하세요
   - 프로덕션 환경에서는 추가 보안 및 모니터링 설정이 필요합니다

