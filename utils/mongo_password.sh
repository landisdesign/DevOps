#!/bin/bash
#
# Changes passwords on mongo instances/replica sets deployed as services on the swarm associated with the current machine.
#
# This is a huge task for a shell script, so I'm documenting and breaking it down as best as I can.
#
# Basic code structure is:
#
# 1. Define functions/variables for DRYing
# 2. Identify the mongo services deployed on this swarm, and which services to update
# 3. Get the database, user name and updated password information
# 4. Start utility service with the mongo_* name and pwd secrets
# 5. Validate that the users are located in secrets accessible to all identified services
# 6. Set up environment variables for password change
# 7. Cycle through services and update passwords
# 8. Check for errors in password changes in services
# 9. Update secrets

#
#	1. Define functions to DRY
#

. ../libs/utils.sh
. ../libs/docker_utils.sh
. ../libs/mongo_utils.sh

awk_make_unique='{a[$0]=1} END {for (i in a) print i}'

dsmachines

starting_machine_name="${CURRENT_DOCKER_MACHINE_NAME}"

clean_up() {
	destroy_utility_service
	rm -f ./~invalid_secrets.txt ./~password_data.txt ./~password_error*.txt ./~valid_secrets.txt
	switch_to_machine "${starting_machine_name}"
}

#
#	2. Identify the MongoDB services in this swarm and which to update
#

switch_to_machine "${SWARM_MANAGER_MACHINE_NAME}"
get_service_data

case ${#service_data_host[@]} in
	0)
		echo >&2
		echo "No mongo services with backup labels could be found" >&2
		echo >&2
		switch_to_machine "${starting_machine_name}"
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
			echo "$(($i + 1)) ) ${service_data_description[$i]}"
		done
		echo
		while [ -z "${service_index}" ]
		do
			read -p "Choose one or more numbers between 1 and $((${#service_data_host[@]} + 1)), or \"a\"" service_index
			if [ -z "${service_index}" ]
			then
				echo
				echo "Exiting without changing passwords"
				echo
				switch_to_machine "${starting_machine_name}"
				exit
			fi
			service_index="$(echo "${service_index}" | tr -s ',' ' ')"
			case "${service_index}" in
				a )
					unset service_index
					declare -a service_index
					IFS=' ' read -a service_index <<<"$(seq 1 ${#service_data_host[@]}) "
					;;
				*[!\ 0-9]* )
					echo "  Only numbers commas and spaces, or the letter \"a\" alone, are allowed."
					service_index=""
					;;
				* )
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
		done
		;;
esac

declare -a hosts
declare -a networks
for i in ${service_index[@]}
do
	networks+=( "${service_data_network[$i]}" )
	if [ "${service_data_replica[$i]}" = "(none)" ]
	then
		hosts+=( "${service_data_host[$i]}" )
	else
		hosts+=( "${service_data_replica[$i]}/${service_data_host[$i]}" )
	fi
done


echo
echo "Passwords will be changed on:"
for i in ${service_index[@]}
do
	echo " * ${service_data_description[$i]}"
done
echo

#
#	3. Get the database, user name and updated password information
#

# Although MongoDB can take any characters as data, we are restricting names and passwords to not conflict with shell commands.
user_filter='[a-zA-Z0-9_@!.#%^&()][-a-zA-Z0-9_@!.#%^&()]*'

# MongoDB DB name restriction: none of /\. "$*<>:|? and less than 64 characters.
# Although UNIX isn't as restricted, I don't want to assume the DB will never be loaded on a Windows machine.
db_filter='[^<>/\. "$*:|?]\{1,63\}'

auth_user=""
auth_pwd=""
auth_db=""
user_names=()
user_new_pwds=()
user_db=""

# Get new names and passwords
read -p "Are you changing your password or others? (Y/o) " response
echo

if [ "${response}" = "o" ] || [ "${response}" = "O" ]
then
	get_input -f "${db_filter}" "Which database do you authenticate to?" "admin"
	auth_db="${INPUT}"
	get_input -f "${user_filter}" "Admin name:"
	auth_user="${INPUT}"
	get_input -f "${user_filter}" -s "Admin password:"
	auth_pwd="${INPUT}"
	echo
	read -p "Are the other users in the same database? (Y/n) " INPUT
	if [ "${INPUT}" = "n" ] || [ "${INPUT}" = "N" ]
	then
		get_input -f "${db_filter}" "Which database are the users located in?" ${auth_db}
		user_db="${INPUT}"
	else
		user_db="${auth_db}"
	fi
	while [ "${INPUT}" ] || [ "${#user_names[@]}" -eq 0 ]
	do
		echo
		get_input -e -f "${user_filter}" "User $(( ${#user_names[@]} + 1)) (Return to exit loop):"
		if [ "${INPUT}" ]
		then
			_temp_user_name="${INPUT}"
			user_names+=( "${_temp_user_name}" )
			get_input -f "${user_filter}" -s "New password for ${_temp_user_name}:"
			user_new_pwds+=( "${INPUT}" )
		fi
	done
else
	get_input -f "${db_filter}" "Database:" "admin"
	auth_db="${INPUT}"
	user_db="${auth_db}"
	get_input -f "${user_filter}"  "User name:"
	auth_user="${INPUT}"
	user_names+=( "${INPUT}" )
	get_input -f "${user_filter}" -s "Old password:"
	auth_pwd="${INPUT}"
	get_input -f "${user_filter}" -s "New password:"
	user_new_pwds+=( "${INPUT}" )
fi
echo

#
#	4. Start utility service with the mongo_* name and pwd secrets
#

declare -a docker_secrets
IFS=' ' read -a docker_secrets <<<"$(../define/secrets.sh -v ../define/secrets_combined.txt | awk '/^mongo_[^ ]*(_name|pwd) / {printf ("--secret source=%s_v%s,target=%s ", $1, $2, $1)}')"
create_utility_service "${networks[0]}" ${docker_secrets[@]}

#
#	5. Validate that the users are located in secrets accessible to all identified services
#

echo "Ensuring that users exist in the secrets available on the networks being updated..."

rm -f ./~valid_secrets.txt ./~invalid_secrets.txt
touch ./~valid_secrets.txt ./~invalid_secrets.txt

for network in ${networks[@]}
do
	switch_utility_service_network "${network}"
	execute_utility_process sh /secret_search.sh mongo_*_name ${auth_user} 2>>./~invalid_secrets.txt 1>/dev/null
	execute_utility_process sh /secret_search.sh mongo_*_name ${user_names[@]} 2>>./~invalid_secrets.txt | awk '{for (i=2;i<=NF;i++)gsub(/_name$/, "_pwd", $i);}1' 1>>./~valid_secrets.txt
done

if [ $(ls -n ./~invalid_secrets.txt | awk '{print $5}') -gt "0" ]
then
	echo >&2
	echo "The following user names could not be found:" >&2
	echo "$(sed -n 's/^[^:]*: \(.*\)$/\1/gp' < ./~invalid_secrets.txt | tr -d "'" | tr -s ' ' '\n' | awk "${awk_make_unique}" | sort -f | awk '{print "  " $0}')" >&2
	echo "None of the passwords were changed."
	echo
	clean_up
	exit 1
fi

#
#	6. Set up options for change_password.sh
#
#	Host information will be added for each cycle through the list of services chosen.
#

declare -a change_password_args
change_password_args+=( -a "${auth_db}" )
change_password_args+=( -u "${auth_user}" )
change_password_args+=( -p "${auth_pwd}" )
change_password_args+=( -d "${user_db}" )
for i in ${!user_new_pwds[@]}
do
	change_password_args+=( -c "${user_names[$i]}=${user_new_pwds[$i]}" )
done

#
#	7. Cycle through services and update passwords
#

echo
echo "Updating services"

failed_services=()
successful_services=()

for i in ${!hosts[@]}
do
	switch_utility_service_network "${networks[$i]}"
	execute_utility_process sh /password.sh ${change_password_args[@]} -h ${hosts[$i]} 2>./~password_error${i}.txt 1>/dev/null 
	if [ $(ls -n ./~password_error${i}.txt | awk '{print $5}') -gt "0" ]
	then
		echo " ! ${hosts[$i]}"
		failed_services+=( $i )
	else
		echo " * ${hosts[$i]}"
		successful_services+=( $i )
	fi
done

#
#	8. Check for errors in password changes in services
#

if [ ${#failed_services[@]} -gt 0 ]
then
	echo "Passwords were not changed on the following services:" >&2
	echo >&2
	for i in ${!failed_services[@]}
	do
		echo "${hosts[$i]}:" >&2
		cat ./~password_error${i}.txt >&2
		echo >&2
	done

	if [ ${#successful_services[@]} -eq 0 ]
	then
		echo "Passwords and secrets have not been updated." >&2
		echo >&2
		clean_up
		exit 1
	else
		prompt -p "Your updated services are out of sync with your secrets. Do you want to update your secrets? Doing so will put your other services out of sync. (y/N) " INPUT
		echo >&2
		if [ "${INPUT}" != "Y" ] && [ "${INPUT}" != "y" ]
		then
			echo "Passwords have been updated on the following services:" >&2
			for i in ${successful_services[@]}
			do
				echo " * ${service_data_description[${service_index[$i]}]}" >&2
			done
			echo "Passwords have not been changed on the following services:" >&2
			for i in ${failed_services[@]}
			do
				echo " * ${service_data_description[${service_index[$i]}]}" >&2
			done
			echo >&2
			clean_up
			exit 1
		fi
	fi
else
	echo
	echo "Services updated"
	echo
fi

#
#	9. Update secrets
#

rm -f ./~password_data.txt
touch ./~password_data.txt

for i in ${!user_names[@]}
do
	echo "${user_names[$i]} ${user_new_pwds[$1]}" >> ./~password_data.txt
done

secret_args=( -k ../secret_keys.sh )

secrets="$(awk 'NR==FNR {u[$1]=$2} NR!=FNR && ($1 in u) {for (i=2;i<=NF;i++) print $i, u[$1]}' ./~password_data.txt ./~valid_secrets.txt)"
while read name value
do
	secret_args+=( -u "${name}=${value}" )
done <<<"${secrets}"

secret_args+=( ../define/secrets_combined.txt )

../define/secrets.sh ${secret_args[@]}

clean_up

echo "Password update completed. Please back up affected services to keep those changes recorded upon restart."
echo
