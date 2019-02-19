get_service_data() {
	docker inspect --format "{{.Id}} {{.Name}}" $(docker network ls -q) > ./~network_data.txt
	docker service inspect --format '{{index .Spec.TaskTemplate.ContainerSpec.Labels "com.michael-landis-awakening.mongodb.backup-name"}}!{{index (index .Spec.TaskTemplate.Networks 0).Target}}!{{.Spec.TaskTemplate.ContainerSpec.Hostname}}!{{index .Spec.TaskTemplate.ContainerSpec.Labels "com.michael-landis-awakening.mongodb.replica-name"}}' $(docker service ls -q) | awk -f ../libs/collect_mongo_hosts.awk > ./~backup_data.txt
	service_data_backup=()
	service_data_network=()
	service_data_host=()
	service_data_replica=()
	while IFS= read -r service_data_line
	do
		declare -a service_data_fields
		IFS=' ' read -a service_data_fields <<<"${service_data_line} "
		service_data_backup+=(${service_data_fields[0]})
		service_data_network+=(${service_data_fields[1]})
		service_data_host+=(${service_data_fields[2]})
		service_data_replica+=(${service_data_fields[3]})
		unset service_data_fields
	done <<< "$(awk -f ../libs/translate_network.awk ./~network_data.txt ./~backup_data.txt )"
	unset service_data_line
	rm ./~network_data.txt ./~backup_data.txt
}

get_password_secret_names() {
	contents="$(cat ${1:-/dev/stdin})"
	echo "$contents" | sed -n 's/^\([^ ]*\) *mongo_\([^ ]*\)_name$/\1 mongo_\2_pwd/p'
}