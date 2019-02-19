#!/bin/bash
#
# Changes passwords on mongo instances/replica sets deployed as services on the swarm associated with the current machine.
#
# This is a huge task for a shell script, so I'm documenting and breaking it down as best as I can.
#
# Basic code structure is:
#
# 1. Define functions to DRY
# 2. Identify the mongo services deployed on this swarm, and which services to update
# 3. Get the user name and updated password information
# 4. Create command line options for putting all current mongo name and password secrets into utility docker container
# 5. Start the utility service
# 6. Validate that the users are located in secrets accessible to all identified services


#
#	1. Define functions to DRY
#

. ../libs/utils.sh
. ../libs/docker_utils.sh
. ../libs/mongo_utils.sh

awk_make_unique='{a[$1]=1} END {for (i in a) print i}'

service_description() {
	if [ "${service_data_replica[$1]}" == '(none)' ]
	then
		replica_desc=""
	else
		replica_desc="replica set \"${service_data_replica[$1]}\" on "
	fi
	echo -n "${replica_desc} ${service_data_host[$1]} on network ${service_data_network[$1]}"
}

declare -a machine_data
IFS=' ' read -a machine_data <<<"$(dsmachines) "
starting_machine=${machine_data[0]}
swarm_manager=${machine_data[1]}
current_machine=${starting_machine}

switch_to_machine() {
	if [ "$1" != "${current_machine}" ]
	then
		eval $(docker-machine env "$1") 2>&1 1>/dev/null
		current_machine="$1"
	fi
}

#
#	2. Identify the MongoDB services in this swarm and which to update
#

switch_to_machine "${swarm_manager}"
get_service_data

case ${#service_data_host[@]} in
	0)
		echo >&2
		echo "No mongo services with backup labels could be found" >&2
		echo >&2
		switch_to_machine "${starting_machine}"
		exit 1
		;;
	1)	# If only one service, no need to choose -- just use it
		service_index=( 0 )
		;;
	*)
		echo
		echo "CAUTION: This operation updates the secrets stored on the swarm manager. If you"
		echo "only change passwords on some MongoDB services but other services are using"
		echo "those secrets, those services may not authenticate until the passwords on those"
		echo "services are updated to match the new secrets."
		echo
		echo "Choose from one or more of the services below, by number. Choose multiple"
		echo "services by placing spaces or commas between numbers, or by choosing \"a\" for"
		echo "all. Press Enter without choosing a number to exit without changing passwords."
		echo
		for i in ${!service_data_host}
		do
			echo "$(($i + 1)) ) $(service_description $i)"
		done
		echo
		while [ -z "${service_index}" ]
			read -p "Choose one or more numbers between 1 and $((${#service_data_host[@]} + 1)), or \"a\"" service_index
			if [ -z "${service_index}" ]
			then
				echo
				echo "Exiting without changing passwords"
				echo
				switch_to_machine "${starting_machine}"
				exit
			fi
			service_index="$(echo "${service_index}" | tr -s ',' ' ')"
			case "${service_index}" in
				a)
					unset service_index
					declare -a service_index
					IFS=' ' read -a service_index <<<"$(seq 1 ${#service_data_host[@]}) "
					;;
				*[^0-9 ]*)
					echo "  Only numbers commas and spaces, or the letter \"a\" alone, are allowed."
					service_index=""
					;;
				*)
					entries="$(echo "${service_index}" | tr ' ' '\n' | awk ${awk_make_unique})"
					unset service_index
					declare -a service_index
					IFS=' ' read -a service_index <<<"${entries} "
					unset entries
					if [ "${#service_index[@]}" -eq 0 ]
					then
						echo "  At least one entry needs to be made, or press Enter to exit."
						service_index=""
					else
						for i in ${service_index[@]}
						do
							if [ "$i" -gt ${#service_data_host[@]} ]
							then
								echo "Service numbers must be between 1 and ${#service_data_host[@]}."
								service_index=""
								break
							fi
						done
					fi
			esac
			# reorder services by network, to facilitate network switches to access hosts on that network
			if [ "${#service_index[@]}" -gt 1 ]
			then
				echo -n "" > ./~network_order.txt
				for i in ${service_index[@]}
				do
					echo "${service_data_network[$i]} $i" >> ./~network_order.txt
				done
				unset service_index
				declare -a service_index
				IFS=' ' read -a service_index <<<"$(awk '{n[$1]=n[$1] " " $2} END {for (i in n) printf("%s ", n[i])}' ./~network_order.txt)"
				rm ./~network_order.txt
			fi
		do
		done
		;;
esac
echo
echo "Passwords will be changed on:"
for i in ${service_index[@]}
do
	service_description $i
done
echo

#
#	3. Get the user name and updated password information
#

# ALthough MongoDB can take any characters as data, we are restricting names and passwords to not conflict with shell commands.
filter='[a-zA-Z0-9_@!.#%^&()][-a-zA-Z0-9_@!.#%^&()]*'

auth_name=""
auth_pwd=""
user_names=()
user_new_pwds=()

# MongoDB DB name restriction: none of /\. "$*<>:|? and less than 64 characters.
# Although UNIX isn't as restricted, I don't want to assume the DB will never be loaded on a Windows machine.
get_input -f '\\/\\\\. \"[^$*<>:|?]\\{1,63\\}' "Which database are these users in?" "admin"
db="${INPUT}"

# Get new names and passwords
read -p "Are you changing your password or others? (Y/o) " response

if [ "${response}" = "o" ] || [ "${response}" = "O" ]
then
	get_input -f ${filter} "Admin name:"
	auth_name="${INPUT}"
	get_input -f ${filter} -s "Admin password:"
	auth_pwd="${INPUT}"
	while [ "${INPUT}" ] || [ "${#user_names[@]}" -eq 0 ]
	do
		echo
		get_input -e -f ${filter} "User $(( ${#user_names[@]} + 1)) (Return to exit loop):"
		if [ "${INPUT}" ]
		then
			user_names+=( "${INPUT}" )
			get_input -f ${filter} -s "User $(( ${#user_names[@]})) new password:"
			user_new_pwds+=( "${INPUT}" )
		fi
	done
else
	get_input -f ${filter}  "User name:"
	auth_name="${INPUT}"
	user_names+=( "${INPUT}" )
	get_input -f ${filter} -s "Old password:"
	auth_pwd="${INPUT}"
	get_input -f ${filter} -s "New password:"
	user_new_pwds+=( "${INPUT}" )
fi

#
#	4. Create command line options for putting all current mongo name and password secrets into utility docker container
#

define -a docker_secrets
IFS=' ' read -a docker_secrets <<<"$(../define/secrets.sh -v ../define/secrets_combined.txt | awk '/^mongo_[^ ]*(_name|pwd) / {printf ("--secret source=%s_v%s,target=%s ", $1, $2, $1)}')"

#
#	5. Start the utility service
#

echo
echo "Starting up utility service..."
echo

current_network="${service_data_network[${service_index[0]}]}"

docker_image=landisdesign/mongo-authenticated-utilities:4.0.3-xenial
docker_service_name="mongo_password_$RANDOM"
docker_args=( \
	--name ${docker_service_name} \
	--limit-memory "256MB" \
	--network ${current_network} \
	--entrypoint "tail -f </dev/null" \
)
docker service create ${docker_args[@]} ${docker_secrets[@]} ${docker_image}

service_machine="$(docker service ps "${docker_service_name}" --format "{{.Node}}")"

switch_to_machine "${service_machine}"

container_id="$(docker ps --filter "name=${docker_service_name}" --format "{{.ID}}")"

#
#	6. Validate that the users are located in secrets accessible to all identified services
#

echo
echo "Ensuring that users exist in the secrets available to the services being updated..."
echo

echo -n "" > ./~valid_secrets.txt
echo -n "" > ./~invalid_secrets.txt
for i in ${service_index[@]}
do
	if [ "${service_data_network[$i]}" != "${current_network}" ]
	then
		docker network disconnect "${current_network}" "${container_id}"
		current_network="${service_data_network[$i]}"
		docker network connect "${current_network}" "${container_id}"
	fi
	docker exec ${container_id} sh /secret_search.sh mongo_*_name ${auth_name} ${user_names[@]} 1>>./~valid_secrets.txt 2>>./~invalid_secrets.txt
done

if [ $(ls -n ./~invalid_secrets.txt | awk '{print $5}') -gt "0" ]
then
	echo >&2
	echo "The following user names could not be found:" >&2
	echo "$(sed -n 's/^[^:]*: \(.*\)$/\1/gp' < ./~invalid_secrets.txt | tr -d "'" | tr -s ' ' '\n' | awk ${awk_make_unique} | sort -f | awk '{print "  " $0}')" >&2
	echo >&2
	rm ./~invalid_secrets.txt ./~valid_secrets.txt
	switch_to_machine "${starting_machine}"
	exit 1
fi

