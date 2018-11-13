#!/usr/bin/env ksh
SOURCE_DIR=$(dirname $0)
ZABBIX_DIR=/etc/zabbix
PREFIX_DIR="${ZABBIX_DIR}/scripts/agentd/zocker"

ZOCKER_SOCK="${1:-/var/run/docker.sock}"
CACHE_DIR="${2:-${PREFIX_DIR}/tmp}"
CACHE_TTL="${3:-5}"

mkdir -p "${PREFIX_DIR}"

SCRIPT_CONFIG="${PREFIX_DIR}/zocker.conf"
if [[ -f "${SCRIPT_CONFIG}" ]]; then
    SCRIPT_CONFIG="${SCRIPT_CONFIG}.new"
fi

cp -rpv "${SOURCE_DIR}/zocker/zocker.sh"             "${PREFIX_DIR}/"
cp -rpv "${SOURCE_DIR}/zocker/zocker.conf.example"   "${SCRIPT_CONFIG}"
cp -rpv "${SOURCE_DIR}/zocker/zabbix_agentd.conf"    "${ZABBIX_DIR}/zabbix_agentd.d/zocker.conf"

regex_array[0]="s|ZOCKER_SOCK=.*|ZOCKER_SOCK=\"${ZOCKER_SOCK}\"|g"
regex_array[1]="s|CACHE_DIR=.*|CACHE_DIR=\"${CACHE_DIR}\"|g"
regex_array[2]="s|CACHE_TTL=.*|CACHE_TTL=\"${CACHE_TTL}\"|g"
for index in ${!regex_array[*]}; do
    sed -i "${regex_array[${index}]}" ${SCRIPT_CONFIG}
done
