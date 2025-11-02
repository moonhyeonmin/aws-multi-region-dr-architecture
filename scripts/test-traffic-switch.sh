#!/bin/bash
#
# Route 53 트래픽 전환 테스트 스크립트
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Route 53 트래픽 전환 테스트 ===${NC}\n"

# Terraform outputs에서 정보 가져오기
if [ ! -f "../terraform/terraform.tfstate" ]; then
    echo -e "${RED}Error: terraform.tfstate 파일을 찾을 수 없습니다.${NC}"
    echo "먼저 terraform apply를 실행하세요."
    exit 1
fi

# Terraform outputs 추출
DOMAIN=$(terraform -chdir=../terraform output -raw route53_domain 2>/dev/null || echo "")
PRIMARY_IP=$(terraform -chdir=../terraform output -raw seoul_ec2_ip 2>/dev/null || echo "")
SECONDARY_IP=$(terraform -chdir=../terraform output -raw tokyo_ec2_ip 2>/dev/null || echo "")

if [ -z "$DOMAIN" ] || [ -z "$PRIMARY_IP" ] || [ -z "$SECONDARY_IP" ]; then
    echo -e "${YELLOW}Warning: Terraform outputs를 가져올 수 없습니다. 수동으로 입력하세요.${NC}"
    read -p "Domain name: " DOMAIN
    read -p "Primary IP (Seoul): " PRIMARY_IP
    read -p "Secondary IP (Tokyo): " SECONDARY_IP
fi

echo -e "\n${GREEN}테스트 정보:${NC}"
echo "  Domain: $DOMAIN"
echo "  Primary (Seoul): $PRIMARY_IP"
echo "  Secondary (Tokyo): $SECONDARY_IP"
echo ""

# 1. 초기 상태 확인
echo -e "${YELLOW}[1단계] 초기 상태 확인${NC}"
echo "Primary 리전 Health Check:"
PRIMARY_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://$PRIMARY_IP/health || echo "000")
if [ "$PRIMARY_HEALTH" = "200" ]; then
    echo -e "  ${GREEN}✓ Primary 건강 (HTTP $PRIMARY_HEALTH)${NC}"
else
    echo -e "  ${RED}✗ Primary 비정상 (HTTP $PRIMARY_HEALTH)${NC}"
fi

echo "Secondary 리전 Health Check:"
SECONDARY_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://$SECONDARY_IP/health || echo "000")
if [ "$SECONDARY_HEALTH" = "200" ]; then
    echo -e "  ${GREEN}✓ Secondary 건강 (HTTP $SECONDARY_HEALTH)${NC}"
else
    echo -e "  ${RED}✗ Secondary 비정상 (HTTP $SECONDARY_HEALTH)${NC}"
fi

echo ""
sleep 2

# 2. DNS 조회 확인
echo -e "${YELLOW}[2단계] DNS 조회 확인${NC}"
DNS_RESULT=$(dig +short $DOMAIN @8.8.8.8 2>/dev/null | head -1 || echo "")
if [ -n "$DNS_RESULT" ]; then
    echo "현재 DNS 해석 결과: $DNS_RESULT"
    if [ "$DNS_RESULT" = "$PRIMARY_IP" ]; then
        echo -e "  ${GREEN}✓ Primary로 트래픽 라우팅 중${NC}"
    elif [ "$DNS_RESULT" = "$SECONDARY_IP" ]; then
        echo -e "  ${YELLOW}⚠ Secondary로 트래픽 라우팅 중 (이미 전환됨)${NC}"
    else
        echo -e "  ${RED}✗ 예상과 다른 IP: $DNS_RESULT${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠ DNS 해석 불가 (Route 53 설정 확인 필요)${NC}"
fi
echo ""
sleep 3

# 3. Primary 장애 시뮬레이션
echo -e "${YELLOW}[3단계] Primary 장애 시뮬레이션${NC}"
echo "Primary EC2의 Security Group에서 HTTP 트래픽을 차단합니다."
echo -e "${RED}주의: 이 작업은 AWS CLI를 사용합니다.${NC}"
echo ""
read -p "Primary 장애를 시뮬레이션하시겠습니까? (y/N): " CONFIRM

if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
    echo "Security Group 규칙 제거 중..."
    # 여기서 실제로 Security Group 규칙을 수정할 수 있지만, 
    # 안전을 위해 수동으로 하도록 안내
    echo -e "${YELLOW}수동 작업 필요:${NC}"
    echo "1. AWS Console에서 Seoul 리전의 EC2 Security Group으로 이동"
    echo "2. Inbound 규칙에서 HTTP (80) 규칙을 제거하거나 임시로 차단"
    echo "3. Route 53 Health Check가 실패를 감지할 때까지 대기 (약 2-3분)"
    echo ""
    read -p "Security Group 규칙을 제거했으면 Enter를 누르세요..."
fi

# 4. Failover 확인
echo -e "\n${YELLOW}[4단계] Failover 확인 (약 2-3분 대기)${NC}"
echo "Route 53 Health Check가 실패를 감지하고 트래픽을 전환합니다..."
echo ""

MAX_WAIT=180  # 3분
ELAPSED=0
INTERVAL=10

while [ $ELAPSED -lt $MAX_WAIT ]; do
    DNS_RESULT=$(dig +short $DOMAIN @8.8.8.8 2>/dev/null | head -1 || echo "")
    
    if [ -n "$DNS_RESULT" ]; then
        if [ "$DNS_RESULT" = "$SECONDARY_IP" ]; then
            echo -e "${GREEN}✓ Failover 완료! 트래픽이 Secondary ($SECONDARY_IP)로 전환되었습니다.${NC}"
            break
        else
            echo "[$ELAPSED초] 아직 Primary ($DNS_RESULT)로 라우팅 중..."
        fi
    fi
    
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo -e "${RED}✗ Failover가 완료되지 않았습니다. Health Check 설정을 확인하세요.${NC}"
fi

# 5. 최종 확인
echo -e "\n${YELLOW}[5단계] 최종 확인${NC}"
FINAL_DNS=$(dig +short $DOMAIN @8.8.8.8 2>/dev/null | head -1 || echo "")
if [ "$FINAL_DNS" = "$SECONDARY_IP" ]; then
    echo -e "${GREEN}✓ 테스트 성공: 트래픽이 정상적으로 Secondary로 전환되었습니다.${NC}"
    echo ""
    echo "Secondary 응답 확인:"
    curl -s http://$SECONDARY_IP/health | jq '.' || curl -s http://$SECONDARY_IP/health
else
    echo -e "${YELLOW}현재 DNS: $FINAL_DNS${NC}"
fi

echo -e "\n${GREEN}테스트 완료!${NC}"

