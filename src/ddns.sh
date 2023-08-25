#!/bin/sh

# 当前脚本所在的位置
prefix="/etc/ddns"
# prefix="～/path-to-dir"

. ${prefix}/lib/jshn.sh
. ${prefix}/lib/network.sh

# 读取配置 [每个文件 只读取 第一行]
# 钉钉群聊机器人服务器地址
read -r DINGTALK_HOST <${prefix}/env/dingtalk_host
# 钉钉群聊机器人 token
read -r DINGTALK_ROBOT_ACCESS_TOKEN <${prefix}/env/dingtalk_robot_access_token
# 钉钉群聊机器人 消息推送 签名 [签名一致才会被接受]
read -r DINGTALK_ROBOT_MESSAGE_KEY <${prefix}/env/dingtalk_robot_message_key
# CloudFlare ZoneID
read -r CLOUDFLARE_ZONE_ID <${prefix}/env/cloudflare_zone_id
# CloufFlare DNS API token [需要有dns的修改权限]
read -r CLOUDFLARE_EDIT_ZONE_DNS_API_TOKEN <${prefix}/env/cloudflare_edit_zone_dns_api_token
# CloufFlare 需要被修改的 DNS 项 的 IDENTIFIER [可以通过接口或者别的途径查询]
read -r CLOUDFLARE_DNS_RECORDS_IDENTIFIER <${prefix}/env/cloudflare_dns_records_identifier
# iOS Bark App 的 通知推送服务 地址
read -r RENDER_BARK_SERVER_HOST <${prefix}/env/bark_server_host

# 上一次脚本执行时候的 ip 地址 [用来和当前地址比较，两次结果不一致会依次推送 钉钉消息、bark 通知、更新 DNS IP]
read -r ip_old <${prefix}/log/ip_old.txt

# 获取 wan 口的公网 ip 地址
ip_new=''
network_get_ipaddr ip_new wan

############### FUNCTIONS ###############
# 推送 Brak 消息
pushBark() {
    data_body="[${ip_old}] -> [${ip_new}]"
    data="{
         \"title\": \"IP 变动提醒\",
         \"body\": \"${data_body}\",
         \"device_key\": \"bark\",
         \"icon\": \"https://www.google.com/s2/favicons?sz=64&domain=cloudflare.net\",
         \"group\": \"DDNS[bot]\"
         }"

    curl --insecure \
        --url "${RENDER_BARK_SERVER_HOST}/push" \
        --header "Content-Type: application/json; charset=utf-8" \
        --data "${data}"
}

# 推送 dingding 消息
pushDingTalk() {
    content=$(ip address | grep 'inet')
    dateStr=$(date +%Y-%m-%d\ %H:%M:%S\ %z)
    data="{
          \"msgtype\": \"text\",
          \"at\": {
            isAtAll: true
          },
          \"text\": {
                    \"content\": \"${dateStr}\n==========\n[${ip_old}] -> [${ip_new}]\n${content}\n${DINGTALK_ROBOT_MESSAGE_KEY}\"
                    }
         }"

    curl --insecure \
        --request POST \
        --url "${DINGTALK_HOST}?access_token=${DINGTALK_ROBOT_ACCESS_TOKEN}" \
        --header "Content-Type: application/json" \
        --data "${data}"
}

# dns 更新 数据
dns_data_new="{
             \"content\": \"${ip_new}\",
             \"name\": \"sh.tedding.dev\",
             \"proxied\": false,
             \"type\": \"A\"
         }"

# 更新 dns 信息
put_dns_record() {
    curl --insecure \
        --request PUT \
        --url "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${CLOUDFLARE_DNS_RECORDS_IDENTIFIER}" \
        --header "Content-Type: application/json" \
        --header "Authorization: Bearer ${CLOUDFLARE_EDIT_ZONE_DNS_API_TOKEN}" \
        --data "${dns_data_new}"
}

# 查询 dns 信息
get_records() {
    curl --insecure \
        --request GET \
        --url "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/dns_records" \
        --header "Content-Type: application/json" \
        --header "Authorization: Bearer ${CLOUDFLARE_EDIT_ZONE_DNS_API_TOKEN}"
}
############### FUNCTIONS ###############

if [ "${ip_new}" = "${ip_old}" ]; then
    echo "[$(/bin/date)] 当前 ip 未更改" >${prefix}/log/log.txt
else
    echo "[$(/bin/date)] 当前 ip 已更改" >${prefix}/log/log.txt
    # 推送 消息
    pushDingTalk
    pushBark
    # 更新 dns
    put_dns_record
    # 记录新的 ip 地址
    echo "${ip_new}" >${prefix}/log/ip_old.txt
    # 记录 dns 更新时间
    /bin/date >${prefix}/log/dns.txt
    # 记录 dns 更新内容
    echo "${dns_data_new}" >>${prefix}/log/dns.txt
    # 追加记录每一次 动作 的 日期
    /bin/date >>${prefix}/log/push.log
fi
