build_service_data(){
	service_data=$(docker service inspect --format='{{index .Spec.TaskTemplate.ContainerSpec.Labels "com.michael-landis-awakening.mongodb.backup-name"}}!{{index (index .Spec.TaskTemplate.Networks 0).Target}}!{{.Spec.TaskTemplate.ContainerSpec.Hostname}}!{{index .Spec.TaskTemplate.ContainerSpec.Labels "com.michael-landis-awakening.mongodb.replica-name"}}' $(docker service ls -q) | awk -f ../libs/mongo-backup.awk)
	service_data_backup=()
	service_data_network=()
	service_data_host=()
	service_data_replica=()
	service_data_description=()
	while IFS= read -r service_data_line
	do
		service_data_fields=( ${service_data_line} )
		service_data_backup+=(${service_data_fields[0]})
		service_data_network+=(${service_data_fields[1]})
		service_data_host+=(${service_data_fields[2]})
		service_data_replica+=(${service_data_fields[3]:-'(none)'})
	done <<< "${service_data}"
	service_data_network=( $(docker inspect --format '{{.Name}}' ${service_data_network[@]}) )
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
	unset i
	unset service_data_line
	unset temp_description
}

if [ -f "../secret_key.sh" ]
then
	. ../secret_key.sh
	if ! docker secret inspect mongo_${DOCKER_SECRET_VERSION} 2>&1 1>/dev/null
	then
		echo "mongo secrets aren't associated with the current secret_key.sh file. Rerun ../define/serets.sh to reassociate the names and passwords with Docker secrets."
		return 1
	fi
else
	echo "../secret_key.sh is missing. Rerun ../define/secrets.sh to associate names and passwords with Docker secrets."
	return 1
fi

build_service_data

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
docker_args=(\
	--name ${docker_service_name}\
	--network ${backup_network}\
	--limit-memory "256MB"\
	--mount type=bind,source=${backup_destination},destination=/data/mongodb/backup\
	--secret source=mongo_${DOCKER_SECRET_VERSION},target=mongo\
	--tty\
	--entrypoint "bash"\
	--env MONGO_HOSTS=${backup_hosts}\
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

original_host=${DOCKER_MACHINE_NAME:--u}
service_host=$(docker service ps "${docker_service_name}" --format "{{.Node}}")
if [ "${original_host}" != "${service_host}" ]
then
	eval $(docker-machine env "${service_host}") 2>&1 1>/dev/null
fi

echo
echo "Starting backup process"
echo

docker exec -t $(docker ps --filter "name=${docker_service_name}" --format "{{.ID}}") sh ./backup.sh

echo
echo "Shutting down and removing service"
echo

if [ "${original_host}" != "${service_host}" ]
then
	eval $(docker-machine env "${original_host}") 2>&1 1>/dev/null
fi
docker service rm ${docker_service_name} 1>/dev/null

echo "Backup \"${backup_name}\" of $(if [ "${replica_sets}" ]; then echo "${replica_sets}/"; fi)${hosts} complete."
echo