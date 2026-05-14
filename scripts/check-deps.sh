#!/bin/bash
set -euo pipefail

# Check if dependencies are installed
# Dependencies: docker, terraform, gh, act, helm, kubectl

# Define colors, red, blue and green
RED='\033[0;31m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'
YELLOW='\033[1;33m'


# Check if docker is installed
echo -e "${BLUE}Checking if docker is installed...${NC}"
if ! command -v docker &> /dev/null; then
    echo "Docker is not installed. Please install docker."
    echo "You can install Docker by following the instructions at: https://docs.docker.com/get-docker/"
    exit 1
else
    echo -e "${GREEN}Docker is installed.${NC}"
fi

# Check if terraform is installed
echo -e "${BLUE}Checking if terraform is installed...${NC}"
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Terraform is not installed. Please install terraform.${NC}"
    echo "You can install Terraform by following the instructions at: https://learn.hashicorp.com/terraform/getting-started/install.html"
    exit 1
else
    echo -e "${GREEN}Terraform is installed.${NC}"
fi

# Check if gh cli is installed
echo -e "${BLUE}Checking if GitHub CLI is installed...${NC}"
if ! command -v gh &> /dev/null; then
    echo -e "${RED}GitHub CLI is not installed. Please install GitHub CLI.${NC}"
    echo "You can install GitHub CLI by following the instructions at: https://cli.github.com/"
    exit 1
else
    echo -e "${GREEN}GitHub CLI is installed.${NC}"
fi

# Check if act is installed
echo -e "${BLUE}Checking if act is installed...${NC}"
if ! command -v act &> /dev/null; then
    echo -e "${RED}act is not installed. Please install act.${NC}"
    echo "You can install act by following the instructions at: https://github.com/nektos/act"
    exit 1
else
    echo -e "${GREEN}act is installed.${NC}"
fi

# Check if helm is installed
echo -e "${BLUE}Checking if helm is installed...${NC}"
if ! command -v helm &> /dev/null; then
    echo -e "${RED}Helm is not installed. Please install Helm.${NC}"
    echo "You can install Helm by following the instructions at: https://helm.sh/docs/intro/install/"
    exit 1
else
    echo -e "${GREEN}Helm is installed.${NC}"
fi

# Check if kubectl is installed
echo -e "${BLUE}Checking if kubectl is installed...${NC}"
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl is not installed. Please install kubectl.${NC}"
    echo "You can install kubectl by following the instructions at: https://kubernetes.io/docs/tasks/tools/"
    exit 1
else
    echo -e "${GREEN}kubectl is installed.${NC}"
fi

echo -e "${GREEN}All dependencies are installed.${NC}"
