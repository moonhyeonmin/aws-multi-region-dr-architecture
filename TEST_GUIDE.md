# DR 테스트 가이드

이 문서는 AWS 멀티리전 DR 환경의 테스트 방법, 메트릭 수집, 그리고 회고 작성을 위한 종합 가이드입니다.

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

---

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

---

## 테스트 메트릭 수집 (수치화)

회고 작성을 위해 테스트 결과를 수치화하여 수집합니다.

### 종합 메트릭 수집

모든 성능 메트릭을 한번에 수집하고 리포트 생성:

```bash
cd scripts
./test-metrics.sh
```

**생성되는 리포트:**
- `dr-test-report-YYYYMMDD-HHMMSS.txt`: 텍스트 리포트 (회고에 바로 사용 가능)
- `dr-test-report-YYYYMMDD-HHMMSS.json`: JSON 리포트 (데이터 분석용)

**측정 항목:**
1. Health Check 응답 시간 (Primary, Secondary)
2. 데이터 복제 지연 시간 (RPO 측정)
3. RDS 복제 지연 (Seconds Behind Master)
4. DNS 쿼리 응답 시간
5. API 응답 시간

---

### RTO (Recovery Time Objective) 측정

**의미**: 장애 발생부터 서비스 복구까지 걸리는 시간

**측정 방법:**
```bash
cd scripts
./test-failover-timing.sh
```

**측정 항목:**
- Health Check 실패 감지 시간
- DNS Failover 완료 시간
- 전체 RTO

**예상 수치 (테스트 환경):**
- Health Check 감지: 30-90초
- DNS 전환: 2-3분
- 전체 RTO: 약 2-3분

**프로덕션 예상 수치:**
- 전체 RTO: 5-10분 (추가 검증, 모니터링, 승인 프로세스 고려)

---

### RPO (Recovery Point Objective) 측정

**의미**: 데이터 손실 허용 범위 (복제 지연 시간)

**측정 방법:**
```bash
cd scripts
./test-data-replication.sh
# 또는
./test-metrics.sh
```

**측정 항목:**
- 데이터 복제 지연 시간 (초)
- RDS 복제 지연 (Seconds Behind Master)

**예상 수치 (테스트 환경):**
- 데이터 복제: 10-60초
- RDS 복제 지연: 5-30초

**프로덕션 예상 수치:**
- RPO: 10-30초 (네트워크 최적화 및 버퍼링 고려)

---

### 성능 메트릭 측정

**측정 항목:**
- Health Check 응답 시간
- API 응답 시간
- DNS 쿼리 시간

**예상 수치:**
- Health Check: < 100ms
- API 응답: < 500ms
- DNS 쿼리: < 50ms

---

## 성능 기준

### 트래픽 전환

- **감지 시간**: Health Check 실패 후 약 30초-1분
- **전환 완료**: DNS TTL(60초) 고려 시 약 2-3분
- **목표**: 5분 이내 전환 완료

### 데이터 복제

- **일반 지연**: 10-30초
- **최대 지연**: 네트워크 상황에 따라 1분 이상 가능
- **목표**: 1분 이내 복제 완료

---

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

---

## 회고 작성 가이드

테스트 결과를 바탕으로 회고를 작성할 때 활용할 수 있는 강조 포인트입니다.

### 테스트 환경 vs 프로덕션 환경 비교

| 항목 | 테스트 환경 | 프로덕션 환경 | 차이점 및 영향 |
|------|------------|-------------|---------------|
| **RTO** | 2-3분 | 5-10분 | 승인 프로세스, 검증 단계 추가로 증가 |
| **RPO** | 20-30초 | 10-30초 | 네트워크 최적화 시 개선 가능, 하지만 보안 강화로 지연 가능 |
| **AZ 구성** | 단일 AZ | Multi-AZ | 고가용성 향상, 하지만 복잡도 증가 |
| **보안** | Public RDS | Private RDS | 보안 강화, 하지만 네트워크 홉 증가 |
| **모니터링** | 수동 확인 | 자동화 알람 | 더 빠른 대응 가능, 하지만 설정 복잡도 증가 |
| **네트워크** | Internet 경유 | Direct Connect | 성능 향상, 비용 증가 |
| **비용** | 최소 구성 | 적절한 크기 | 실제 부하 처리 능력 확보 |

---

### 주요 강조 포인트

#### 1. 실제 측정된 수치 vs 프로덕션 예상 수치

**RTO (Recovery Time Objective)**
- **테스트 환경**: 약 2-3분
- **프로덕션 예상**: 5-10분
- **증가 요인**: 
  - 운영팀 승인 프로세스 및 Change Management
  - Multi-AZ 구성으로 인한 추가 검증 시간
  - 복잡한 네트워크 토폴로지로 인한 장애 진단 시간 증가
  - 실제 트래픽 부하 상황에서의 성능 검증 필요

**RPO (Recovery Point Objective)**
- **테스트 환경**: 약 20-30초
- **프로덕션 예상**: 10-30초 (최적화 시)
- **개선 가능성**: 
  - VPC Peering 또는 Direct Connect로 네트워크 최적화
  - 전용 네트워크 연결을 통한 지연 시간 감소
  - 하지만 Private RDS 사용으로 인한 추가 홉 증가 가능

---

#### 2. 테스트 환경의 제한사항

**아키텍처 복잡도**
- 단일 Availability Zone (프로덕션: Multi-AZ 필수)
- 최소 인스턴스 크기 사용 (t3.micro, db.t3.micro)
- Public RDS 사용 (프로덕션: Private 권장)
- 단순한 네트워크 구성

**프로덕션 환경 요구사항**
- Multi-AZ 구성 (고가용성)
- 적절한 인스턴스 크기 및 성능 튜닝
- Private RDS (보안 강화)
- 복잡한 네트워크 토폴로지 (VPC Peering, Transit Gateway)
- WAF, Shield 등 보안 계층 추가

---

#### 3. 실무에서 중요한 요소들

**트래픽 부하 고려**
- 테스트 환경: 단일 사용자 트래픽 시뮬레이션
- 프로덕션: 실제 사용자 트래픽 부하, 피크 타임 고려
- **영향**: 실제 트래픽 부하 상황에서는 복제 지연이 증가할 수 있음

**데이터 일관성 및 무결성**
- 테스트 환경: 단순한 테스트 데이터
- 프로덕션: 복잡한 트랜잭션, 외래키 제약조건
- **영향**: Cross-Region 복제 시 데이터 일관성 문제 가능

**네트워크 비용 및 성능**
- 테스트 환경: 최소한의 데이터 전송
- 프로덕션: Cross-Region 데이터 전송 비용, Direct Connect 등 전용선 고려
- **영향**: 실제 프로덕션에서는 Cross-Region 데이터 전송 비용이 매우 높을 수 있음

---

### 회고 작성 예시 구조

#### 서론
```
본 프로젝트는 금융사 재해복구센터 구축 과제로,
실제 프로덕션 환경을 완전히 구현하기보다는
핵심 DR 메커니즘의 흐름을 이해하고 검증하는 데 중점을 두었습니다.
```

#### 본문 1: 측정 결과
```
[실제 측정 수치]

테스트 환경에서 측정한 주요 지표:
- RTO: 약 3분 (장애 감지부터 서비스 복구까지)
- RPO: 약 30초 (데이터 복제 지연 시간)
- Health Check 응답: 평균 85ms
- 데이터 복제 완료: 평균 25초

이러한 수치는 최소 구성의 테스트 환경에서 얻은 것으로,
실제 프로덕션 환경에서는 여러 요인에 의해 달라질 수 있습니다.
```

#### 본문 2: 프로덕션 예상 및 차이점
```
[프로덕션 환경 예상]

1. RTO 증가 요인 (3분 → 5-10분 예상)
   - 운영팀 승인 프로세스 및 Change Management
   - Multi-AZ 구성으로 인한 추가 검증 시간
   - 복잡한 네트워크 토폴로지로 인한 장애 진단 시간 증가
   - 실제 트래픽 부하 상황에서의 성능 검증 필요

2. RPO 개선 가능성 (30초 → 10-20초 예상)
   - VPC Peering 또는 Direct Connect로 네트워크 최적화
   - 전용 네트워크 연결을 통한 지연 시간 감소
   - 하지만 Private RDS 사용으로 인한 추가 홉 증가 가능

3. 추가 고려사항
   - 실제 트래픽 부하 테스트 필요
   - 데이터 일관성 검증 프로세스 수립
   - 네트워크 비용 최적화 전략
   - 자동화된 Runbook 및 복구 프로세스
```

#### 본문 3: 제한사항 및 개선 방향
```
[테스트 환경의 제한사항]

본 테스트 환경은 다음 제한사항이 있습니다:
- 단일 AZ 구성 (프로덕션: Multi-AZ 필수)
- 최소 인스턴스 크기 사용
- Public RDS 사용 (프로덕션: Private 권장)
- 실제 트래픽 부하 미적용
- 최소 모니터링 구성

[실무 적용을 위한 개선 방향]

1. 인프라 레벨
   - Multi-AZ 구성으로 가용성 향상
   - 적절한 인스턴스 크기 및 Auto Scaling
   - Private RDS 및 VPC Endpoint 구성
   - Direct Connect 또는 VPC Peering 최적화

2. 운영 레벨
   - CloudWatch 알람 및 자동화 설정
   - SNS를 통한 즉시 알림
   - 자동화된 Runbook 작성
   - 정기적인 DR 훈련 및 테스트

3. 보안 레벨
   - WAF, Shield 등 보안 계층 추가
   - VPC Flow Logs 및 CloudTrail 로깅
   - 암호화 및 접근 제어 강화
```

#### 결론
```
[결론]

본 프로젝트를 통해 기본적인 DR 메커니즘의 동작 원리를 이해하고,
실제 수치를 측정하여 프로덕션 환경과의 차이점을 분석할 수 있었습니다.

테스트 환경에서 측정한 RTO 3분, RPO 30초는 최소 구성에서의 결과이며,
실제 프로덕션 환경에서는 보안, 고가용성, 모니터링 등 추가 요구사항으로 인해
RTO는 5-10분으로 증가할 것으로 예상됩니다.

하지만 프로덕션 환경에서는 네트워크 최적화(Direct Connect 등)를 통해
RPO를 10-20초로 개선할 수 있을 것으로 예상됩니다.

실무 적용 시에는 이러한 요소들을 모두 고려하여
단계적으로 개선해나가는 것이 중요할 것입니다.
```

---

## 회고 작성 시 체크리스트

- [ ] 실제 측정 수치 명시 (RTO, RPO 등)
- [ ] 테스트 환경의 제한사항 명확히 설명
- [ ] 프로덕션 환경과의 차이점 분석
- [ ] 예상되는 문제점 및 해결 방안 제시
- [ ] 비용 고려사항 언급
- [ ] 보안 강화 필요성 강조
- [ ] 실제 트래픽 부하 테스트의 필요성
- [ ] 단계적 개선 방향 제시
- [ ] 실무 적용 시 주의사항
- [ ] 학습한 점과 부족한 점 균형있게 서술

---

## 테스트 체크리스트

- [ ] 인프라 배포 완료
- [ ] Primary 웹 서버 Health Check 통과
- [ ] Secondary 웹 서버 Health Check 통과
- [ ] RDS 복제 상태 정상
- [ ] Route 53 DNS 해석 확인
- [ ] 트래픽 전환 테스트 성공
- [ ] 데이터 복제 테스트 성공
- [ ] 장애 시뮬레이션 테스트 완료
- [ ] 메트릭 수집 및 리포트 생성 (`./test-metrics.sh`)
- [ ] RTO 측정 완료 (`./test-failover-timing.sh`)
- [ ] 리소스 정리 (`terraform destroy`)

---

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

---

## 추가 참고 자료

### 리포트 파일 위치
- 메트릭 리포트: `scripts/dr-test-report-*.txt`
- Failover 타이밍 리포트: `scripts/failover-timing-*.txt`
- JSON 리포트: `scripts/dr-test-report-*.json`

### 회고 작성 팁
1. **객관적 수치 중심**: 추상적 표현보다 측정된 수치 사용
2. **비교 분석**: 테스트 vs 프로덕션 비교로 깊이 있게 서술
3. **건설적 비판**: 제한사항을 인정하되, 개선 방향 제시
4. **실무 적용성**: 이론이 아닌 실제 적용 가능한 인사이트 제공
5. **균형잡힌 시각**: 잘한 점과 부족한 점 모두 언급
