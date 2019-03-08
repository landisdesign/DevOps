get_service_data() {
	docker inspect --format "{{.Id}} {{.Name}}" $(docker network ls -q) > ./~network_data.txt
	docker service inspect --format '{{index .Spec.TaskTemplate.ContainerSpec.Labels "com.michael-landis-awakening.mongodb.backup-name"}}!{{index (index .Spec.TaskTemplate.Networks 0).Target}}!{{.Spec.TaskTemplate.ContainerSpec.Hostname}}!{{index .Spec.TaskTemplate.ContainerSpec.Labels "com.michael-landis-awakening.mongodb.replica-name"}}' $(docker service ls -q) 2>/dev/null | awk -f ../libs/collect_mongo_hosts.awk > ./~backup_data.txt
	service_data_backup=()
	service_data_network=()
	service_data_host=()
	service_data_replica=()
	service_data_description=()
	while IFS= read -r service_data_line
	do
		IFS=' ' read _backup _network _host _replica <<<"${service_data_line} "
		service_data_backup+=(${_backup})
		service_data_network+=(${_network})
		service_data_host+=(${_host})
		service_data_replica+=(${_replica})
		if [ "${_replica}" = "(none)" ]
		then
			_desc=""
		else
			_desc="replica set \"${_replica}\" on "
		fi
		if [ "$1" = "-b" ]
		then
			_desc="Back up \"${_backup}\" of ${_desc}"
		fi
		service_data_description+=("${_desc}${_host} on network ${_network}")
	done <<< "$(awk -f ../libs/translate_network.awk ./~network_data.txt ./~backup_data.txt )"
	unset service_data_line _backup _network _host _replica _desc
	rm ./~network_data.txt ./~backup_data.txt
}

create_utility_service() {
	if [ "$#" -eq 0 ]
	then
		echo "Missing network name" >&2
		return 1
	fi

	_utility_service_container_network="$1"
	shift

	if [ "${_utility_service_name}" ]
	then
		echo "Utility service is already created" >&2
		return 1
	fi

	_utility_service_name="mongo_utility_$RANDOM"

	echo "Starting utility ${_utility_service_name}"
	echo

	if [ -z "${SWARM_MANAGER_MACHINE_NAME}" ]
	then
		dsmachines
	fi

	switch_to_machine "${SWARM_MANAGER_MACHINE_NAME}"

	docker service create --name "${_utility_service_name}" --network "${_utility_service_container_network}" --limit-memory "256MB" $@ "landisdesign/mongo-authenticated-utilities:4.0.3-xenial"
	echo

	_utility_service_machine_name="$(docker service ps "${_utility_service_name}" --format "{{.Node}}")"

	switch_to_machine "${_utility_service_machine_name}"

	_utility_service_container_id="$(docker ps --filter "name=${_utility_service_name}" --format "{{.ID}}")"
}

execute_utility_process() {
	if [ -z "${_utility_service_container_id}" ]
	then
		echo "Utility service is not yet created" >&2
		return 1
	fi

	switch_to_machine "${_utility_service_machine_name}"

	docker exec ${_utility_service_container_id} $@
}

switch_utility_service_network() {
	if [ -z "${_utility_service_container_id}" ]
	then
		echo "Utility service is not yet created" >&2
		return 1
	fi

	if [ "$1" != "${_utility_service_container_network}" ]
	then
		switch_to_machine "${_utility_service_machine_name}"

		docker network disconnect "${_utility_service_container_network}" "${_utility_service_container_id}"
		_utility_service_container_network="$1"
		docker network connect "${_utility_service_container_network}" "${_utility_service_container_id}"
	fi
}

destroy_utility_service() {
	if [ -z "${_utility_service_name}" ]
	then
		echo "No utility service is running" >&2
		return 1
	fi

	local current_machine_name="${CURRENT_DOCKER_MACHINE_NAME}"
	switch_to_machine "${SWARM_MANAGER_MACHINE_NAME}"
	docker service rm "${_utility_service_name}" > /dev/null

	echo "Utility service ${_utility_service_name} removed"
	echo

	unset _utility_service_container_id _utility_service_container_network _utility_service_machine_name _utility_service_name
}
