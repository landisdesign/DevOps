#!/bin/bash

. ../libs/utils.sh
. ../libs/docker_utils.sh
. ../libs/mongo_utils.sh

# TODO
# Create User:
#	Create secrets
#		Identify secrets data file
#		Identify secrets key file
#		Define entry in secrets file
#	Create user in service
# Delete User:
#	Delete secrets
#	Alert to retained secrets
#	Delete entry in secrets file


# MongoDB DB name restriction: none of /\. "$*<>:|? and less than 64 characters.
# Although UNIX isn't as restricted, I don't want to assume the DB will never be loaded on a Windows machine.
db_filter='[^<>/\. "$*:|?]\{1,63\}'

# This list is copypasta'd from Docker image landisdesign/mongo-authenticated:4.0.3-xenial.
# It must be kept in sync with UserFunctions.js or this script will fail.
valid_user_types=(\
	"dbAdminAnyDatabase"\
	"userAdminAnyDatabase"\
	"backupAdmin"\
	"dbOwner"\
	"readWrite"\
)

usage() {
	echo "mongo_user.sh create [-a <authentication database name>]"
	echo "                     [-d <new user's database name -- default to -a name>]"
	echo "                      -h <host URL>"
	echo "                      -n <network>"
	echo "                      -p <user admin password>"
	echo "                      -q <new user password>"
	echo "                      -t <new user type>"
	echo "                      -u <user admin name>"
	echo "                      -v <new user name>"
	echo
	echo "mongo_user.sh delete [-a <authentication database name>]"
	echo "                     [-d <doomed user's database name -- default to -a name>]"
	echo "                      -f force deletion"
	echo "                      -h <host URL>"
	echo "                      -n <network>"
	echo "                      -p <user admin password>"
	echo "                      -u <user admin name>"
	echo "                      -v <doomed user name>"
	echo
	echo "mongo_user.sh types  Display the valid user types for creating a new user"
	echo
	echo "mongo_user.sh -?     Display this usage information"
}

command="$1"
shift

case "${command}" in
	"create" )
		commanding="creating"
		commanded="created"
		commandment="creation"
		;;
	"delete" )
		commanding="deleting"
		commanded="deleted"
		commandment="deletion"
		;;
	"types" )
		for type in "${valid_user_types[@]}"
		do
			echo "${type}"
		done
		exit
		;;
	"-?"|"help" )
		usage
		exit
		;;
	* )
		echo "Invalid command ${command}" >&2
		usage >&2
		exit
		;;
esac

invalid_opts=""
missing_opts=""
missing_args=""

force=""
authentication_db=""
user_db=""
host=""
network=""
admin_user_name=""
admin_user_password=""
user_name=""
user_password=""
user_type=""

OPTIND=1
while getopts ":a:d:fh:n:p:q:t:u:v:" opt
do
	case "${opt}" in
		"a" ) authentication_db="${OPTARG}" ;;
		"d" ) user_db="${OPTARG}" ;;
		"f" ) force="y" ;;
		"h" ) host="${OPTARG}" ;;
		"n" ) network="${OPTARG}" ;;
		"p" ) admin_user_password="${OPTARG}" ;;
		"q" ) user_password="${OPTARG}" ;;
		"t" ) user_type="${OPTARG}" ;;
		"u" ) admin_user_name="${OPTARG}" ;;
		"v" ) user_name="${OPTARG}" ;;

		":" ) missing_args="${missing_args}${OPTARG}" ;;
		"?" ) invalid_opts="${invalid_opts}${OPTARG}" ;;
	esac
done

shift $((OPTIND - 1))

incomplete=""

authentication_db="${authentication_db:-admin}"
user_db="${user_db:-${authentication_db}}"

if [ -z "${host}" ]
then
	missing_opts="${missing_opts}h"
fi

switch_to_swarm_manager

if [ "${network}" ]
then
	found_network="$(docker network ls --filter "name=${network}" --format "{{.Name}}" | sed -n "s/^${network}\$/&/p" )"
	if [ -z "${found_network}" ]
	then
		echo "Invalid option: -n: Network \"${network}\" not found in swarm"
		incomplete="y"
	fi
else
	missing_opts="${missing_opts}n"
fi

if [ -z "${admin_user_name}" ]
then
	missing_opts="${missing_opts}u"
fi

if [ -z "${admin_user_password}" ]
then
	missing_opts="${missing_opts}p"
fi

if [ -z "${user_name}" ]
then
	missing_opts="${missing_opts}v"
fi

if [ "${command}" = "create" ]
then
	if [ -z "${user_password}" ]
	then
		missing_opts="${missing_opts}q"
	fi

	if [ -z "${user_type}" ]
	then
		missing_opts="${missing_opts}t"
	else
		found=""
		for type in ${valid_user_types[@]}
		do
			if [ "${type}" = "${user_type}" ]
			then
				found="y"
			fi
		done
		if [ -z "${found}" ]
		then
			echo "Invalid option: -t (new user type) is not a valid option" >&2
			incomplete="y"
		fi
	fi

	if [ "${force}" ]
	then
		echo "Invalid option: -f (force deletion) invalid during user creation" >&2
		incomplete="y"
	fi
else
	if [ -z "${force}" ]
	then
		read -p "Are you sure you want to delete \"${user_name}\" from database \"${db_name}\"? (Y/n) " INPUT
		if [ "${INPUT}" != "y" ] && [ "${INPUT}" != "Y" ]
		then
			echo "Exiting without changes"
			echo
			exit 0
		fi
	fi
fi

if [ "${missing_opts}" ]
then
	echo "Missing options: These options are missing to {command} a user: -$(echo "${missing_opts}" | grep -o . | sort | tr -d "\n")" >&2
	incomplete="y"
fi

if [ "${missing_args}" ]
then
	echo "Invalid options: Arguments are missing for -$(echo "${missing_args}" | grep -o . | sort | tr -d "\n")" >&2
	incomplete="y"
fi

if [ "${invalid_opts}" ]
then
	echo "Illegal options: -$(echo "${invalid_opts}" | grep -o . | sort | tr -d "\n") are not valid options." >&2
	incomplete="y"
fi

if [ "${incomplete}" ]
then
	switch_to_original_machine
	exit 1
fi

process_args=(\
	-h "${host}"\
	-a "${authentication_db}"\
	-u "${admin_user_name}"\
	-p "${admin_user_password}"\
	-d "${user_db}"\
	-v "${user_name}"\
)
if [ "${command}" = "create" ]
then
	process_args+=(\
		-q "${user_password}"\
		-t "${user_type}"\
	)
fi

create_utility_service "${network}"
execute_utility_process sh ./user.sh "${command}" ${process_args[@]} 2>./~user-error.txt
destroy_utility_service
switch_to_original_machine

if [ $(ls -n ./~user-error.txt | awk '{print $5}') -gt "0" ]
then
	echo "User ${commandment} failed:" >&2
	cat ./~user-error.txt >&2
else
	echo "User ${commanded}"
fi
echo

rm -f ./~user-error.txt
