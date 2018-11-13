#!/usr/bin/env ksh
PATH=/usr/local/bin:${PATH}
IFS_DEFAULT="${IFS}"

#################################################################################

#################################################################################
#
#  Variable Definition
# ---------------------
#
APP_NAME=$(basename $0)
APP_DIR=$(dirname $0)
APP_VER="1.0.0"
APP_WEB="http://www.sergiotocalini.com.ar/"
PID_FILE="/var/run/keepalived.pid"
TIMESTAMP=`date '+%s'`

DOCKER_SOCK="/var/run/docker.sock"
CACHE_DIR="${APP_DIR}/tmp"
CACHE_TTL=1                                      # IN MINUTES
#
#################################################################################

#################################################################################
#
#  Load Oracle Environment
# -------------------------
#
[ -f ${APP_DIR}/${APP_NAME%.*}.conf ] && . ${APP_DIR}/${APP_NAME%.*}.conf

#
#################################################################################

#################################################################################
#
#  Function Definition
# ---------------------
#
usage() {
    echo "Usage: ${APP_NAME%.*} [Options]"
    echo ""
    echo "Options:"
    echo "  -a            Arguments to the section."
    echo "  -h            Displays this help message."
    echo "  -j            Jsonify output."
    echo "  -s            Select the section (service, account, etc. )."
    echo "  -v            Show the script version."
    echo ""
    echo "Please send any bug reports to sergiotocalini@gmail.com"
    exit 1
}

version() {
    echo "${APP_NAME%.*} ${APP_VER}"
    exit 1
}

zabbix_not_support() {
    echo "ZBX_NOTSUPPORTED"
    exit 1
}

refresh_cache() {
    params=( "${@}" )
    if [[ ${#params[@]} > 1 ]]; then
	if [[ ${params[0]} == 'containers' ]]; then
	    if [[ ${params[1]} == 'data' ]]; then
		name="containers/${params[2]}/data"
		url="http://localhost/containers/${params[2]}/json?size=true"
	    elif [[ ${params[1]} == 'stats' ]]; then
		name="containers/${params[2]}/stats"
		url="http://localhost/containers/${params[2]}/stats?stream=false"
	    fi
	elif [[ ${params[0]} == 'images' ]]; then
	    if [[ ${params[1]} == 'data' ]]; then
		name="containers/${params[2]}/data"
		url="http://localhost/images/${params[2]}/json"
	    fi
	fi
    else
	if [[ ${params[0]} == 'containers' ]]; then
	    name="containers/data"
	    url="http://localhost/containers/json?size=true&all=true"
	elif [[ ${params[0]} == 'images' ]]; then
	    name="images/data"
	    url="http://localhost/images/json?all=true"
	else
	    name="${params[0]}"
	    url="http://localhost/${params[0]}"
	fi
    fi
    [[ -z ${url} || -z ${name} ]] && return 1
    
    filename="${CACHE_DIR}/${name}.json"
    basename=`dirname ${filename}`
    [[ -d "${basename}" ]] || mkdir -p "${basename}"
    [[ -f "${filename}" ]] || touch -d "$(( ${CACHE_TTL}+1 )) minutes ago" "${filename}"

    if [[ $(( `stat -c '%Y' "${filename}" 2>/dev/null`+60*${CACHE_TTL} )) -le ${TIMESTAMP} ]]; then
	[[ ! -f "${DOCKER_SOCK}" ]] || return 1
	curl -s --unix-socket "${DOCKER_SOCK}" "${url}" 2>/dev/null | jq . 2>/dev/null > "${filename}"
    fi
    echo "${filename}"
}


service() {
    params=( ${@} )
    pattern='^(([a-z]{3,5})://)?((([^:\/]+)(:([^@\/]*))?@)?([^:\/?]+)(:([0-9]+))?)(\/[^?]*)?(\?[^#]*)?(#.*)?$'
    [[ "${DOVEIX_URI}" =~ $pattern ]] || return 1
    regex_match=( "${.sh.match[@]:-${BASH_REMATCH[@]:-${match[@]}}}" )
    
    if [[ ${params[0]} =~ (uptime|listen|cert) ]]; then
	pid=`sudo lsof -Pi :${regex_match[10]:-${regex_match[2]}} -sTCP:LISTEN -t 2>/dev/null`
	rcode="${?}"
	if [[ -n ${pid} ]]; then
	    if [[ ${params[0]} == 'uptime' ]]; then
		res=`sudo ps -p ${pid} -o etimes -h 2>/dev/null`
	    elif [[ ${params[0]} == 'listen' ]]; then
		[[ ${rcode} == 0 && -n ${pid} ]] && res=1
	    elif [[ ${params[0]} == 'cert' ]]; then
		cert_text=`openssl s_client -connect "${regex_match[3]}:${regex_match[10]:-${regex_match[2]}}" </dev/null 2>/dev/null`
		if [[ ${params[1]} == 'expires' ]]; then
		    date=`echo "${cert_text}" | openssl x509 -noout -enddate 2>/dev/null | cut -d'=' -f2`
		    res=$((($(date -d "${date}" +'%s') - $(date +'%s'))/86400))
		elif [[ ${params[1]} == 'after' ]]; then
		    date=`echo "${cert_text}" | openssl x509 -noout -enddate 2>/dev/null | cut -d'=' -f2`
		res=`date -d "${date}" +'%s' 2>/dev/null`
		elif [[ ${params[1]} == 'before' ]]; then
		    date=`echo "${cert_text}" | openssl x509 -noout -startdate 2>/dev/null | cut -d'=' -f2`
		    res=`date -d "${date}" +'%s' 2>/dev/null`
		fi
	    fi
	fi
    elif [[ ${params[0]} == 'version' ]]; then
	res=`dovecot --version 2>/dev/null`
    fi
    echo "${res:-0}"
    return 0
}


containers() {
    params=( ${@} )
    if [[ ${params[0]:-list} =~ (list|LIST|all|ALL) ]]; then
	cache=$( refresh_cache 'containers' )
	if [[ ${?} == 0 ]]; then
	    res=`jq ".[] | [.Id, .Names[0][1:], (.Created|tostring), .State, .Status] | join(\"|\")" ${cache} 2>/dev/null`
	fi
    elif [[ ${#params[@]} > 1 ]]; then
	if [[ ${params[0]} =~ (data|stats) ]]; then
	    cache=$( refresh_cache 'containers' "${params[0]}" "${params[1]}" )
	    if [[ ${?} == 0 ]]; then
		res=`jq ".${params[2]}" ${cache} 2>/dev/null`
	    fi
	fi
    fi
    echo "${res:-0}"
    return 0    
}


images() {
    params=( ${@} )
    if [[ ${params[0]:-list} =~ (list|LIST|all|ALL) ]]; then
	cache=$( refresh_cache 'images' )
	if [[ ${?} == 0 ]]; then
	    res=`jq ".[] | [.Id, .RepoTags[0], (.Created|tostring), (.Size|tostring)] | join(\"|\")" ${cache} 2>/dev/null`
	fi
    elif [[ ${#params[@]} > 1 ]]; then
	if [[ ${params[0]} =~ (data) ]]; then
	    cache=$( refresh_cache 'images' "${params[0]}" "${params[1]}" )
	    if [[ ${?} == 0 ]]; then
		res=`jq ".${params[2]}" ${cache} 2>/dev/null`
	    fi
	fi
    fi
    echo "${res:-0}"
    return 0    
}


general() {
    params=( ${@} )
    if [[ ${params[0]:-info} =~ (info|version|volumes|network) ]]; then
	cache=$( refresh_cache "${params[0]}" )
	if [[ ${?} == 0 ]]; then
	    res=`jq ".${params[2]}" ${cache} 2>/dev/null`
	fi
    fi
    echo "${res:-0}"
    return 0    
}

#
#################################################################################

#################################################################################
while getopts "s::a:sj:uphvt:" OPTION; do
    case ${OPTION} in
	h)
	    usage
	    ;;
	s)
	    SECTION="${OPTARG}"
	    ;;
        j)
            JSON=1
            IFS=":" JSON_ATTR=( ${OPTARG} )
	    IFS="${IFS_DEFAULT}"
            ;;
	a)
	    param="${OPTARG//p=}"
	    [[ -n ${param} ]] && ARGS[${#ARGS[*]}]="${param}"
	    ;;
	v)
	    version
	    ;;
        \?)
            exit 1
            ;;
    esac
done

if [[ "${SECTION}" == "service" ]]; then
    rval=$( service "${ARGS[@]}" )  
elif [[ "${SECTION}" == "containers" ]]; then
    rval=$( containers "${ARGS[@]}" )
elif [[ "${SECTION}" == "images" ]]; then
    rval=$( images "${ARGS[@]}" )
elif [[ "${SECTION}" == "general" ]]; then
    rval=$( general "${ARGS[@]}" )    
else
    zabbix_not_support
fi
rcode="${?}"

if [[ ${JSON} -eq 1 ]]; then
    echo '{'
    echo '   "data":['
    count=1
    while read line; do
	if [[ ${line} != '' ]]; then
            IFS="|" values=(${line})
            output='{ '
            for val_index in ${!values[*]}; do
		output+='"'{#${JSON_ATTR[${val_index}]:-${val_index}}}'":"'${values[${val_index}]}'"'
		if (( ${val_index}+1 < ${#values[*]} )); then
                    output="${output}, "
		fi
            done
            output+=' }'
	    if (( ${count} < `echo ${rval}|wc -l` )); then
		output="${output},"
            fi
            echo "      ${output}"
	fi
        let "count=count+1"
    done < <(echo "${rval}")
    echo '   ]'
    echo '}'
else
    echo "${rval:-0}"
fi

exit ${rcode}
