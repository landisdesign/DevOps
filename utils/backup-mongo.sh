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

if [ $# -eq 1 ]
then
	backup_name=$1
else
	if [ "${MONGO_BACKUP_NAME}" ]
	then
		backup_name="${MONGO_BACKUP_NAME}"
	else
		echo "$0 requires one argument: backup name if env variable MONGO_BACKUP_NAME isn't set"
		return 1
	fi
fi

backup_destination="/data/mongodb/backup/"
replica_sets=()
networks=()
hosts=()

service_data=( $(docker service inspect --format='{{index .Spec.TaskTemplate.ContainerSpec.Labels "com.michael-landis-awakening.mongodb.backup-name"}} {{index .Spec.TaskTemplate.ContainerSpec.Labels "com.michael-landis-awakening.mongodb.replica-name"}} {{index (index .Spec.TaskTemplate.Networks 0).Target}} {{.Spec.TaskTemplate.ContainerSpec.Hostname}}' $(docker service ls -q) | sed -n "s/^$backup_name //p") )

#populate arrays
for i in ${!service_data[@]}
do
	if [ "${service_data[i]}" ]
	then
		case $(expr $i % 3) in
			0) replica_sets+=(${service_data[i]});;
			1) networks+=(${service_data[i]});;
			2) hosts+=(${service_data[i]});;
		esac
	fi
done

#deduplicate arrays
replica_sets=( $(printf "%s\n" ${replica_sets[@]} | awk '!x[$0]++') )
networks=( $(printf "%s\n" ${networks[@]} | awk '!x[$0]++') )
hosts=( $(printf "%s\n" ${hosts[@]} | awk '!x[$0]++') )

if [ ${#hosts[@]} -eq 0 ]
then
	echo "No hosts found for backup named \"${backup_name}\""
	return 1
fi

hosts=$(echo "${hosts[@]}" | sed 's/ /,/g')

if [ ${#replica_sets[@]} -gt 1 ]
then
	echo "There can only be at most one replica set associated with a backup. Backup \"${backup_name}\" includes replica sets \"${replica_sets[@]}\""
	return 1
fi

if [ ${#networks[@]} -eq 0 ]
then
	echo "No network is identified with backup \"${backup_name}\""
	return 1
fi

networks=( $(docker inspect --format '{{.Name}}' ${networks[@]}) )

if [ ${#networks[@]} -gt 1 ]
then
	echo "Backups can only access hosts who identify the same network first in their configuration. Backup \"${backup_name}\" identifies networks \"${networks[@]}\""
	return 1
fi

docker_image=landisdesign/mongo-authenticated-backup:4.0.3-xenial
docker_service_name="mongo_backup_${backup_name}_$RANDOM"
docker_args=(\
	--name ${docker_service_name}\
	--network ${networks}\
	--limit-memory "256MB"\
	--mount type=bind,source=${backup_destination}${backup_name},destination=/data/mongodb/backup\
	--secret source=mongo_${DOCKER_SECRET_VERSION},target=mongo\
	--tty\
	--entrypoint "bash"\
	--env MONGO_HOSTS=${hosts}\
)
if [ "${replica_sets}" ]
then
	echo "Backing up replica set \"${replica_sets}\" from primary member to ${backup_destination}${backup_name}"
	docker_args+=(--env MONGO_REPLICA_NAME=${replica_sets})
else
	if [ ${#hosts[@]} -gt 1 ]
	then
		echo "Backing up replica set from nearest of the hosts \"${hosts[@]}\" to ${backup_destination}${backup_name}"
	else
		echo "Backing up database from ${hosts} to ${backup_destination}${backup_name}"
	fi
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

docker exec -t $(docker ps --filter "name=${docker_service_name}" --format "{{.ID}}") sh ./start.sh

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