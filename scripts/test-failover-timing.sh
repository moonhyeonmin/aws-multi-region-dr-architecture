#!/bin/bash
#
# Failover 시간 측정 스크립트 (RTO 측정)
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Failover 시간 측정 (RTO) ===${NC}\n"

cd "$(dirname "$0")/../terraform" || exit 1
DOMAIN=$(terraform output -raw route53_domain 2>/dev/null || echo "")
PRIMARY_IP=$(terraform output -raw seoul_ec2_ip 2>/dev/null || echo "")
SECONDARY_IP=$(terraform output -raw tokyo_ec2_ip 2>/dev/null || echo "")

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Error: Domain을 가져올 수 없습니다.${NC}"
    exit 1
fi

cd "$(dirname "$0")"

TIMING_FILE="failover-timing-$(date +%Y%m%d-%H%M%S).txt"

echo "Failover 시간 측정을 시작합니다."
echo "이 스크립트는 다음 시간을 측정합니다:"
echo "  1. 장애 발생 감지 시간 (Health Check 실패 감지)"
echo "  2. DNS 전환 시간 (Failover 완료)"
echo ""
read -p "측정을 시작하시겠습니까? (y/N): " CONFIRM

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "취소되었습니다."
    exit 0
fi

# 초기 상태 확인
echo -e "\n${YELLOW}[초기 상태 확인]${NC}"
INITIAL_DNS=$(dig +short $DOMAIN @8.8.8.8 2>/dev/null | head -1 || echo "")
echo "초기 DNS 타겟: $INITIAL_DNS"

# Health Check 상태 확인
PRIMARY_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://$PRIMARY_IP/health 2>/dev/null || echo "000")
echo "Primary Health Check: $PRIMARY_HEALTH"

if [ "$PRIMARY_HEALTH" != "200" ]; then
    echo -e "${RED}Primary가 이미 비정상 상태입니다.${NC}"
    exit 1
fi

# 장애 시뮬레이션 안내
echo -e "\n${YELLOW}[장애 시뮬레이션 준비]${NC}"
echo "다음 단계를 수행하세요:"
echo "1. AWS Console에서 Seoul 리전의 EC2 Security Group으로 이동"
echo "2. Inbound 규칙에서 HTTP (80) 규칙을 제거하거나 차단"
echo ""
read -p "Security Group 규칙을 제거했으면 Enter를 누르세요..."

# 시간 측정 시작
FAILOVER_START=$(date +%s)
echo -e "\n${GREEN}시간 측정 시작: $(date '+%H:%M:%S')${NC}"

# Health Check 실패 감지 대기
echo -e "\n${YELLOW}[1단계] Health Check 실패 감지 대기${NC}"
HEALTH_FAIL_TIME=0
MAX_WAIT=300

for i in {1..60}; do
    sleep 5
    HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://$PRIMARY_IP/health 2>/dev/null || echo "000")
    
    if [ "$HEALTH" != "200" ]; then
        HEALTH_FAIL_TIME=$(date +%s)
        HEALTH_FAIL_DURATION=$((HEALTH_FAIL_TIME - FAILOVER_START))
        echo -e "  ${GREEN}✓ Health Check 실패 감지: ${HEALTH_FAIL_DURATION}초${NC}"
        break
    fi
    
    ELAPSED=$((i * 5))
    if [ $((ELAPSED % 30)) -eq 0 ]; then
        echo "  [${ELAPSED}초] Health Check 계속 확인 중..."
    fi
done

if [ $HEALTH_FAIL_TIME -eq 0 ]; then
    echo -e "  ${RED}✗ Health Check 실패 감지 타임아웃${NC}"
    HEALTH_FAIL_DURATION="TIMEOUT"
else
    HEALTH_FAIL_DURATION=$((HEALTH_FAIL_TIME - FAILOVER_START))
fi

# DNS 전환 확인
echo -e "\n${YELLOW}[2단계] DNS Failover 대기${NC}"
FAILOVER_COMPLETE_TIME=0
DNS_CHECK_COUNT=0

for i in {1..60}; do
    sleep 5
    DNS_CHECK_COUNT=$((DNS_CHECK_COUNT + 1))
    CURRENT_DNS=$(dig +short $DOMAIN @8.8.8.8 2>/dev/null | head -1 || echo "")
    
    if [ "$CURRENT_DNS" = "$SECONDARY_IP" ]; then
        FAILOVER_COMPLETE_TIME=$(date +%s)
        FAILOVER_DURATION=$((FAILOVER_COMPLETE_TIME - FAILOVER_START))
        echo -e "  ${GREEN}✓ Failover 완료: ${FAILOVER_DURATION}초${NC}"
        break
    fi
    
    ELAPSED=$((i * 5))
    if [ $((ELAPSED % 30)) -eq 0 ]; then
        echo "  [${ELAPSED}초] 현재 DNS: $CURRENT_DNS (대기 중...)"
    fi
done

if [ $FAILOVER_COMPLETE_TIME -eq 0 ]; then
    echo -e "  ${RED}✗ Failover 타임아웃${NC}"
    FAILOVER_DURATION="TIMEOUT"
else
    FAILOVER_DURATION=$((FAILOVER_COMPLETE_TIME - FAILOVER_START))
fi

# 최종 확인
echo -e "\n${YELLOW}[결과 요약]${NC}"
FINAL_DNS=$(dig +short $DOMAIN @8.8.8.8 2>/dev/null | head -1 || echo "")
SECONDARY_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://$SECONDARY_IP/health 2>/dev/null || echo "000")

echo "  최종 DNS 타겟: $FINAL_DNS"
echo "  Secondary Health Check: $SECONDARY_HEALTH"

# 리포트 생성
cat > "$TIMING_FILE" << EOF
========================================
Failover 시간 측정 리포트
생성 시간: $(date '+%Y-%m-%d %H:%M:%S')
========================================

[측정 결과]

1. Health Check 실패 감지 시간: ${HEALTH_FAIL_DURATION}초
2. DNS Failover 완료 시간: ${FAILOVER_DURATION}초

[타이밍 분석]
- 시작 시간: $(date -d "@$FAILOVER_START" '+%H:%M:%S')
EOF

if [ "$HEALTH_FAIL_DURATION" != "TIMEOUT" ]; then
    echo "- Health Check 실패: $(date -d "@$HEALTH_FAIL_TIME" '+%H:%M:%S')" >> "$TIMING_FILE"
fi

if [ "$FAILOVER_DURATION" != "TIMEOUT" ]; then
    echo "- Failover 완료: $(date -d "@$FAILOVER_COMPLETE_TIME" '+%H:%M:%S')" >> "$TIMING_FILE"
    echo "" >> "$TIMING_FILE"
    echo "[RTO 분석]" >> "$TIMING_FILE"
    echo "- 테스트 환경 RTO: ${FAILOVER_DURATION}초 (약 $((FAILOVER_DURATION / 60))분 $((FAILOVER_DURATION % 60))초)" >> "$TIMING_FILE"
    echo "- 프로덕션 예상 RTO: $((FAILOVER_DURATION * 2))-$((FAILOVER_DURATION * 3))초 (추가 검증 및 모니터링 고려)" >> "$TIMING_FILE"
fi

cat "$TIMING_FILE"
echo -e "\n${GREEN}리포트 파일: $TIMING_FILE${NC}"

