echo "Installing kubectl..."

sudo curl --silent --location -o /usr/local/bin/kubectl \
   https://amazon-eks.s3.us-west-2.amazonaws.com/1.17.11/2020-09-18/bin/linux/amd64/kubectl

sudo chmod +x /usr/local/bin/kubectl

echo "Updating AWS CLI"
sudo pip install --upgrade awscli && hash -r

echo "Install utilities (jq, yq, bash completions, etc.)..."
sudo yum -y install jq gettext bash-completion moreutils

echo 'yq() {
  docker run --rm -i -v "${PWD}":/workdir mikefarah/yq yq "$@"
}' | tee -a ~/.bashrc && source ~/.bashrc


echo "Verify the binaries are in the path and executable..."
for command in kubectl jq envsubst aws
  do
    which $command &>/dev/null && echo "$command in path" || echo "$command NOT FOUND"
  done

echo "Bash tuneup..."

kubectl completion bash >>  ~/.bash_completion
. /etc/profile.d/bash_completion.sh
. ~/.bash_completion

echo 'export LBC_VERSION="v2.0.0"' >>  ~/.bash_profile
.  ~/.bash_profile

echo "Adjust ENV variables"
rm -vf ${HOME}/.aws/credentials

export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
export AWS_REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')

test -n "$AWS_REGION" && echo AWS_REGION is "$AWS_REGION" || echo AWS_REGION is not set

echo "export ACCOUNT_ID=${ACCOUNT_ID}" | tee -a ~/.bash_profile
echo "export AWS_REGION=${AWS_REGION}" | tee -a ~/.bash_profile
aws configure set default.region ${AWS_REGION}
aws configure get default.region

echo "Validate IAM Role"
aws sts get-caller-identity --query Arn | grep eksworkshop-admin -q && echo "IAM role valid" || echo "IAM role NOT valid"

echo "Clone service repos"
cd ~/environment
git clone https://github.com/brentley/ecsdemo-frontend.git
git clone https://github.com/brentley/ecsdemo-nodejs.git
git clone https://github.com/brentley/ecsdemo-crystal.git

echo "Setting up SSH Key"
ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa <<< y
aws ec2 import-key-pair --key-name "eksworkshop" --public-key-material file://~/.ssh/id_rsa.pub

echo "Creating key to encrypt K8S secrets"

aws kms create-alias --alias-name alias/eksworkshop --target-key-id $(aws kms create-key --query KeyMetadata.Arn --output text)
export MASTER_ARN=$(aws kms describe-key --key-id alias/eksworkshop --query KeyMetadata.Arn --output text)
echo "export MASTER_ARN=${MASTER_ARN}" | tee -a ~/.bash_profile

echo "Install EKSCTL"

curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp

sudo mv -v /tmp/eksctl /usr/local/bin

eksctl completion bash >> ~/.bash_completion
. /etc/profile.d/bash_completion.sh
. ~/.bash_completion

cat << EOF > eksworkshop.yaml
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: eksworkshop-eksctl
  region: ${AWS_REGION}
  version: "1.17"

availabilityZones: ["${AWS_REGION}a", "${AWS_REGION}b", "${AWS_REGION}c"]

managedNodeGroups:
- name: nodegroup
  desiredCapacity: 3
  ssh:
    allow: true
    publicKeyName: eksworkshop

# To enable all of the control plane logs, uncomment below:
# cloudWatch:
#  clusterLogging:
#    enableTypes: ["*"]

secretsEncryption:
  keyARN: ${MASTER_ARN}
EOF

eksctl create cluster -f eksworkshop.yaml




