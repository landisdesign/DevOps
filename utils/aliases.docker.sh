alias dm=docker-machine;

dmenv() {
	eval $(docker-machine env $1);
}

dms() {
	_machine_data="$(docker-machine ls --format='{{.Name}} {{.URL}} {{.Active}}')"
	_ssh_machine=(${_machine_data}) # cheating to get first name from list
	_manager_url=$(docker info --format="{{range .Swarm.RemoteManagers}} {{.Addr}} {{end}}" | head -n 1 | sed -n 's/^[^0-1]*\([^:]*\).*$/\1/p')
	if [ -z "${_manager_url}" ]
	then
		_manager_url=$(docker-machine ssh ${_ssh_machine} "docker info --format='{{range .Swarm.RemoteManagers}} {{.Addr}} {{end}}'" | head -n 1 | sed -n 's/^[^0-1]*\([^:]*\).*$/\1/p')
	fi
	printf "%s %s %s\n" "${_machine_data}" | awk -v u=${_manager_url} 'BEGIN {a="-u"} $2 ~ "(^|[^0-9])" u "([^0-9]|$)" {m=$1} $3=="*" {a=$1} END {print a " " m}'
}

dsps() {
	declare -a _machine_data
	IFS=' ' read -a _machine_data <<<"$(dsmachines) "
	_current=${_machine_data[0]}
	_manager=${_machine_data[1]}
	_stack_name=$1
	if [ "${_current}" == "${_manager}" ]
	then
		docker stack ps ${_stack_name} --filter "desired-state=running" --format "table {{.Name}}\t{{.Node}}\t{{.CurrentState}}\t{{.Ports}}"
	else
		docker-machine ssh "${_manager}" "docker stack ps ${_stack_name} --filter 'desired-state=running' --format 'table {{.Name}}\t{{.Node}}\t{{.CurrentState}}\t{{.Ports}}'"
	fi
}

ds() {
	_command="$1"
	if [ $# -eq 3 ]
	then
		_task_name=$3
		declare -a _machine_data
		IFS=' ' read -a _machine_data <<<"$(dsmachines) "
		_current=${_machine_data[0]}
		_manager=${_machine_data[1]}
		if [ "${_current}" == "${_manager}" ]
		then
			_stack_vm=$(docker stack ps $2 --filter "name=$_task_name" --filter "desired-state=running" --format "{{.Node}}" 2>/dev/null)
		else
			_stack_vm=$(docker-machine ssh "${_manager}" "docker stack ps $2 --filter 'name=$_task_name' --filter 'desired-state=running' --format '{{.Node}}'" 2>/dev/null)
		fi
		if [ -z "${_stack_vm}" ]
		then
			echo "No task found with name ${_task_name} in stack $2" >&2
			return
		fi
		if [ "${_current}" != "${_stack_vm}" ]
		then
			dmenv "${_stack_vm}"
		fi
	else
		_current=""
		_stack_vm=""
		_task_name=$2
	fi
	_task_id=$(docker ps --filter "name=$_task_name" --format "{{.ID}}" 2>/dev/null)
	if [ "${_task_id}" ]
	then
		case "${_command}" in
			"bash" ) docker exec -it ${_task_id} bash ;;
			"logs" ) docker logs --tail all --follow ${_task_id} ;;
			* ) echo "ds: ${_command} is not a valid argument." >&2 ;;
		esac
	else
		echo "No task found with name ${_task_name} on this machine" >&2
		return
	fi
	if [ "${_current}" != "${_stack_vm}" ]
	then
		dmenv ${_current}
	fi
}

db() {
	OPTIND=1
	cache=--no-cache
	push=""
	while getopts ":v:pc" opt
	do
		case "${opt}" in
			"v" ) version="${OPTARG}" ;;
			"p" ) push="y" ;;
			"c" ) cache="" ;;

			"?" )
				echo "Invalid option: ${OPTARG}" >&2
				exit 1
				;;
			":" )
				echo "Invalid option: ${OPTARG} is missing an argument" >&2
				exit 1
		esac
	done
	shift $(($OPTIND - 1))

	if [ "${version}" ]
	then
		tag="$(basename $(pwd)):${version}"
	else
		tag="$1"
	fi
	tag="landisdesign/${tag}"

	docker build ${cache} -t=${tag} .
	if [ "${push}" ]
	then
		docker push ${tag}
	fi
}