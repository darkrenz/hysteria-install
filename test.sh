#!/bin/bash

export LANG=en_US.UTF-8

mkdir -p /etc/hysteria

version=$(wget -qO- -t1 -T2 --no-check-certificate "https://api.github.com/repos/HyNetwork/hysteria/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')

echo -e "Downloading the latest hysteria (version \033[31m$version\033[0m)"

get_arch=$(arch)

if [ "$get_arch" = "x86_64" ]; then

  wget -q -O /etc/hysteria/hysteria --no-check-certificate https://github.com/HyNetwork/hysteria/releases/download/"$version"/hysteria-linux-amd64

elif [ "$get_arch" = "aarch64" ]; then

  wget -q -O /etc/hysteria/hysteria --no-check-certificate https://github.com/HyNetwork/hysteria/releases/download/"$version"/hysteria-linux-arm64

elif [ "$get_arch" = "mips64" ]; then

  wget -q -O /etc/hysteria/hysteria --no-check-certificate https://github.com/HyNetwork/hysteria/releases/download/"$version"/hysteria-linux-mipsle

else

  print "\033[41;37mError: $get_arch is not supported yet\n\033[0m"

  exit

fi

chmod 755 /etc/hysteria/hysteria

 

echo -e "\033[32mDomain (default wechat.com):\033[0m"

read -r domain

if [ -z "${domain}" ]; then

  domain="wechat.com"

  ip=$(curl -4 -s ip.sb)

  echo -e "server ip:\033[31m$ip\033[0m\n"

fi

 

echo -e "\033[32mPort:\033[0m"

read -r port

if [ -z "${port}" ]; then

  port=$(($(od -An -N2 -i /dev/random) % (65534 - 10001) + 10001))

  echo -e "Port:\033[31m$port\033[0m\n"

fi

 

echo -e "\033[32mProtocol:\n\033[0m\033[33m\033[01m1、udp (recommended) \n2、fake tcp (Linux and Android only)\n3、wechat video (default)\033[0m\033[32m\n\nProtocol:\033[0m"

read -r protocol

if [ -z "${protocol}" ] || [ "$protocol" == "3" ]; then

  protocol="wechat-video"

  iptables -I INPUT -p udp --dport ${port} -m comment --comment "allow udp(hysteria)" -j ACCEPT

elif [ $protocol == "2" ]; then

  protocol="faketcp"

  iptables -I INPUT -p tcp --dport ${port} -m comment --comment "allow tcp(hysteria)" -j ACCEPT

else

  protocol="udp"

  iptables -I INPUT -p udp --dport ${port} -m comment --comment "allow udp(hysteria)" -j ACCEPT

fi

echo -e "Protocol: \033[31m$protocol\033[0m\n"

 

echo -e "\033[32mLatency in ms (default 200):\033[0m"

read -r delay

if [ -z "${delay}" ]; then

  delay=200

  echo -e "Latency: \033[31m$delay\033[0m\n"

fi

echo -e "\033[32mDownload in Mbps (default 50):\033[0m"

read -r download

if [ -z "${download}" ]; then

  download=50

  echo -e "Download: \033[31m$download\033[0mMbps\n"

fi

echo -e "\033[32mUpload in Mbps (default 10):\033[0m"

read -r upload

if [ -z "${upload}" ]; then

  upload=10

  echo -e "Upload: \033[31m$upload\033[0mMbps\n"

fi

echo -e "\033[32mPassword:\033[0m"

read -r auth_str

 

download=$(($download + $download / 4))

upload=$(($upload + $upload / 4))

r_client=$(($delay * $download * 2100))

r_conn=$((491520 / 4))

if [ "$domain" = "wechat.com" ]; then

  mail="admin@qq.com"

  days=36500

 

  echo -e "\033[1;;35mSIGN...\n \033[0m"

  openssl genrsa -out /etc/hysteria/$domain.ca.key 2048

  openssl req -new -x509 -days $days -key /etc/hysteria/$domain.ca.key -subj "/C=CN/ST=GuangDong/L=ShenZhen/O=PonyMa/OU=Tencent/emailAddress=$mail/CN=Tencent Root CA" -out /etc/hysteria/$domain.ca.crt

  openssl req -newkey rsa:2048 -nodes -keyout /etc/hysteria/$domain.key -subj "/C=CN/ST=GuangDong/L=ShenZhen/O=PonyMa/OU=Tencent/emailAddress=$mail/CN=Tencent Root CA" -out /etc/hysteria/$domain.csr

  openssl x509 -req -extfile <(printf "subjectAltName=DNS:%s,DNS:%s",$domain,$domain) -days $days -in /etc/hysteria/$domain.csr -CA /etc/hysteria/$domain.ca.crt -CAkey /etc/hysteria/$domain.ca.key -CAcreateserial -out /etc/hysteria/$domain.crt

 

  rm /etc/hysteria/${domain}.ca.key /etc/hysteria/${domain}.ca.srl /etc/hysteria/${domain}.csr

  echo -e "\033[1;;35mOK.\n \033[0m"

 

  cat <<EOF >/etc/hysteria/config.json

{

  "listen": ":$port",

  "protocol": "$protocol",

  "disable_udp": false,

  "cert": "/etc/hysteria/$domain.crt",

  "key": "/etc/hysteria/$domain.key",

  "auth": {

    "mode": "password",

    "config": {

      "password": "$auth_str"

    }

  },

  "recv_window_conn": 196608,

  "recv_window_client": 491520,

  "max_conn_client": 4096,

}

EOF

 

  v6str=":"

  result=$(echo "$ip" | grep ${v6str})

  if [ "$result" != "" ]; then

    ip="[$ip]" #ipv6?

  fi

 

  cat <<EOF >config.json

{

"server": "$ip:$port",

"protocol": "$protocol",

"up_mbps": $upload,

"down_mbps": $download,

"socks5": {

"listen": "127.0.0.1:1080",

"timeout": 300,

"disable_udp": false

},

"auth_str": "$auth_str",

"server_name": "$domain",

"insecure": true,

"recv_window_conn": 196608,

"recv_window": 491520,

"disable_mtu_discovery": false,

"retry": 3,

"retry_interval": 1

}

EOF

 

else

  iptables -I INPUT -p tcp --dport 80 -m comment --comment "allow tcp(hysteria)" -j ACCEPT

  iptables -I INPUT -p tcp --dport 443 -m comment --comment "allow tcp(hysteria)" -j ACCEPT

  cat <<EOF >/etc/hysteria/config.json

{

  "listen": ":$port",

  "protocol": "$protocol",

  "acme": {

    "domains": [

	"$domain"    ],

    "email": "admin@$domain"

  },

  "disable_udp": false,

  "auth": {

    "mode": "password",

    "config": {

      "password": "$auth_str"

    }

  },

  "recv_window_conn": 196608,

  "recv_window_client": 491520,

  "max_conn_client": 4096,

  "disable_mtu_discovery": false,

  "resolver": "8.8.8.8:53"

}

EOF

 

  cat <<EOF >config.json

{

"server": "$domain:$port",

"protocol": "$protocol",

"up_mbps": $upload,

"down_mbps": $download,

"socks5": {

"listen": "127.0.0.1:1080",

"timeout": 300,

"disable_udp": false

},

"auth_str": "$auth_str",

"server_name": "$domain",

"insecure": false,

"recv_window_conn": 196608,

"recv_window": 491520,

"retry": 3,

"retry_interval": 1

}

EOF

fi

 

cat <<EOF >/etc/systemd/system/hysteria.service

[Unit]

Description=hysteria

After=network.target

 

[Service]

Type=simple

PIDFile=/run/hysteria.pid

ExecStart=/etc/hysteria/hysteria --log-level warn -c /etc/hysteria/config.json server

#Restart=on-failure

#RestartSec=10s

 

[Install]

WantedBy=multi-user.target

EOF

 

sysctl -w net.core.rmem_max=8000000

sysctl -p

netfilter-persistent save

netfilter-persistent reload

chmod 644 /etc/systemd/system/hysteria.service

systemctl daemon-reload

systemctl enable hysteria

systemctl start hysteria

echo -e "\033[1;;35m\nWaiting...\n\033[0m"

sleep 3

status=$(systemctl is-active hysteria)

if [ "${status}" = "active" ]; then

  crontab -l >./crontab.tmp

  echo "0 4 * * * systemctl restart hysteria" >>./crontab.tmp

  crontab ./crontab.tmp

  rm -rf ./crontab.tmp

  echo -e "\033[35m↓***********************************↓↓↓start↓↓↓*******************************↓\033[0m"

  cat ./config.json

  echo -e "\033[35m↑************************************↑↑↑end↑↑↑********************************↑\033[0m"

else

  echo -e "\033[1;33;40mError! Try running /etc/hysteria/hysteria -c /etc/hysteria/config.json server\033[0m\n"

fi
