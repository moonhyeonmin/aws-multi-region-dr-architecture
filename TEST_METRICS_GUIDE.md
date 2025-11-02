# 테스트 메트릭 수집 가이드

이 가이드는 DR 테스트 결과를 수치화하여 회고 및 리포트에 활용하기 위한 방법을 설명합니다.

## 수치화 가능한 메트릭

### 1. RTO (Recovery Time Objective) - 복구 시간 목표

**의미**: 장애 발생부터 서비스 복구까지 걸리는 시간

**측정 방법**:
```bash
cd scripts
./test-failover-timing.sh
```

**측정 항목**:
- Health Check 실패 감지 시간
- DNS Failover 완료 시간
- 전체 RTO

**예상 수치 (테스트 환경)**:
- Health Check 감지: 30-90초
- DNS 전환: 2-3분
- 전체 RTO: 약 2-3분

**프로덕션 예상 수치**:
- 전체 RTO: 5-10분 (추가 검증, 모니터링, 승인 프로세스 고려)

---

### 2. RPO (Recovery Point Objective) - 복구 시점 목표

**의미**: 데이터 손실 허용 범위 (복제 지연 시간)

**측정 방법**:
```bash
cd scripts
./test-data-replication.sh
# 또는
./test-metrics.sh
```

**측정 항목**:
- 데이터 복제 지연 시간 (초)
- RDS 복제 지연 (Seconds Behind Master)

**예상 수치 (테스트 환경)**:
- 데이터 복제: 10-60초
- RDS 복제 지연: 5-30초

**프로덕션 예상 수치**:
- RPO: 10-30초 (네트워크 최적화 및 버퍼링 고려)

---

### 3. 성능 메트릭

**측정 항목**:
- Health Check 응답 시간
- API 응답 시간
- DNS 쿼리 시간

**측정 방법**:
```bash
cd scripts
./test-metrics.sh
```

**예상 수치**:
- Health Check: < 100ms
- API 응답: < 500ms
- DNS 쿼리: < 50ms

---

## 종합 테스트 리포트 생성

모든 메트릭을 한번에 수집:

```bash
cd scripts
./test-metrics.sh
```

이 스크립트는 다음 파일을 생성합니다:
- `dr-test-report-YYYYMMDD-HHMMSS.txt`: 텍스트 리포트
- `dr-test-report-YYYYMMDD-HHMMSS.json`: JSON 리포트

---

## 회고 작성 예시

### 실제 측정 결과 예시

```
[테스트 환경 측정 결과]

1. RTO (Recovery Time Objective)
   - Health Check 실패 감지: 45초
   - DNS Failover 완료: 180초 (3분)
   - 전체 RTO: 약 3분

2. RPO (Recovery Point Objective)
   - 데이터 복제 지연: 25초
   - RDS 복제 지연: 12초
   - 최대 RPO: 약 30초

3. 성능 메트릭
   - Health Check 응답: 85ms
   - API 응답 시간: 320ms
   - DNS 쿼리 시간: 28ms
```

### 회고 예시

```
## 테스트 결과 및 회고

본 프로젝트에서는 실제 금융사 재해복구 환경을 간소화하여 구현하고,
주요 DR 메트릭을 측정했습니다.

### 측정 결과

테스트 환경에서 측정한 주요 지표는 다음과 같습니다:

- **RTO**: 약 3분 (장애 감지부터 서비스 복구까지)
- **RPO**: 약 30초 (데이터 복제 지연 시간)
- **Health Check 응답 시간**: 평균 85ms
- **데이터 복제 완료 시간**: 평균 25초

### 프로덕션 환경 예상 및 고려사항

실제 프로덕션 환경에서는 다음과 같은 요인으로 인해 RTO가 증가할 것으로 예상됩니다:

1. **RTO 증가 요인** (3분 → 5-10분 예상)
   - Multi-AZ 구성으로 인한 추가 검증 시간
   - 운영팀 승인 프로세스 (Change Management)
   - 추가 모니터링 및 로그 확인 시간
   - 실제 트래픽 부하 시 성능 영향

2. **RPO 개선 가능성** (30초 → 10-20초 예상)
   - VPC Peering 또는 Transit Gateway로 네트워크 최적화
   - 전용 네트워크 연결 (Direct Connect 등)
   - 버퍼링 최적화

3. **추가 고려사항**
   - 실제 트래픽 부하 테스트 필요
   - 백업 및 스냅샷 전략 수립
   - 보안 강화 (WAF, Shield 등)
   - 자동화 스크립트 및 Runbook 작성

### 제한사항

본 테스트 환경은 다음과 같은 제한사항이 있습니다:
- 단일 AZ 구성 (프로덕션: Multi-AZ 필수)
- 최소 인스턴스 크기 사용
- Public RDS 사용 (프로덕션: Private 권장)
- 실제 트래픽 부하 미적용

이러한 제한사항으로 인해 실제 프로덕션 환경에서는 
추가적인 검증과 최적화가 필요할 것으로 판단됩니다.
```

---

## 추가 측정 항목 (선택)

### 트래픽 부하 테스트
```bash
# 간단한 부하 테스트
ab -n 1000 -c 10 http://$PRIMARY_IP/health
```

### 네트워크 지연 측정
```bash
# RDS 연결 테스트
time mysql -h $PRIMARY_RDS -u admin -p -e "SELECT 1"
time mysql -h $SECONDARY_RDS -u admin -p -e "SELECT 1"
```

---

## 리포트 활용 방법

1. **텍스트 리포트**: 회고 문서에 직접 복사/붙여넣기
2. **JSON 리포트**: 데이터 분석 및 시각화에 활용
3. **타이밍 리포트**: RTO 상세 분석에 활용

이러한 수치화된 결과를 바탕으로 실제 프로덕션 환경과의 차이점을
명확히 분석하고, 개선 방향을 제시할 수 있습니다.

