#!/bin/bash
#
# Route 53 설정 확인 스크립트
#

BLUE='\033[0;34m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Route 53 설정 확인 ===${NC}\n"

cd "$(dirname "$0")/../terraform" || exit 1

DOMAIN=$(terraform output -raw route53_domain 2>/dev/null || echo "dr-test.local")
NAMESERVERS=$(terraform output -raw route53_name_servers 2>/dev/null || echo "")

if [ -z "$NAMESERVERS" ]; then
    echo -e "${YELLOW}Route 53 네임서버를 가져올 수 없습니다.${NC}"
    echo "AWS CLI로 확인하세요:"
    echo "  aws route53 list-hosted-zones --query 'HostedZones[?Name==\`dr-test.local.\`].Id' --output text"
    exit 1
fi

# 첫 번째 네임서버 사용
NS=$(echo "$NAMESERVERS" | head -1 | tr -d '[],"')

echo -e "${GREEN}Domain: $DOMAIN${NC}"
echo -e "${GREEN}Route 53 Name Server: $NS${NC}\n"

echo -e "${YELLOW}[1] Route 53 네임서버로 DNS 조회${NC}"
DNS_RESULT=$(dig +short @$NS $DOMAIN 2>/dev/null | head -1 || echo "")
if [ -n "$DNS_RESULT" ]; then
    echo -e "${GREEN}✓ DNS 해석: $DNS_RESULT${NC}"
else
    echo -e "${RED}✗ DNS 해석 실패${NC}"
fi

echo -e "\n${YELLOW}[2] 모든 Route 53 레코드 확인${NC}"
dig @$NS $DOMAIN ANY +noall +answer 2>/dev/null || echo "레코드 조회 실패"

echo -e "\n${YELLOW}[3] AWS CLI로 Route 53 레코드 확인${NC}"
ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='${DOMAIN}.'].Id" --output text 2>/dev/null | cut -d'/' -f3 || echo "")
if [ -n "$ZONE_ID" ]; then
    echo "Hosted Zone ID: $ZONE_ID"
    echo ""
    echo "레코드 목록:"
    aws route53 list-resource-record-sets --hosted-zone-id $ZONE_ID --query "ResourceRecordSets[?Type=='A']" --output table 2>/dev/null || echo "레코드 조회 실패"
else
    echo -e "${RED}Hosted Zone을 찾을 수 없습니다.${NC}"
fi

echo -e "\n${YELLOW}[4] Health Check 상태 확인${NC}"
HEALTH_CHECKS=$(aws route53 list-health-checks --query "HealthChecks[?contains(Tags[?Key=='Name'].Value, 'dr-test')].{ID:Id,Status:HealthCheckConfig.Type}" --output table 2>/dev/null || echo "")
if [ -n "$HEALTH_CHECKS" ]; then
    echo "$HEALTH_CHECKS"
else
    echo "Health Check를 찾을 수 없습니다."
fi

echo -e "\n${BLUE}=== 해결 방법 ===${NC}"
echo "1. Route 53 네임서버를 사용하여 DNS 조회:"
echo "   dig @$NS $DOMAIN"
echo ""
echo "2. 로컬 /etc/hosts에 추가 (임시):"
PRIMARY_IP=$(terraform output -raw seoul_ec2_ip 2>/dev/null || echo "")
if [ -n "$PRIMARY_IP" ]; then
    echo "   echo '$PRIMARY_IP $DOMAIN' | sudo tee -a /etc/hosts"
fi
echo ""
echo "3. 테스트 시 Route 53 네임서버 사용:"
echo "   dig @$NS $DOMAIN"

