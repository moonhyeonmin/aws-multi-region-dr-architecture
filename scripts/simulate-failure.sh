#!/bin/bash
#
# 서울 리전 장애 시뮬레이션 스크립트
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}=== 서울 리전 장애 시뮬레이션 ===${NC}\n"

# Terraform outputs에서 정보 가져오기
if [ ! -f "../terraform/terraform.tfstate" ]; then
    echo -e "${RED}Error: terraform.tfstate 파일을 찾을 수 없습니다.${NC}"
    exit 1
fi

SEoul_INSTANCE_ID=$(terraform -chdir=../terraform output -raw seoul_ec2_ip 2>/dev/null || echo "")

if [ -z "$SEoul_INSTANCE_ID" ]; then
    echo -e "${YELLOW}Warning: Terraform outputs를 가져올 수 없습니다.${NC}"
    read -p "Seoul EC2 Instance ID: " SEoul_INSTANCE_ID
fi

echo -e "${YELLOW}주의: 이 스크립트는 실제 인스턴스를 중지하거나 변경합니다!${NC}\n"
echo "선택 가능한 장애 시나리오:"
echo "  1) Security Group 규칙 제거 (HTTP 차단)"
echo "  2) EC2 인스턴스 중지"
echo "  3) RDS 인스턴스 중지 (주의: 비용 및 시간 소요)"
echo ""

read -p "시나리오 선택 (1-3): " SCENARIO

case $SCENARIO in
    1)
        echo -e "\n${YELLOW}Security Group 규칙 제거 방법:${NC}"
        echo "1. AWS Console에서 Seoul 리전의 EC2 Security Group으로 이동"
        echo "2. Inbound 규칙에서 HTTP (80) 규칙을 제거하거나 임시로 차단"
        echo "3. Route 53 Health Check가 실패를 감지할 때까지 대기"
        ;;
    2)
        echo -e "\n${RED}EC2 인스턴스 중지${NC}"
        read -p "정말 EC2 인스턴스를 중지하시겠습니까? (yes): " CONFIRM
        if [ "$CONFIRM" = "yes" ]; then
            echo "EC2 인스턴스 중지 중..."
            aws ec2 stop-instances --instance-ids "$SEoul_INSTANCE_ID" --region ap-northeast-2 || {
                echo -e "${RED}Error: AWS CLI를 사용할 수 없거나 권한이 없습니다.${NC}"
                echo "수동으로 AWS Console에서 인스턴스를 중지하세요."
            }
            echo -e "${GREEN}인스턴스 중지 요청 완료${NC}"
        fi
        ;;
    3)
        echo -e "\n${RED}RDS 인스턴스 중지 (비추천)${NC}"
        echo "RDS를 중지하면 재시작하는 데 시간이 오래 걸립니다."
        read -p "정말 계속하시겠습니까? (yes): " CONFIRM
        if [ "$CONFIRM" = "yes" ]; then
            RDS_ID=$(terraform -chdir=../terraform output -raw seoul_rds_endpoint 2>/dev/null | cut -d: -f1 || echo "")
            echo "RDS 인스턴스 중지 중..."
            aws rds stop-db-instance --db-instance-identifier "$RDS_ID" --region ap-northeast-2 || {
                echo -e "${RED}Error: AWS CLI를 사용할 수 없거나 권한이 없습니다.${NC}"
            }
        fi
        ;;
    *)
        echo -e "${RED}잘못된 선택${NC}"
        exit 1
        ;;
esac

echo -e "\n${GREEN}장애 시뮬레이션 완료${NC}"
echo "Route 53 Health Check가 장애를 감지하고 트래픽을 전환할 때까지 대기하세요."
echo "약 2-3분 소요됩니다."

