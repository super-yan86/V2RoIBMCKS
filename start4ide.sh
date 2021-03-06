#!/bin/bash

# 定义参数检查
paras=$@
function checkPara(){
    local p=$1
    for i in $paras; do if [[ $i == $p ]]; then return; fi; done
    false
}

# 设置 REGION
REGION=us-south # US South(Dallas, USA), North America
checkPara 'au' && REGION=au-syd # AP South(Sydney, Australia), Asia Pacific
checkPara 'de' && REGION=eu-de # EU Central(Frankfurt, Deutschland), Europe
checkPara 'uk' && REGION=eu-gb # UK South(London, Great Britain), Europe

# 设置 BBR
BBR=false
checkPara 'bbr' && BBR=true

# 设置 CLUSTER_NAME
echo -e -n '\n您打算用哪个集群？请原样输入集群名称并仔细核对：'
read CLUSTER_NAME
while [ -z $CLUSTER_NAME ]
do
    echo -e -n '\n您未输入应用程序名称，请重新输入：'
    read CLUSTER_NAME
done

# 保留或生成 UUID、SS_PWD & WebSocket PATH
echo -e '\n++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
echo 'First, configure V2Ray as a VMess server with WebSocket.'
echo '++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
echo -e -n '\n要生成新 UUID，请按回车键；要保留旧 UUID，请正确输入，仔细核对：'
read UUID
if [ -z $UUID ]; then 
    echo -e '\n您未输入旧 UUID，将生成新 UUID。'
    UUID=$(cat /proc/sys/kernel/random/uuid)
    echo -e '\nGenerated a new UUID for V2Ray VMess server.'
fi
echo -e -n '\n要生成新 WebSocket PATH，请按回车键；要用 "/" 或保留旧 WebSocket PATH，请正确输入，仔细核对：'
read WEBSOCKET_PATH
if [ -z $WEBSOCKET_PATH ]; then 
    echo -e '\n您未输入旧 WebSocket PATH，将生成新 WebSocket PATH。'
    WEBSOCKET_PATH=$(cat /proc/sys/kernel/random/uuid | cut -d '-' -f1)
    echo -e '\nGenerated a new WebSocket PATH for V2Ray VMess server.'
else
    WEBSOCKET_PATH=$(echo $WEBSOCKET_PATH | cut -d '/' -f2) # 删除用户输入字符串开头可能会有的'/'
fi

echo -e '\n+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
echo 'Then, configure V2Ray as a Shadowsocks server with WebSocket.'
echo '+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++'
echo -e -n '\n要生成新密码，请按回车键；要保留旧密码，请正确输入，仔细核对：'
read SS_PWD
if [ -z $SS_PWD ]; then 
    echo -e '\n您未输入旧密码，将生成新密码。'
    SS_PWD=$(openssl rand -base64 12 | md5sum | head -c12)
    echo -e '\nGenerated a new PASSWORD for V2Ray Shadowsocks server.'
fi
echo -e -n '\n要生成新 WebSocket PATH，请按回车键；要用 "/" 或保留旧 WebSocket PATH，请正确输入，仔细核对：'
read SS_WEBSOCKET_PATH
if [ -z $SS_WEBSOCKET_PATH ]; then 
    echo -e '\n您未输入旧 WebSocket PATH，将生成新 WebSocket PATH。'
    SS_WEBSOCKET_PATH=$(cat /proc/sys/kernel/random/uuid | cut -d '-' -f1)
    echo -e '\nGenerated a new WebSocket PATH for V2Ray Shadowsocks server.'
else
    SS_WEBSOCKET_PATH=$(echo $SS_WEBSOCKET_PATH | cut -d '/' -f2) # 删除用户输入字符串开头可能会有的'/'
fi

# 询问 Caddy 申请证书时使用的 DOMAIN 与 EMAIL
echo -e '\n++++++++++++++++++++++++++++++++++++++++++++'
echo 'Finally, configure Caddy with TLS.'
echo '++++++++++++++++++++++++++++++++++++++++++++'
echo -e -n "\n请输入 Caddy 申请 Let's Encrypt 证书时使用的域名："
read DOMAIN
while [ -z $DOMAIN ]
do
    echo -e -n '\n您未输入域名，请重新输入：'
    read DOMAIN
done
echo -e -n '\n请输入找回证书私钥时使用的 email 地址：'
read EMAIL
while [ -z $EMAIL ]
do
    echo -e -n '\n您未输入email地址，请重新输入：'
    read EMAIL
done

sleep 3

# 显示 BBR 安装信息
if $BBR; then
    echo -e '\nBBR will be enabled.'
fi

#获取并验证 IBM Cloud 账户信息，登录到 IBM Cloud CLI
echo -e -n '\n请输入用户名：'
read USERNAME
while [ -z $USERNAME ]
do
    echo -e -n '\n您未输入用户名，请重新输入：'
    read USERNAME
done
echo -e -n '\n请输入密码：'
read -s PASSWD
while [ -z $PASSWD ]
do
    echo -e -n '\n您未输入密码，请重新输入：'
    read -s PASSWD
done
echo -e '\n'
while ibmcloud login -a https://cloud.ibm.com -r $REGION -u $USERNAME -p $PASSWD 2>&1 | grep -q "Credentials were rejected"
do
    echo -e '\n用户名或密码错误，请核对后重新输入！'
    echo -e -n '\n请输入用户名：'
    read USERNAME
    while [ -z $USERNAME ]
    do
        echo -e -n '\n您未输入用户名，请重新输入：'
        read USERNAME
    done
    echo -e -n '\n请输入密码：'
    read -s PASSWD
    while [ -z $PASSWD ]
    do
        echo -e -n '\n您未输入密码，请重新输入：'
        read -s PASSWD
    done
    echo -e '\n'
done
echo 'OK'
echo

# 设置 IBMCR_DOMAIN
IBMCR_DOMAIN=$(ibmcloud cr region | grep 'icr.io' | cut -d "'" -f4)

# 设置 KUBECTLVER
KUBECTLVER='v'$(ibmcloud ks cluster get --cluster $CLUSTER_NAME | grep 'Version' | awk '{print $2}' | cut -d '_' -f1)

# 将 IBM Cloud CLI 配置为运行 kubectl
echo -e '\nConfigurate IBM Cloud CLI to run kubectl ...'
$(ibmcloud ks cluster config --cluster $CLUSTER_NAME -s)

# 显示 kubectl 版本
echo -e '\nKubectl version:'
echo
kubectl version  --short

# 尝试清除以前的构建环境
echo -e '\nTry to clear the previous build environment ...'
kubectl delete pod build 2>/dev/null
while ! kubectl get pod build 2>&1 | grep -q "NotFound"
do
    sleep 5  # 等待 build 容器停止
done
echo 'Done.'

# 尝试清除以前的部署
echo -e '\nTry to clear the previous deployments ...'
kubectl delete deploy v2ray v2ray-ss caddy bbr 2>/dev/null
kubectl delete svc v2ray-tcp-for-caddy v2ray-udp-for-caddy v2ray-ss-tcp-for-caddy v2ray-ss-udp-for-caddy caddy-tcp-for-bbr bbr-tcp caddy-tcp caddy-udp 2>/dev/null
kubectl delete rs -l run=v2ray | grep 'deleted' --color=never
kubectl delete rs -l run=v2ray-ss | grep 'deleted' --color=never
kubectl delete rs -l run=caddy | grep 'deleted' --color=never
kubectl delete rs -l run=bbr | grep 'deleted' --color=never
echo 'Done.'

# 创建构建环境
echo -e '\nCreate the build environment ...'

cat << _EOF_ > build.yaml
apiVersion: v1
kind: Pod
metadata:
  name: build
spec:
  containers:
  - name: alpine
    image: docker:dind
    command: ["sleep"]
    args: ["1800"]
    securityContext:
      privileged: true
  restartPolicy: Never
_EOF_

kubectl create -f build.yaml
sleep 3
while ! kubectl exec -it build expr 24 '*' 24 2>/dev/null | grep -q "576"
do
    sleep 5
done

# 获取 V2Ray 服务器的 IP 地址，设置端口参数
IP=$(kubectl exec -it build -- wget -qO- whatismyip.akamai.com)
SP=443
let PORT_RAND=($RANDOM)/12

# 进入构建环境
echo -e '\nEnter into the build environment ...'
(echo 'apk add --update curl ca-certificates openssl'; \
    echo wget -O build.sh 'https://raw.githubusercontent.com/USAmy/V2RoIBMCKS/master/build.sh'; \
    echo sh build.sh "$REGION" "$USERNAME" "$PASSWD" "$CLUSTER_NAME" "$IP" "$SP" "$PORT_RAND" "$UUID" "$SS_PWD" "$BBR" "$DOMAIN" "$EMAIL" "$WEBSOCKET_PATH" "$SS_WEBSOCKET_PATH" "$KUBECTLVER" "$IBMCR_DOMAIN") | kubectl exec -it build sh

# 清除构建环境
echo -e '\nClear the build environment ...'
kubectl delete pod build

# 输出信息
echo
echo 
echo '惊不惊喜，意不意外！'
echo
echo " V2Ray Shadowsocks server with WebSocket & TLS via Caddy's proxy:"
echo
echo '  IP: '$IP
echo '  Port: '$SP
echo '  Password: '$SS_PWD
echo '  Method: aes-128-gcm'
echo '  WebSocket PATH: /'$SS_WEBSOCKET_PATH
echo '  Domain: '$DOMAIN
echo '  Email: '$EMAIL
echo "  Certificate file's path: /root/.caddy/acme/acme-v02.api.letsencrypt.org/sites/${DOMAIN}/"
echo "  Certificate files: ${DOMAIN}.crt, ${DOMAIN}.key"
ADDR='ss://'$(echo -n "aes-128-gcm:$SS_PWD@$IP:$SP" | base64)
echo 
echo '  快速添加: '$ADDR
echo '  二维码: http://qr.liantu.com/api.php?text='$ADDR
echo
echo ' ================================================================'
echo
echo " V2Ray VMess server with WebSocket & TLS via Caddy's proxy:"
echo
echo '  IP: '$IP
echo '  Port: '$SP
echo '  UUID: '$UUID
echo '  WebSocket PATH: /'$WEBSOCKET_PATH
echo '  Domain: '$DOMAIN
echo '  Email: '$EMAIL
echo "  Certificate file's path: /root/.caddy/acme/acme-v02.api.letsencrypt.org/sites/${DOMAIN}/"
echo "  Certificate files: ${DOMAIN}.crt, ${DOMAIN}.key"
echo
