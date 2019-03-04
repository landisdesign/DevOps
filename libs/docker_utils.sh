dsmachines() {
	_machine_data="$(docker-machine ls --format='{{.Name}} {{.URL}} {{.Active}}')"
	read _ssh_machine <<<"${_machine_data}"
	_manager_url="$(docker info --format="{{range .Swarm.RemoteManagers}} {{.Addr}} {{end}}" | head -n 1 | sed -n 's/^[^0-1]*\([^:]*\).*$/\1/p')"
	if [ -z "${_manager_url}" ]
	then
		_manager_url="$(docker-machine ssh ${_ssh_machine} "docker info --format='{{range .Swarm.RemoteManagers}} {{.Addr}} {{end}}'" | head -n 1 | sed -n 's/^[^0-1]*\([^:]*\).*$/\1/p')"
	fi
	_machine_data="$( printf "%s %s %s\n" "${_machine_data}" | awk -v u=${_manager_url} 'BEGIN {a="-u"} $2 ~ "(^|[^0-9])" u "([^0-9]|$)" {m=$1} $3=="*" {a=$1} END {print a " " m}' )"
	declare -a _machine_data_arr
	IFS=' ' read -a _machine_data_arr <<<"${_machine_data} "
	CURRENT_DOCKER_MACHINE_NAME="${_machine_data_arr[0]}"
	SWARM_MANAGER_MACHINE_NAME="${_machine_data_arr[1]}"
	unset _machine_data _machine_data_arr
}

switch_to_machine() {
	if [ -z "${CURRENT_DOCKER_MACHINE_NAME}" ]
	then
		dsmachines
	fi

	if [ "$1" != "${CURRENT_DOCKER_MACHINE_NAME}" ]
	then
		eval $(docker-machine env "$1") 1>/dev/null
		CURRENT_DOCKER_MACHINE_NAME="$1"
	fi
}

switch_to_swarm_manager() {
	if [ -z "${SWARM_MANAGER_MACHINE_NAME:+set}" ]
	then
		dsmachines
	fi

	ORIGINAL_MACHINE="${CURRENT_DOCKER_MACHINE_NAME}"

	switch_to_machine "${SWARM_MANAGER_MACHINE_NAME}"
}

switch_to_original_machine() {
	switch_to_machine "${ORIGINAL_MACHINE}"
}

push_secret() {
	switch_to_swarm_manager
	if [ -f "$2" ]
	then
		docker secret create $1 $2 >/dev/null 2>/dev/null
	else
		echo $2 | docker secret create $1 - >/dev/null 2>/dev/null
	fi
	switch_to_original_machine
}

remove_secret(){
	switch_to_swarm_manager
	docker secret rm $1 >/dev/null 2>/dev/null
	switch_to_original_machine
}

remove_secrets(){ # Returns names of secrets that couldn't be deleted
	doomed_secrets=($@)

	switch_to_swarm_manager
	docker secret rm ${doomed_secrets[@]} 2>&1 | sed -n "s/^[^']*'\([^']*\)'[^']*$/\\1/p"
	switch_to_original_machine
}

get_secrets(){
	filter_name=$1
	shift
	filters=()
	for filter
	do
		filters+=(--filter "${filter_name}=${filter}")
	done

	switch_to_swarm_manager
	docker secret ls ${filters[@]} --format={{.Name}}
	switch_to_original_machine
}