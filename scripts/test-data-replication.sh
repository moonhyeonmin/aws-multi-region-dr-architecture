#!/bin/bash
#
# RDS 데이터 복제 테스트 스크립트
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== RDS Cross-Region 복제 테스트 ===${NC}\n"

# Terraform outputs에서 정보 가져오기
if [ ! -f "../terraform/terraform.tfstate" ]; then
    echo -e "${RED}Error: terraform.tfstate 파일을 찾을 수 없습니다.${NC}"
    echo "먼저 terraform apply를 실행하세요."
    exit 1
fi

PRIMARY_IP=$(terraform -chdir=../terraform output -raw seoul_ec2_ip 2>/dev/null || echo "")
SECONDARY_IP=$(terraform -chdir=../terraform output -raw tokyo_ec2_ip 2>/dev/null || echo "")
PRIMARY_RDS=$(terraform -chdir=../terraform output -raw seoul_rds_endpoint 2>/dev/null || echo "")
SECONDARY_RDS=$(terraform -chdir=../terraform output -raw tokyo_rds_endpoint 2>/dev/null || echo "")

if [ -z "$PRIMARY_IP" ] || [ -z "$SECONDARY_IP" ]; then
    echo -e "${YELLOW}Warning: Terraform outputs를 가져올 수 없습니다. 수동으로 입력하세요.${NC}"
    read -p "Primary IP (Seoul): " PRIMARY_IP
    read -p "Secondary IP (Tokyo): " SECONDARY_IP
fi

echo -e "${BLUE}테스트 정보:${NC}"
echo "  Primary EC2: $PRIMARY_IP"
echo "  Secondary EC2: $SECONDARY_IP"
echo "  Primary RDS: $PRIMARY_RDS"
echo "  Secondary RDS: $SECONDARY_RDS"
echo ""

# 1. Primary에 데이터 작성
echo -e "${YELLOW}[1단계] Primary에 테스트 데이터 생성${NC}"
TEST_MESSAGE="DR-Test-$(date +%Y%m%d-%H%M%S)"

echo "메시지: $TEST_MESSAGE"
echo "Primary에 데이터 생성 중..."

CREATE_RESPONSE=$(curl -s -X POST http://$PRIMARY_IP/api/data \
    -H "Content-Type: application/json" \
    -d "{\"message\": \"$TEST_MESSAGE\"}")

if echo "$CREATE_RESPONSE" | grep -q '"status":"created"'; then
    CREATED_ID=$(echo "$CREATE_RESPONSE" | grep -o '"id":[0-9]*' | grep -o '[0-9]*' || echo "")
    echo -e "  ${GREEN}✓ 데이터 생성 성공 (ID: $CREATED_ID)${NC}"
    echo "  Response: $CREATE_RESPONSE"
else
    echo -e "  ${RED}✗ 데이터 생성 실패${NC}"
    echo "  Response: $CREATE_RESPONSE"
    exit 1
fi

echo ""
sleep 3

# 2. Primary에서 데이터 확인
echo -e "${YELLOW}[2단계] Primary에서 데이터 확인${NC}"
PRIMARY_DATA=$(curl -s http://$PRIMARY_IP/api/data)
PRIMARY_COUNT=$(echo "$PRIMARY_DATA" | grep -o '"count":[0-9]*' | grep -o '[0-9]*' || echo "0")

if echo "$PRIMARY_DATA" | grep -q "$TEST_MESSAGE"; then
    echo -e "  ${GREEN}✓ Primary에서 데이터 확인됨 (총 $PRIMARY_COUNT개)${NC}"
    echo "  최신 데이터:"
    echo "$PRIMARY_DATA" | grep -A 5 "$TEST_MESSAGE" | head -10
else
    echo -e "  ${RED}✗ Primary에서 데이터를 찾을 수 없음${NC}"
fi

echo ""
sleep 5

# 3. Secondary에서 복제 확인 (재시도 로직)
echo -e "${YELLOW}[3단계] Secondary에서 복제 데이터 확인${NC}"
echo "복제 지연을 고려하여 재시도합니다..."

MAX_RETRIES=12
RETRY_INTERVAL=10
FOUND=false

for i in $(seq 1 $MAX_RETRIES); do
    echo "[시도 $i/$MAX_RETRIES] Secondary 데이터 확인 중..."
    
    SECONDARY_DATA=$(curl -s http://$SECONDARY_IP/api/data || echo "")
    
    if echo "$SECONDARY_DATA" | grep -q "$TEST_MESSAGE"; then
        SECONDARY_COUNT=$(echo "$SECONDARY_DATA" | grep -o '"count":[0-9]*' | grep -o '[0-9]*' || echo "0")
        echo -e "  ${GREEN}✓ Secondary에서 복제된 데이터 확인됨 (총 $SECONDARY_COUNT개)${NC}"
        echo "  복제된 데이터:"
        echo "$SECONDARY_DATA" | grep -A 5 "$TEST_MESSAGE" | head -10
        FOUND=true
        break
    else
        echo "  데이터 복제 대기 중... ($((i * RETRY_INTERVAL))초 경과)"
        sleep $RETRY_INTERVAL
    fi
done

if [ "$FOUND" = false ]; then
    echo -e "  ${RED}✗ Secondary에서 데이터를 찾을 수 없음 (복제 실패 가능)${NC}"
    echo ""
    echo "복제 상태 확인:"
    REPLICATION_STATUS=$(curl -s http://$SECONDARY_IP/api/replication-status || echo "")
    echo "$REPLICATION_STATUS" | jq '.' || echo "$REPLICATION_STATUS"
fi

# 4. 복제 상태 확인
echo -e "\n${YELLOW}[4단계] 복제 상태 상세 확인${NC}"
REPLICATION_STATUS=$(curl -s http://$SECONDARY_IP/api/replication-status || echo "")

if [ -n "$REPLICATION_STATUS" ]; then
    echo "Secondary 복제 상태:"
    echo "$REPLICATION_STATUS" | jq '.' || echo "$REPLICATION_STATUS"
    
    IO_RUNNING=$(echo "$REPLICATION_STATUS" | grep -o '"slave_io_running":"[^"]*"' | cut -d'"' -f4 || echo "")
    SQL_RUNNING=$(echo "$REPLICATION_STATUS" | grep -o '"slave_sql_running":"[^"]*"' | cut -d'"' -f4 || echo "")
    BEHIND=$(echo "$REPLICATION_STATUS" | grep -o '"seconds_behind_master":[0-9]*' | grep -o '[0-9]*' || echo "")
    
    if [ "$IO_RUNNING" = "Yes" ] && [ "$SQL_RUNNING" = "Yes" ]; then
        echo -e "\n  ${GREEN}✓ 복제 정상 작동 중${NC}"
        if [ -n "$BEHIND" ]; then
            echo "  지연 시간: ${BEHIND}초"
        fi
    else
        echo -e "\n  ${YELLOW}⚠ 복제 상태 확인 필요${NC}"
        echo "  IO Running: $IO_RUNNING"
        echo "  SQL Running: $SQL_RUNNING"
    fi
else
    echo -e "  ${YELLOW}⚠ 복제 상태 정보를 가져올 수 없음${NC}"
fi

# 5. 최종 요약
echo -e "\n${BLUE}=== 테스트 요약 ===${NC}"
echo "테스트 메시지: $TEST_MESSAGE"
echo "Primary 데이터 확인: $([ "$FOUND" = true ] || echo "부분")"
if [ "$FOUND" = true ]; then
    echo -e "${GREEN}✓ 데이터 복제 테스트 성공${NC}"
else
    echo -e "${YELLOW}⚠ 데이터 복제 확인 불가 (추가 조사 필요)${NC}"
    echo ""
    echo "확인 사항:"
    echo "  1. RDS Read Replica가 정상적으로 생성되었는지 확인"
    echo "  2. 네트워크 연결 확인"
    echo "  3. 복제 상태 API 응답 확인"
fi

echo -e "\n${GREEN}테스트 완료!${NC}"

