#!/bin/bash

. ../libs/utils.sh
. ../libs/docker_utils.sh
. ../libs/mongo_utils.sh

usage() {
	echo "mongo_database.sh create [-a <authentication-database>]"
	echo "                          -h <database host url>"
	echo "                          -n <docker network>"
	echo "                          -p <db-admin-pwd>"
	echo "                          -u <db-admin-user>"
	echo "                          <new-database-name>"
	echo
	echo "mongo_database.sh delete [-a <authentication-database>]"
	echo "                          -f"
	echo "                          -h <database host url>"
	echo "                          -n <docker network>"
	echo "                          -p <db-admin-pwd>"
	echo "                          -u <db-admin-user>"
	echo "                          <doomed-database-name>"
}

# MongoDB DB name restriction: none of /\. "$*<>:|? and less than 64 characters.
# Although UNIX isn't as restricted, I don't want to assume the DB will never be loaded on a Windows machine.
db_filter='[^<>/\. "$*:|?]\{1,63\}'

command="$1"
shift

case "${command}" in
	"create" )
		commanding="creating"
		commanded="created"
		;;
	"delete" )
		commanding="deleting"
		commanded="deleted"
		;;
	"-?" | "help" )
		usage
		exit
		;;
	* )
		echo "Invalid command ${command}:" >&2
		usage >&2
		exit
		;;
esac

authentication_db=""
db_name=""
db_admin_name=""
db_admin_password=""
force=""
host=""
network=""
interactive=""
invalid_args=""
missing_args=""

OPTIND=1
while getopts ":a:fh:n:p:u:" opt
do
	case "${opt}" in
		"a" ) authentication_db="${OPTARG}" ;;
		"f" ) force="y" ;;
		"h" ) host="${OPTARG}" ;;
		"n" ) network="${OPTARG}" ;;
		"p" ) db_admin_password="${OPTARG}" ;;
		"u" ) db_admin_user="${OPTARG}" ;;

		":" ) missing_args="${missing_args} -${OPTARG}" ;;
		"?" ) invalid_args="${invalid_args} -${OPTARG}" ;;
	esac
done

dsmachines

starting_machine_name="${CURRENT_DOCKER_MACHINE_NAME}"
switch_to_machine "${SWARM_MANAGER_MACHINE_NAME}"

incomplete=""

shift $(( OPTIND - 1 ))
db_name="$1"

authentication_db="${authentication_db:-admin}"

if [ "${force}" ] && [ "${command}" != "delete" ]
then
	echo "Invalid option: -f (force) option is only valid with delete" >&2
	incomplete="y"
fi

if [ -z "${host}" ]
then
	echo "Missing option: -h (host) required" >&2
	incomplete="y"
fi

if [ "${network}" ]
then
	found_network="$(docker network ls --filter "name=${network}" --format "{{.Name}}" | sed -n "s/^${network}$$/&/p" )"
	if [ -z "${found_network}" ]
	then
		echo "Invalid option: -n: Network \"${network}\" not found in swarm"
		incomplete="y"
	fi
else
	echo "Missing option: -n (network) required" >&2
	incomplete="y"
fi

if [ -z "${db_admin_password}" ]
then
	echo "Missing option: -p (database manager password) required" >&2
	incomplete="y"
fi

if [ -z "${db_admin_user}" ]
then
	echo "Missing option: -u (database manager user name) required" >&2
	incomplete="y"
fi

if [ -z "${db_name}" ]
then
	echo "Missing database name" >&2
	incomplete="y"
else
	if [ "$(echo "$1" | sed "s/^${db_filter}$$/&/" )" != "$1" ]
	then
		echo "Database name \"${db_name}\" can not include any of <>/\\. \"$*:|? and must be less than 64 characters in length." >&2
		incomplete="y"
	fi
fi

if [ "${invalid_args}" ]
then
	echo "Invalid args: the following options aren't valid:${invalid_args}" >&2
	incomplete="y"
fi

if [ "${missing_args}" ]
then
	echo "Missing args: the following options are missing their arguments:${missing_args}" >&2
	incomplete="y"
fi

if [ "${incomplete}" ]
then
	exit 1
fi

if [ "${command}" = "delete" ] && [ -z "${force}" ]
then
	prompt "Database \"${db_name}\" will be removed from ${service_data_description[${service_index}]}. Are you sure you want to do this? (y/N) " INPUT
	if [ "${INPUT}" != "y" ] && [ "${INPUT}" != "Y" ]
	then
		echo "Database deletion cancelled."
		exit 0
	fi
fi

create_service_utility "${network}"

echo "${commanding} database \"${db_name}\""
echo

execute_utility_process sh /database.sh $command -h "${host}" -a "${admin_db}" -u "${db_admin_user}" -p "${db_admin_password}" "${db_name}" 2>./~database-error.txt

if [ $(ls -n ./~database-error.txt | awk '{print $5}') -gt "0" ]
then
	echo "Error occurred creating database \"${db_name}\" on host ${host} on network ${network}:" >&2
	cat ./~database-error.txt >&2
	echo >&2
	rm -f ./~database-error.txt
	exit 1
else
	rm -f ./~database-error.txt
	echo "Database \"${db_name}\" ${commanded}"
	echo
fi

destroy_utility_process
