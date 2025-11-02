#!/bin/bash
#
# DR 테스트 메트릭 수집 및 리포트 생성 스크립트
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPORT_FILE="dr-test-report-$(date +%Y%m%d-%H%M%S).txt"
JSON_REPORT="dr-test-report-$(date +%Y%m%d-%H%M%S).json"

echo -e "${BLUE}=== DR 테스트 메트릭 수집 ===${NC}\n"

# Terraform outputs
cd "$(dirname "$0")/../terraform" || exit 1
PRIMARY_IP=$(terraform output -raw seoul_ec2_ip 2>/dev/null || echo "")
SECONDARY_IP=$(terraform output -raw tokyo_ec2_ip 2>/dev/null || echo "")
DOMAIN=$(terraform output -raw route53_domain 2>/dev/null || echo "")
PRIMARY_RDS=$(terraform output -raw seoul_rds_endpoint 2>/dev/null || echo "")
SECONDARY_RDS=$(terraform output -raw tokyo_rds_endpoint 2>/dev/null || echo "")

if [ -z "$PRIMARY_IP" ] || [ -z "$SECONDARY_IP" ]; then
    echo -e "${RED}Error: Terraform outputs를 가져올 수 없습니다.${NC}"
    exit 1
fi

cd "$(dirname "$0")"

# Initialize metrics
declare -A METRICS

echo "테스트 메트릭 수집 시작..."
echo "=========================================="

# 1. Health Check 응답 시간 측정
echo -e "\n${YELLOW}[1] Health Check 응답 시간 측정${NC}"
PRIMARY_HEALTH_TIME=$(curl -s -o /dev/null -w "%{time_total}" http://$PRIMARY_IP/health || echo "999")
SECONDARY_HEALTH_TIME=$(curl -s -o /dev/null -w "%{time_total}" http://$SECONDARY_IP/health || echo "999")

PRIMARY_HEALTH_TIME_MS=$(awk "BEGIN {printf \"%.0f\", $PRIMARY_HEALTH_TIME * 1000}")
SECONDARY_HEALTH_TIME_MS=$(awk "BEGIN {printf \"%.0f\", $SECONDARY_HEALTH_TIME * 1000}")

METRICS[primary_health_response_ms]=$PRIMARY_HEALTH_TIME_MS
METRICS[secondary_health_response_ms]=$SECONDARY_HEALTH_TIME_MS

echo "  Primary Health Check: ${PRIMARY_HEALTH_TIME_MS}ms"
echo "  Secondary Health Check: ${SECONDARY_HEALTH_TIME_MS}ms"

# 2. 데이터 복제 지연 시간 측정
echo -e "\n${YELLOW}[2] 데이터 복제 지연 시간 측정${NC}"
TEST_MESSAGE="Metric-Test-$(date +%Y%m%d-%H%M%S-%N | cut -b1-19)"

# Primary에 데이터 생성
CREATE_START=$(date +%s.%N)
CREATE_RESPONSE=$(curl -s -X POST http://$PRIMARY_IP/api/data \
    -H "Content-Type: application/json" \
    -d "{\"message\": \"$TEST_MESSAGE\"}")
CREATE_END=$(date +%s.%N)
    CREATE_TIME=$(awk "BEGIN {printf \"%.2f\", $CREATE_END - $CREATE_START}")

if echo "$CREATE_RESPONSE" | grep -q '"status":"created"'; then
    echo "  ✓ 데이터 생성 완료 (${CREATE_TIME}s)"
    
    # 복제 확인 (최대 60초 대기)
    REPLICATION_START=$(date +%s.%N)
    REPLICATION_TIME=0
    FOUND=false
    
    for i in {1..20}; do
        sleep 3
        SECONDARY_DATA=$(curl -s http://$SECONDARY_IP/api/data || echo "")
        
        if echo "$SECONDARY_DATA" | grep -q "$TEST_MESSAGE"; then
            REPLICATION_END=$(date +%s.%N)
            REPLICATION_TIME=$(awk "BEGIN {printf \"%.2f\", $REPLICATION_END - $REPLICATION_START}")
            FOUND=true
            break
        fi
        REPLICATION_TIME=$(awk "BEGIN {printf \"%.2f\", $(date +%s.%N) - $REPLICATION_START}")
    done
    
    if [ "$FOUND" = true ]; then
        REPLICATION_TIME_MS=$(awk "BEGIN {printf \"%.0f\", $REPLICATION_TIME * 1000}")
        METRICS[replication_lag_ms]=$REPLICATION_TIME_MS
        echo "  ✓ 데이터 복제 완료: ${REPLICATION_TIME}s (${REPLICATION_TIME_MS}ms)"
    else
        METRICS[replication_lag_ms]="TIMEOUT"
        echo "  ✗ 복제 타임아웃 (60초 이상)"
    fi
else
    echo "  ✗ 데이터 생성 실패"
    METRICS[replication_lag_ms]="ERROR"
fi

# 3. RDS 복제 지연 확인
echo -e "\n${YELLOW}[3] RDS 복제 지연 시간 확인${NC}"
REPLICATION_STATUS=$(curl -s http://$SECONDARY_IP/api/replication-status 2>/dev/null || echo "")
if [ -n "$REPLICATION_STATUS" ]; then
    BEHIND_MASTER=$(echo "$REPLICATION_STATUS" | grep -o '"seconds_behind_master":[0-9]*' | grep -o '[0-9]*' || echo "0")
    IO_RUNNING=$(echo "$REPLICATION_STATUS" | grep -o '"slave_io_running":"[^"]*"' | cut -d'"' -f4 || echo "")
    SQL_RUNNING=$(echo "$REPLICATION_STATUS" | grep -o '"slave_sql_running":"[^"]*"' | cut -d'"' -f4 || echo "")
    
    METRICS[rds_replication_lag_seconds]=$BEHIND_MASTER
    METRICS[rds_io_running]=$IO_RUNNING
    METRICS[rds_sql_running]=$SQL_RUNNING
    
    echo "  RDS 복제 지연: ${BEHIND_MASTER}초"
    echo "  IO Running: ${IO_RUNNING}"
    echo "  SQL Running: ${SQL_RUNNING}"
else
    METRICS[rds_replication_lag_seconds]="N/A"
    echo "  ⚠ 복제 상태 확인 불가"
fi

# 4. DNS 쿼리 시간 측정
echo -e "\n${YELLOW}[4] DNS 쿼리 응답 시간 측정${NC}"
if [ -n "$DOMAIN" ]; then
    DNS_START=$(date +%s.%N)
    DNS_RESULT=$(dig +short $DOMAIN @8.8.8.8 2>/dev/null | head -1 || echo "")
    DNS_END=$(date +%s.%N)
    DNS_QUERY_TIME=$(awk "BEGIN {printf \"%.3f\", $DNS_END - $DNS_START}")
    DNS_QUERY_TIME_MS=$(awk "BEGIN {printf \"%.0f\", $DNS_QUERY_TIME * 1000}")
    
    METRICS[dns_query_time_ms]=$DNS_QUERY_TIME_MS
    METRICS[current_dns_target]=$DNS_RESULT
    echo "  DNS 쿼리 시간: ${DNS_QUERY_TIME_MS}ms"
    echo "  현재 DNS 타겟: ${DNS_RESULT}"
else
    METRICS[dns_query_time_ms]="N/A"
fi

# 5. API 응답 시간 측정
echo -e "\n${YELLOW}[5] API 응답 시간 측정${NC}"
API_START=$(date +%s.%N)
API_RESPONSE=$(curl -s http://$PRIMARY_IP/api/data)
API_END=$(date +%s.%N)
API_TIME=$(awk "BEGIN {printf \"%.3f\", $API_END - $API_START}")
API_TIME_MS=$(awk "BEGIN {printf \"%.0f\", $API_TIME * 1000}")

METRICS[api_response_time_ms]=$API_TIME_MS
echo "  API 응답 시간: ${API_TIME_MS}ms"

# Generate Report
echo -e "\n${GREEN}=== 테스트 리포트 생성 ===${NC}\n"
cat > "$REPORT_FILE" << EOF
========================================
AWS Multi-Region DR 테스트 리포트
생성 시간: $(date '+%Y-%m-%d %H:%M:%S')
========================================

[테스트 환경 구성]
- Primary 리전: Seoul (ap-northeast-2)
- DR 리전: Tokyo (ap-northeast-1)
- Primary EC2 IP: $PRIMARY_IP
- Secondary EC2 IP: $SECONDARY_IP
- Primary RDS: $PRIMARY_RDS
- Secondary RDS: $SECONDARY_RDS

[성능 메트릭]

1. Health Check 응답 시간
   - Primary: ${METRICS[primary_health_response_ms]}ms
   - Secondary: ${METRICS[secondary_health_response_ms]}ms

2. 데이터 복제 지연 시간
   - 복제 완료 시간: ${METRICS[replication_lag_ms]}ms
   - RDS 복제 지연: ${METRICS[rds_replication_lag_seconds]}초
   - IO Thread: ${METRICS[rds_io_running]}
   - SQL Thread: ${METRICS[rds_sql_running]}

3. DNS 성능
   - DNS 쿼리 시간: ${METRICS[dns_query_time_ms]}ms
   - 현재 타겟: ${METRICS[current_dns_target]}

4. API 성능
   - API 응답 시간: ${METRICS[api_response_time_ms]}ms

[예상 RTO/RPO]

RTO (Recovery Time Objective):
- 테스트 환경: 약 2-3분 (Route 53 Health Check + DNS TTL)
- 예상 프로덕션: 5-10분 (추가 검증 및 모니터링 고려)

RPO (Recovery Point Objective):
- 테스트 환경: ${METRICS[rds_replication_lag_seconds]}초
- 예상 프로덕션: 10-30초 (네트워크 최적화 및 버퍼링 고려)

[제한사항 및 개선점]

1. 테스트 환경 제한사항:
   - 단일 AZ 구성 (프로덕션: Multi-AZ 권장)
   - 최소 인스턴스 크기 사용
   - Public RDS 사용 (프로덕션: Private 권장)
   - 최소 모니터링 구성

2. 프로덕션 환경 고려사항:
   - Multi-AZ 구성으로 가용성 향상
   - CloudWatch 알람 및 자동화 설정
   - VPC Peering/Transit Gateway 네트워크 최적화
   - 백업 및 스냅샷 전략 수립
   - 추가 보안 계층 (WAF, Shield 등)
   - 실제 트래픽 부하 테스트 필요

========================================
EOF

cat "$REPORT_FILE"

# Generate JSON report
cat > "$JSON_REPORT" << EOF
{
  "test_timestamp": "$(date -Iseconds)",
  "environment": {
    "primary_region": "ap-northeast-2",
    "dr_region": "ap-northeast-1",
    "primary_ec2_ip": "$PRIMARY_IP",
    "secondary_ec2_ip": "$SECONDARY_IP"
  },
  "metrics": {
    "primary_health_response_ms": ${METRICS[primary_health_response_ms]},
    "secondary_health_response_ms": ${METRICS[secondary_health_response_ms]},
    "replication_lag_ms": "${METRICS[replication_lag_ms]}",
    "rds_replication_lag_seconds": "${METRICS[rds_replication_lag_seconds]}",
    "rds_io_running": "${METRICS[rds_io_running]}",
    "rds_sql_running": "${METRICS[rds_sql_running]}",
    "dns_query_time_ms": "${METRICS[dns_query_time_ms]}",
    "api_response_time_ms": ${METRICS[api_response_time_ms]}
  },
  "estimated_rto": {
    "test_environment": "2-3 minutes",
    "production_estimate": "5-10 minutes"
  },
  "estimated_rpo": {
    "test_environment": "${METRICS[rds_replication_lag_seconds]} seconds",
    "production_estimate": "10-30 seconds"
  }
}
EOF

echo -e "\n${GREEN}리포트 파일:${NC}"
echo "  - 텍스트 리포트: $REPORT_FILE"
echo "  - JSON 리포트: $JSON_REPORT"

echo -e "\n${BLUE}테스트 완료!${NC}"

