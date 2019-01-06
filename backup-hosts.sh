if [ $# -eq 1 ]
then
	backup_name=$1
else
	if [ "${MONGO_BACKUP_NAME}" ]
	then
		backup_name="${MONGO_BACKUP_NAME}"
	else
		echo "$0 requires one argument: backup name"
		exit 1
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
	exit 1
fi

hosts=$(echo "${hosts[@]}" | sed 's/ /,/g')

if [ ${#replica_sets[@]} -gt 1 ]
then
	echo "There can only be at most one replica set associated with a backup. Backup \"${backup_name}\" includes replica sets \"${replica_sets[@]}\""
	exit 1
fi

if [ ${#networks[@]} -eq 0 ]
then
	echo "No network is identified with backup \"${backup_name}\""
	exit 1
fi

networks=( $(docker inspect --format '{{.Name}}' ${networks[@]}) )

if [ ${#networks[@]} -gt 1 ]
then
	echo "Backups can only access hosts who identify the same network first in their configuration. Backup \"${backup_name}\" identifies networks \"${networks[@]}\""
	exit 1
fi

if [ "${replica_sets}" ]
then
	echo "Backing up replica set \"${replica_sets}\" from primary member to ${backup_destination}${backup_name}"
	docker run --net ${networks} mongo-backup -b ${backup_destination}${backup_name} -h ${hosts} -r ${replica_sets}
else
	if [ ${#hosts[@]} -gt 1 ]
	then
		echo "Backing up replica set from nearest of the hosts \"${hosts[@]}\" to ${backup_destination}${backup_name}"
	else
		echo "Backing up database from ${hosts} to ${backup_destination}${backup_name}"
	fi
	docker run --net ${networks} mongo-backup -b ${backup_destination}${backup_name} -h ${hosts} 
fi

