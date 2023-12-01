#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "${red}本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系脚本作者${plain}\n"
    exit 2
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

install_dep(){
        if [[ x"${release}" == x"centos" ]]; then
            yum clean all
            yum makecache
            if [ ${os_version} -eq 7 ]; then
                yum install epel-release -y
                yum install wget curl unzip tar crontabs socat yum-utils ca-certificates net-tools bind-utils lsof libsodium python python-pip python3 python3-pip -y
            elif [ ${os_version} -ge 8 ]; then
                dnf -y install epel-release
                dnf -y install wget curl unzip tar crontabs socat ca-certificates net-tools bind-utils lsof libsodium python3 python3-pip
            fi
        elif [[ x"${release}" == x"ubuntu" ]]; then
            apt update -y
            apt install -y wget curl unzip tar cron socat apt-transport-https ca-certificates gnupg lsb-release libsodium-dev python3 python3-pip python3-testresources libffi-dev libssl-dev git
        elif [[ x"${release}" == x"debian" ]]; then
            apt update -y
            apt install -y wget curl unzip tar cron socat apt-transport-https ca-certificates gnupg lsb-release libsodium-dev python3 python3-pip libffi-dev libssl-dev git
            ln -s -f /usr/lib/x86_64-linux-gnu/libcrypto.a /usr/lib/x86_64-linux-gnu/liblibcrypto.a
        fi
}

install_ssr() {
    apidomain=$(awk -F[/:] '{print $4}' <<< ${apihost})
    ssrname=${apidomain}_${nodeid}
    #python_v1=`python3 -V 2>&1|awk '{print $2}'|awk -F '.' '{print $1}'`
    python_v2=`python3 -V 2>&1|awk '{print $2}'|awk -F '.' '{print $2}'`
    #python_v3=`python3 -V 2>&1|awk '{print $2}'|awk -F '.' '{print $3}'`
    openssl_v1=`openssl version 2>&1|awk '{print $2}'|awk -F '.' '{print $1}'`
    wget --no-check-certificate https://github.com/wangchanggui/shadowsocks/blob/0c27cce1a2dd5595345b2bc877b156072805bc11/shadowsocks-mod230728.tgz -O /tmp/shadowsocks-mod.tgz
    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载失败，请检查服务器网络${plain}"
        exit 1
    fi
    #fix liblibcrypto.a
    if [ ${python_v2} -ge 9 ]; then
        ln -s -f /usr/lib/x86_64-linux-gnu/libcrypto.a /usr/lib/x86_64-linux-gnu/liblibcrypto.a
    fi
    #fix openssl3
    if [ ${openssl_v1} -eq 3 ]; then
        sed -i '/\[provider_sect\]/d' /etc/ssl/openssl.cnf
        sed -i '/default = default_sect/d' /etc/ssl/openssl.cnf
        sed -i '/legacy = legacy_sect/d' /etc/ssl/openssl.cnf
        sed -i '/\[default_sect\]/d' /etc/ssl/openssl.cnf
        sed -i '/\[legacy_sect\]/d' /etc/ssl/openssl.cnf
        sed -i '/activate = 1/d' /etc/ssl/openssl.cnf

cat << EOF >> /etc/ssl/openssl.cnf
[provider_sect]
default = default_sect
legacy = legacy_sect

[default_sect]
activate = 1
[legacy_sect]
activate = 1
EOF
    
    fi

    [ -e "/tmp/shadowsocks-mod" ] && rm -rf /tmp/shadowsocks-mod
    [ -e "/opt/shadowsocks-mod_${ssrname}" ] && rm -rf /opt/shadowsocks-mod_${ssrname}
    [ -e "/etc/systemd/system/ssr_${ssrname}.service" ] && rm -rf /etc/systemd/system/ssr_${ssrname}.service
    cd /tmp/
    tar xvf shadowsocks-mod.tgz
    rm -f /tmp/shadowsocks-mod.tgz
    mv /tmp/shadowsocks-mod /opt/shadowsocks-mod_${ssrname}
    cd /opt/shadowsocks-mod_${ssrname}
    pip3 install --upgrade pip setuptools
    pip3 install -r requirements.txt
    if [[ "${is_mu}" == y ]]; then
        sed -i -e "s/MU_SUFFIX = 'bing.com'/MU_SUFFIX = '${mu_suffix}'/g" -e "s/MU_REGEX = '%5m%id.%suffix'/MU_REGEX = '${mu_regex}'/g" /opt/shadowsocks-mod_${ssrname}/userapiconfig.py
    fi
    sed -i -e "s/NODE_ID = 0/NODE_ID = ${nodeid}/g" -e "s%WEBAPI_URL = 'https://demo.sspanel.host'%WEBAPI_URL = '${apihost}'%g" -e "s/WEBAPI_TOKEN = 'sspanel'/WEBAPI_TOKEN = '${apikey}'/g" /opt/shadowsocks-mod_${ssrname}/userapiconfig.py
cat <<EOF > /etc/systemd/system/ssr_${ssrname}.service
[Unit]
Description=ShadowsocksR server
After=network-online.target
Wants=network-online.target

[Service]
LimitCORE=infinity
LimitNOFILE=512000
LimitNPROC=512000
Type=simple
DynamicUser=yes
StandardOutput=null
#StandardError=journal
WorkingDirectory=/opt/shadowsocks-mod_${ssrname}
ExecStart=/usr/bin/python3 /opt/shadowsocks-mod_${ssrname}/server.py
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s TERM $MAINPID
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    temp=$(systemctl --no-pager status ssr_${ssrname}.service | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        systemctl restart ssr_${ssrname}.service
    else
        systemctl enable ssr_${ssrname}.service --now
    fi
    sleep 3
    systemctl --no-pager status ssr_${ssrname}.service
    if [[ $? -eq 0 ]]; then
        crontab -l > /tmp/cronconf
        if grep -wq "ssr_${ssrname}.service" /tmp/cronconf;then
            sed -i "/ssr_${ssrname}.service/d" /tmp/cronconf
        fi
        echo "0 6 * * *  systemctl restart ssr_${ssrname}.service" >> /tmp/cronconf
        crontab /tmp/cronconf
        rm -f /tmp/cronconf
        echo -e "${green}已添加定时任务：每天6点重启节点[${nodeid}]${plain}"
        crontab -l | grep -w "ssr_${ssrname}.service"
        echo -e "${green}您的节点[${nodeid}]安装完成${plain}"
    else
        echo -e "${red}启动失败，请确认你的安装参数填写正确，安装多个后端端口不可重复。${plain}"
    fi
}

uninstall_ssr() {
    apidomain=$(awk -F[/:] '{print $4}' <<< ${apihost})
    ssrname=${apidomain}_${nodeid}
    systemctl enable ssr_${ssrname}.service --now
    rm -f /etc/systemd/system/ssr_${ssrname}.service
    rm -rf /opt/shadowsocks-mod_${ssrname}
    crontab -l > /tmp/cronconf
    if grep -wq "ssr_${ssrname}.service" /tmp/cronconf;then
        sed -i "/ssr_${ssrname}.service/d" /tmp/cronconf
    fi
    crontab /tmp/cronconf
    rm -f /tmp/cronconf
    echo -e "${green}节点[${nodeid}]卸载完成${plain}"
}

hello(){
    echo ""
    echo -e "${yellow}ShadowsocksR Server一键安装脚本，支持节点多开${plain}"
    echo -e "${yellow}支持系统: CentOS 7+, Debian8+, Ubuntu16+${plain}"
    echo -e "${yellow}支持面板: SSpanel${plain}"
    echo ""
}

help(){
    hello
    echo "使用示例：bash $0 -w https://www.domain.com:443 -k apikey -i 10 -m y"
    echo ""
    echo "  -h     显示帮助信息"
    echo "  -w     【必填】指定WebApi地址，例：http://www.domain.com:80"
    echo "  -k     【必填】指定WebApikey"
    echo "  -i     【必填】指定节点ID"
    echo "  -m     【选填】指定节点是否为单端口类型，默认为y，可选：y, n"
    echo "  -u     【选填】将卸载对应节点"
    echo "目前仅支持上述参数设定，其他参数将保持默认值"
    echo ""
}

uninstall=n
apihost=www.domain.com
apikey=demokey
nodeid=demoid
mu_suffix=bing.com
mu_regex=%5m%id.%suffix

# -w webApiHost
# -k webApiKey
# -i NodeID
# -m is_mu
# -h help

if [[ $# -eq 0 ]];then
    help
    exit 1
fi
while getopts ":w:k:i:m:hu" optname
do
    case "$optname" in
      "w")
        apihost=$OPTARG
        ;;
      "k")
        apikey=$OPTARG
        ;;
      "i")
        nodeid=$OPTARG
        ;;
      "m")
        is_mu=$OPTARG
        ;;
      "h")
        help
        exit 0
        ;;
      "u")
        uninstall=y
        ;;
      ":")
        echo "$OPTARG 选项没有参数值"
        ;;
      "?")
        echo "$OPTARG 选项未知"
        ;;
      *)
        help
        exit 1
        ;;
    esac
done

echo -e "${green}您输入的参数：${plain}"
if [[ x"${apihost}" == x"www.domain.com" ]]; then
    echo -e "${red}未输入 -w 选项，请重新运行${plain}"
    exit 1
else
    echo -e "${yellow}前端面板地址：${apihost}${plain}"
fi
if [[ x"${apikey}" == x"demokey" ]]; then
    echo -e "${red}未输入 -k 选项，请重新运行${plain}"
    exit 1
else
    echo -e "${yellow}前端通讯秘钥：${apikey}${plain}"
fi
if [[ x"${nodeid}" == x"demoid" ]]; then
    echo -e "${red}未输入 -i 选项，请重新运行${plain}"
    exit 1
else
    echo -e "${yellow}节点ID：${nodeid}${plain}"
fi
if [[ x"${is_mu}" == x ]]; then
    echo -e "${red}单端口类型：y (未指定默认使用该值)${plain}"
    is_mu=y
else
    echo -e "${yellow}单端口类型：${is_mu}${plain}"
fi
if [[ ! "${nodeid}" =~ ^[0-9]+$ ]]; then   
    echo -e "${red}-i 选项参数值仅限数字格式，请输入正确的参数值并重新运行${plain}"
    exit 1
fi
if [[ "${uninstall}" == y ]]; then
    echo -e "${red}[警告]即将卸载上述节点，取消请按Ctrl+C，继续卸载请按任意键 ... ${plain}"
    read -s -n1
    uninstall_ssr
else
    echo -e "${green}即将开始运行，请检查信息是否正确，取消请按Ctrl+C，继续安装请按任意键 ... ${plain}"
    read -s -n1
    install_dep
    install_ssr
fi
