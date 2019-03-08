#!/bin/bash
. ../libs/docker_utils.sh
. ../libs/mongo_utils.sh

dsmachines

current_machine="${CURRENT_DOCKER_MACHINE_NAME}"

switch_to_machine "${SWARM_MANAGER_MACHINE_NAME}"

if [ -f "../secret_keys.sh" ]
then
	. ../secret_keys.sh
	if ! docker secret inspect mongo_backup_admin_name_v${mongo_backup_admin_name_SECRET_VERSION} 2>&1 1>/dev/null\
		|| ! docker secret inspect mongo_backup_admin_pwd_v${mongo_backup_admin_pwd_SECRET_VERSION} 2>&1 1>/dev/null
	then
		echo "mongo secrets aren't associated with the current secret_key.sh file. Rerun ../define/serets.sh to reassociate the names and passwords with Docker secrets."
		exit 1
	fi
else
	echo "../secret_keys.sh is missing. Rerun ../define/secrets.sh to associate names and passwords with Docker secrets."
	exit 1
fi

get_service_data -b
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
				exit
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
if [ -e "${backup_destination}" ]
then
	if [ ! -d "${backup_destination}" ]
	then
		echo "${backup_destination} is not a directory. Backup cannot be performed here." >&2
		exit 1
	fi
else
	echo "Creating backup directory ${backup_destination}"
	echo
	mkdir "${backup_destination}"
fi

docker_args=( \
	--mount type=bind,source=${backup_destination},destination=/data/mongodb/backup \
	--secret source=mongo_backup_admin_name_v${mongo_backup_admin_name_SECRET_VERSION},target=mongo_backup_admin_name \
	--secret source=mongo_backup_admin_pwd_v${mongo_backup_admin_pwd_SECRET_VERSION},target=mongo_backup_admin_pwd \
	--tty \
	--env MONGO_HOSTS=${backup_hosts} \
)
if [ "${backup_replica}" != "(none)" ]
then
	echo "Backing up replica set \"${backup_replica}\" from primary member to ${backup_destination}"
	docker_args+=(--env MONGO_REPLICA_NAME=${backup_replica})
	backup_hosts="${backup_replica}/${backup_hosts}"
else
	case "$backup_hosts" in
		*,*) echo "Backing up replica set from nearest of the hosts \"${backup_hosts}\" to ${backup_destination}" ;;
		*) echo "Backing up database from ${backup_hosts} to ${backup_destination}" ;;
	esac
fi

create_utility_service "${backup_network}" ${docker_args[@]}
execute_utility_process sh ./backup.sh
destroy_utility_service

switch_to_machine "${current_machine}"

echo
echo "Backup \"${backup_name}\" of ${backup_hosts} complete."
echo
