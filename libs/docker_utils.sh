current_machine() {
	docker-machine ls --format "{{.Name}} {{.Active}}" | awk 'BEGIN {m="-u"} $2=="*" {m=$1} END {print m}'
}

dsmachines() {
	_machine_data="$(docker-machine ls --format='{{.Name}} {{.URL}} {{.Active}}')"
	_ssh_machine=(${_machine_data}) # cheating to get first name from list
	_manager_url=$(docker info --format="{{range .Swarm.RemoteManagers}} {{.Addr}} {{end}}" | head -n 1 | sed -n 's/^[^0-1]*\([^:]*\).*$/\1/p')
	if [ -z "${_manager_url}" ]
	then
		_manager_url=$(docker-machine ssh ${_ssh_machine} "docker info --format='{{range .Swarm.RemoteManagers}} {{.Addr}} {{end}}'" | head -n 1 | sed -n 's/^[^0-1]*\([^:]*\).*$/\1/p')
	fi
	printf "%s %s %s\n" "${_machine_data}" | awk -v u=${_manager_url} 'BEGIN {a="-u"} $2 ~ "(^|[^0-9])" u "([^0-9]|$)" {m=$1} $3=="*" {a=$1} END {print a " " m}'
}

define_swarm() {
	_machine_data=$(docker-machine ls --format="{{.Name}} {{.URL}}")
	_ssh_machine=(${_machine_data}) # cheating to get first name from list
	_manager_url=$(docker info --format="{{range .Swarm.RemoteManagers}} {{.Addr}} {{end}}" | head -n 1 | sed -n 's/^[^0-1]*\([^:]*\).*$/\1/p')
	if [ -z "${_manager_url}" ]
	then
		_manager_url=$(docker-machine ssh ${_ssh_machine} "docker info --format='{{range .Swarm.RemoteManagers}} {{.Addr}} {{end}}'" | head -n 1 | sed -n 's/^[^0-1]*\([^:]*\).*$/\1/p')
	fi
	SWARM_MANAGER_NAME=$(printf "%s %s\n" ${_machine_data} | awk -v u=${_manager_url} '$2 ~ "(^|[^0-9])" u "([^0-9]|$)" {print $1}')
}

#
#	These methods expect the swarm manager machine to be identified in SWARM_MANAGER_NAME
#

push_secret(){
	if [ -f "$2" ]
	then
		if [ "${SWARM_MANAGER_NAME}" ]
		then
			docker-machine ssh "${SWARM_MANAGER_NAME}" "docker secret create $1 $2" >/dev/null 2>/dev/null
		else
			docker secret create $1 $2 >/dev/null 2>/dev/null
		fi
	else
		if [ "${SWARM_MANAGER_NAME}" ]
		then
			echo $2 | docker-machine ssh "${SWARM_MANAGER_NAME}" "docker secret create $1 -" >/dev/null 2>/dev/null
		else
			echo $2 | docker secret create $1 - >/dev/null 2>/dev/null
		fi
	fi
}

remove_secret(){
	if [ "${SWARM_MANAGER_NAME}" ]
	then
		docker-machine ssh "${SWARM_MANAGER_NAME}" "docker secret rm $1" >/dev/null 2>/dev/null
	else
		docker secret rm $1 >/dev/null 2>/dev/null
	fi
}

remove_secrets(){ # Returns names of secrets that couldn't be deleted
	doomed_secrets=$@
	if [ "${SWARM_MANAGER_NAME}" ]
	then
		docker-machine ssh "${SWARM_MANAGER_NAME}" "docker secret rm ${doomed_secrets} 2>&1" 2>&1 | sed -n "s/^[^']*'\([^']*\)'[^']*$/\\1/p"
	else
		docker secret rm ${doomed_secrets} 2>&1 | sed -n "s/^[^']*'\([^']*\)'[^']*$/\\1/p"
	fi
}

get_secrets(){
	filter_name=$1
	shift
	filters=()
	for filter
	do
		filters+=("--filter=\"${filter_name}=${filter}\"")
	done

	if [ "${SWARM_MANAGER_NAME}" ]
	then
		docker-machine ssh "${SWARM_MANAGER_NAME}" "docker secret ls ${filters[@]} --format=\"{{.Name}}\""
	else
		docker secret ls ${filters[@]} --format={{.Name}}
	fi
}