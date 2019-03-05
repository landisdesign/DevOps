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
		service_data_description+=("${_desc}${_replica} on network ${_network}")
	done <<< "$(awk -f ../libs/translate_network.awk ./~network_data.txt ./~backup_data.txt )"
	unset service_data_line _backup _network _host _replica _desc
	rm ./~network_data.txt ./~backup_data.txt
}
