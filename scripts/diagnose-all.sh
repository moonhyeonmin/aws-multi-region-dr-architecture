#!/bin/bash
#
# 전체 인프라 진단 스크립트
#

set -e

BLUE='\033[0;34m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== 전체 인프라 진단 ===${NC}\n"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

cd "$TERRAFORM_DIR" || {
    echo -e "${RED}Error: terraform 디렉토리를 찾을 수 없습니다.${NC}"
    exit 1
}

# Terraform outputs 가져오기
echo -e "${YELLOW}[정보 수집 중...]${NC}\n"

SEoul_IP=$(terraform output -raw seoul_ec2_ip 2>/dev/null || echo "")
TOKYO_IP=$(terraform output -raw tokyo_ec2_ip 2>/dev/null || echo "")
SEoul_RDS=$(terraform output -raw seoul_rds_endpoint 2>/dev/null || echo "")
TOKYO_RDS=$(terraform output -raw tokyo_rds_endpoint 2>/dev/null || echo "")
DOMAIN=$(terraform output -raw route53_domain 2>/dev/null || echo "dr-test.local")
NAMESERVERS=$(terraform output route53_name_servers 2>/dev/null || echo "")

if [ -z "$SEoul_IP" ] || [ -z "$TOKYO_IP" ]; then
    echo -e "${RED}✗ Terraform outputs를 가져올 수 없습니다.${NC}"
    exit 1
fi

# ============================================
# 1. EC2 인스턴스 상태
# ============================================
echo -e "${BLUE}[1] EC2 인스턴스 상태 확인${NC}"

echo -e "\n${YELLOW}서울 리전 (Primary)${NC}"
echo "IP: $SEoul_IP"

# 네트워크 연결
if ping -c 1 -W 2 $SEoul_IP > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓ 네트워크 연결: OK${NC}"
else
    echo -e "  ${RED}✗ 네트워크 연결: FAIL${NC}"
fi

# HTTP 응답
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 http://$SEoul_IP/health 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo -e "  ${GREEN}✓ HTTP 응답: OK (HTTP $HTTP_CODE)${NC}"
elif [ "$HTTP_CODE" = "000" ]; then
    echo -e "  ${RED}✗ HTTP 응답: FAIL (연결 실패)${NC}"
else
    echo -e "  ${YELLOW}⚠ HTTP 응답: $HTTP_CODE${NC}"
fi

# Health Check 상세
HEALTH_RESPONSE=$(curl -s --connect-timeout 5 --max-time 10 http://$SEoul_IP/health 2>/dev/null || echo "")
if echo "$HEALTH_RESPONSE" | grep -q "healthy"; then
    echo -e "  ${GREEN}✓ Health Check: OK${NC}"
else
    echo -e "  ${YELLOW}⚠ Health Check: $HEALTH_RESPONSE${NC}"
fi

echo -e "\n${YELLOW}도쿄 리전 (DR)${NC}"
echo "IP: $TOKYO_IP"

# 네트워크 연결
if ping -c 1 -W 2 $TOKYO_IP > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓ 네트워크 연결: OK${NC}"
else
    echo -e "  ${RED}✗ 네트워크 연결: FAIL${NC}"
fi

# HTTP 응답
HTTP_CODE2=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 http://$TOKYO_IP/health 2>/dev/null || echo "000")
if [ "$HTTP_CODE2" = "200" ]; then
    echo -e "  ${GREEN}✓ HTTP 응답: OK (HTTP $HTTP_CODE2)${NC}"
elif [ "$HTTP_CODE2" = "000" ]; then
    echo -e "  ${RED}✗ HTTP 응답: FAIL (연결 실패)${NC}"
else
    echo -e "  ${YELLOW}⚠ HTTP 응답: $HTTP_CODE2${NC}"
fi

# Health Check 상세
HEALTH_RESPONSE2=$(curl -s --connect-timeout 5 --max-time 10 http://$TOKYO_IP/health 2>/dev/null || echo "")
if echo "$HEALTH_RESPONSE2" | grep -q "healthy"; then
    echo -e "  ${GREEN}✓ Health Check: OK${NC}"
else
    echo -e "  ${YELLOW}⚠ Health Check: $HEALTH_RESPONSE2${NC}"
fi

# ============================================
# 2. RDS 상태
# ============================================
echo -e "\n${BLUE}[2] RDS 상태 확인${NC}"

if [ -n "$SEoul_RDS" ]; then
    SEoul_RDS_HOST=$(echo "$SEoul_RDS" | cut -d: -f1)
    echo -e "\n${YELLOW}서울 RDS${NC}"
    echo "Endpoint: $SEoul_RDS_HOST"
    
    # RDS 연결 테스트 (타임아웃 체크)
    if timeout 3 bash -c "echo > /dev/tcp/$SEoul_RDS_HOST/3306" 2>/dev/null; then
        echo -e "  ${GREEN}✓ 포트 3306: 열림${NC}"
    else
        echo -e "  ${YELLOW}⚠ 포트 3306: 확인 불가 (Security Group 확인 필요)${NC}"
    fi
fi

if [ -n "$TOKYO_RDS" ]; then
    TOKYO_RDS_HOST=$(echo "$TOKYO_RDS" | cut -d: -f1)
    echo -e "\n${YELLOW}도쿄 RDS${NC}"
    echo "Endpoint: $TOKYO_RDS_HOST"
    
    if timeout 3 bash -c "echo > /dev/tcp/$TOKYO_RDS_HOST/3306" 2>/dev/null; then
        echo -e "  ${GREEN}✓ 포트 3306: 열림${NC}"
    else
        echo -e "  ${YELLOW}⚠ 포트 3306: 확인 불가 (Security Group 확인 필요)${NC}"
    fi
fi

# ============================================
# 3. Route 53 DNS 설정
# ============================================
echo -e "\n${BLUE}[3] Route 53 DNS 설정 확인${NC}"
echo "Domain: $DOMAIN"

if [ -n "$NAMESERVERS" ]; then
    # Terraform output이 리스트 형식일 수 있으므로 다양한 형식 처리
    NS=$(echo "$NAMESERVERS" | grep -oE 'ns-[0-9]+\.awsdns-[0-9]+\.[^" ,\]}]+' | head -1)
    if [ -z "$NS" ]; then
        # 다른 형식 시도
        NS=$(echo "$NAMESERVERS" | tr -d '[]",' | grep -oE 'ns-[0-9]+\.[^ ]+' | head -1)
    fi
    if [ -n "$NS" ]; then
        echo "Name Server: $NS"
        
        # DNS 조회
        DNS_RESULT=$(dig +short $DOMAIN @$NS 2>/dev/null | head -1 || echo "")
        if [ -n "$DNS_RESULT" ]; then
            echo "DNS 해석 결과: $DNS_RESULT"
            if [ "$DNS_RESULT" = "$SEoul_IP" ]; then
                echo -e "  ${GREEN}✓ Primary로 라우팅 중${NC}"
            elif [ "$DNS_RESULT" = "$TOKYO_IP" ]; then
                echo -e "  ${YELLOW}⚠ Secondary로 라우팅 중 (이미 전환됨)${NC}"
            else
                echo -e "  ${RED}✗ 예상과 다른 IP${NC}"
            fi
        else
            echo -e "  ${RED}✗ DNS 해석 실패${NC}"
            echo "  Route 53 레코드가 제대로 생성되었는지 확인:"
            echo "    aws route53 list-resource-record-sets --hosted-zone-id <ZONE_ID>"
        fi
    else
        echo -e "  ${RED}✗ 네임서버를 추출할 수 없습니다${NC}"
    fi
else
    echo -e "  ${RED}✗ Route 53 네임서버 정보 없음${NC}"
fi

# ============================================
# 4. Health Check 상태 (AWS CLI)
# ============================================
echo -e "\n${BLUE}[4] Route 53 Health Check 상태${NC}"

if command -v aws > /dev/null; then
    HEALTH_CHECKS=$(aws route53 list-health-checks --query "HealthChecks[?contains(Tags[?Key=='Name'].Value, 'dr-test') || contains(Tags[?Key=='Name'].Value, 'primary') || contains(Tags[?Key=='Name'].Value, 'secondary')].{ID:Id,Type:HealthCheckConfig.Type,Path:HealthCheckConfig.ResourcePath}" --output table 2>/dev/null || echo "")
    if [ -n "$HEALTH_CHECKS" ] && [ "$HEALTH_CHECKS" != "" ]; then
        echo "$HEALTH_CHECKS"
    else
        echo -e "  ${YELLOW}⚠ Health Check 정보를 가져올 수 없습니다${NC}"
        echo "  AWS CLI 권한을 확인하세요"
    fi
else
    echo -e "  ${YELLOW}⚠ AWS CLI가 설치되어 있지 않습니다${NC}"
fi

# ============================================
# 5. 종합 진단 및 해결 방법
# ============================================
echo -e "\n${BLUE}[5] 종합 진단${NC}\n"

ISSUES=0

# EC2 문제 체크
if [ "$HTTP_CODE" != "200" ] || [ "$HTTP_CODE2" != "200" ]; then
    echo -e "${RED}✗ EC2 웹 서버가 응답하지 않습니다${NC}"
    echo "  → SSH 접속하여 Flask 서비스 상태 확인:"
    echo "    ssh ec2-user@$SEoul_IP 'sudo systemctl status flask-app'"
    echo "    ssh ec2-user@$TOKYO_IP 'sudo systemctl status flask-app'"
    ISSUES=$((ISSUES + 1))
fi

# DNS 문제 체크
if [ -z "$DNS_RESULT" ]; then
    echo -e "${RED}✗ Route 53 DNS가 해석되지 않습니다${NC}"
    echo "  → Route 53 레코드 확인:"
    echo "    ./scripts/check-route53.sh"
    echo "  → 또는 임시로 /etc/hosts 사용:"
    echo "    echo '$SEoul_IP $DOMAIN' | sudo tee -a /etc/hosts"
    ISSUES=$((ISSUES + 1))
fi

# Health Check 문제 체크
if ! echo "$HEALTH_RESPONSE" | grep -q "healthy" || ! echo "$HEALTH_RESPONSE2" | grep -q "healthy"; then
    echo -e "${YELLOW}⚠ Health Check 응답에 문제가 있을 수 있습니다${NC}"
    echo "  → DB 연결 상태 확인:"
    echo "    curl http://$SEoul_IP/health"
    echo "    curl http://$TOKYO_IP/health"
    ISSUES=$((ISSUES + 1))
fi

if [ $ISSUES -eq 0 ]; then
    echo -e "${GREEN}✓ 모든 컴포넌트가 정상적으로 작동하고 있습니다!${NC}\n"
    echo "다음 단계:"
    echo "  ./scripts/test-traffic-switch.sh - 트래픽 전환 테스트"
    echo "  ./scripts/test-data-replication.sh - 데이터 복제 테스트"
else
    echo -e "\n${YELLOW}총 $ISSUES 개의 문제가 발견되었습니다.${NC}"
    echo "위의 해결 방법을 참고하여 문제를 해결하세요."
fi

echo ""

