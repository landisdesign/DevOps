. ../libs/docker_utils.sh
. ../libs/mongo_utils.sh

build_service_descriptions(){
	service_data_description=()
	for i in ${!service_data_backup[@]}
	do
		temp_description="Back up \"${service_data_backup[$i]}\" of "
		if [ "${service_data_replica[$i]}" != '(none)' ]
		then
			temp_description="${temp_description}${service_data_replica[$i]}/"
		fi
		temp_description="${temp_description}${service_data_host[$i]} on ${service_data_network[i]}"
		service_data_description+=("${temp_description}")
	done
	unset temp_description
	unset i
}

declare -a machine_data
IFS=' ' read -a machine_data <<<"$(dsmachines) "
current_machine=${machine_data[0]}
swarm_manager=${machine_data[1]}

if [ "${current_machine}" != "${swarm_manager}" ]
then
	eval $(docker-machine env "${swarm_manager}") 2>&1 1>/dev/null
fi

if [ -f "../secret_keys.sh" ]
then
	. ../secret_keys.sh
	if ! docker secret inspect mongo_backup_admin_name_v${mongo_backup_admin_name_SECRET_VERSION} 2>&1 1>/dev/null\
		|| ! docker secret inspect mongo_backup_admin_pwd_v${mongo_backup_admin_pwd_SECRET_VERSION} 2>&1 1>/dev/null
	then
		echo "mongo secrets aren't associated with the current secret_key.sh file. Rerun ../define/serets.sh to reassociate the names and passwords with Docker secrets."
		return 1
	fi
else
	echo "../secret_keys.sh is missing. Rerun ../define/secrets.sh to associate names and passwords with Docker secrets."
	return 1
fi

get_service_data
build_service_descriptions
backup_index=-1

if [ $# -eq 1 ]
then
	for i in ${!service_data_backup[@]}
	do
		if [ "$1" = "${service_data_backup[$i]}" ]
		then
			if [ ${backup_index} -ge 0 ]
			then
				echo
				echo "More than one backup exists with the name \"$1\"."
				backup_index=-2
			elif [ ${backup_index} -eq -1 ]
			then
				backup_index=${i}
			fi
		fi
	done
	if [ $backup_index -eq -1 ]
	then
		echo
		echo "\"$1\" was not found as a backup label."
		echo
		backup_index=-2
	fi
fi

if [ ${backup_index} -lt 0 ]
then
	backup_length=${#service_data_backup[@]}
	if [ ${backup_length} -eq 1 ] && [ ${backup_index} -eq -1 ]
	then
		backup_index=0
	else
		echo "Choose which backup to perform by entering a number from 1 to ${backup_length} (0 to exit):"
		for i in ${!service_data_description[@]}
		do
			echo "( $((i + 1)) ) ${service_data_description[$i]}"
		done
		i=-1;
		while [ "$i" -lt 0 ] 2>/dev/null || [ "$i" -gt "${backup_length}" ] 2>/dev/null
		do
			read -s i
			if [ "$i" -eq 0 ]
			then
				echo
				echo "Exiting without backing up"
				echo
				return
			fi
		done
		backup_index=$(($i - 1))
	fi
fi

backup_name=${service_data_backup[$backup_index]}
backup_network=${service_data_network[$backup_index]}
backup_hosts=${service_data_host[$backup_index]}
backup_replica=${service_data_replica[$backup_index]}

echo
echo "The following backup will be performed:"
echo "  ${service_data_description[$backup_index]}"
echo

backup_destination="/data/mongodb/backup/${backup_name}"
docker_image=landisdesign/mongo-authenticated-utilities:4.0.3-xenial
docker_service_name="mongo_backup_${backup_name}_$RANDOM"
docker_args=( \
	--name ${docker_service_name} \
	--network ${backup_network} \
	--limit-memory "256MB" \
	--mount type=bind,source=${backup_destination},destination=/data/mongodb/backup \
	--secret source=mongo_backup_admin_name_v${mongo_backup_admin_name_SECRET_VERSION},target=mongo_backup_admin_name \
	--secret source=mongo_backup_admin_pwd_v${mongo_backup_admin_pwd_SECRET_VERSION},target=mongo_backup_admin_pwd \
	--tty \
	--entrypoint "bash" \
	--env MONGO_HOSTS=${backup_hosts} \
)
if [ "${backup_replica}" != "(none)" ]
then
	echo "Backing up replica set \"${backup_replica}\" from primary member to ${backup_destination}"
	docker_args+=(--env MONGO_REPLICA_NAME=${backup_replica})
else
	case "$backup_hosts" in
		*,*) echo "Backing up replica set from nearest of the hosts \"${backup_hosts}\" to ${backup_destination}" ;;
		*) echo "Backing up database from ${backup_hosts} to ${backup_destination}" ;;
	esac
fi

echo
echo "Starting service ${docker_service_name}..."
echo

docker service create ${docker_args[@]} ${docker_image}

echo
echo "Starting backup process"
echo

service_host=$(docker service ps "${docker_service_name}" --format "{{.Node}}")
if [ "${swarm_manager}" != "${service_host}" ]
then
	eval $(docker-machine env "${service_host}") 2>&1 1>/dev/null
fi

docker exec -t $(docker ps --filter "name=${docker_service_name}" --format "{{.ID}}") sh ./backup.sh

echo
echo "Shutting down and removing service"
echo

if [ "${service_host}" == "${swarm_manager}" ]
then
	docker service rm ${docker_service_name} 1>/dev/null
else
	docker-machine ssh "${swarm_manager}" "docker service rm ${docker_service_name} 1>/dev/null"
fi

if [ "${service_host}" != "${current_machine}" ]
then
	eval $(docker-machine env "${current_machine}") 2>&1 1>/dev/null
fi

echo "Backup \"${backup_name}\" of $(if [ "${backup_replica}" ]; then echo " ${backup_replica}/"; fi)${backup_hosts} complete."
echo