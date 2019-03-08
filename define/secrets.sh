#!/bin/bash

. ../libs/docker_utils.sh

usage(){
	echo "Usage:"
	echo "  secrets -n input-file"
	echo "  secrets -v [-s secret-name]... input-file"
	echo "  secrets [-qr] [-d data-file] [-k key-file] [-s secret-name]... input-file"
	echo "  secrets [-r] [-d data-file] [-k key-file] [-u name=value]... input-file"
	echo
	echo "  -d data-file     Data file. The name of a file to output updated secret"
	echo "                   names and values. If not provided, updates will be saved"
	echo "                   directly to the swarm manager. This option is ignored if -q"
	echo "                   is included."
	echo
	echo "  -k key-file      Key file. The name of the file to output environment variable"
	echo "                   settings for use in Docker Swarm compose files."
	echo
	echo "  -n               Names. Return the names of the secrets kept in file. No other"
	echo "                   arguments other than input-file can be included in this"
	echo "                   version of the command or an error will result."
	echo
	echo "  -q               Quiet. Does not request or save new data. Only perform the"
	echo "                   operations requested by -k or -r. This option is superfluous"
	echo "                   when -u options are provided."
	echo
	echo "  -r               Remove secrets. Removes the previous versions of the"
	echo "                   specified secrets, or the previous versions of all secrets"
	echo "                   identified in the input file(s) if no -s options are"
	echo "                   provided."
	echo
	echo "  -s secret-name   Secret name. The name of the secret to be managed. This"
	echo "                   option can be repeated with different secret names. If not"
	echo "                   provided, all secrets in the provided files will be managed."
	echo "                   If -s options are included, -u options cannot be included."
	echo "                   identifying secret names with -s presumes that any value"
	echo "                   updates are interactive, while -u presumes that any value"
	echo "                   updates are not."
	echo
	echo "  -u name=value    Update the named with the provided value. If one or more of"
	echo "                   these options are included, secrets will not be interactive,"
	echo "                   as if the -q option were included. -s options are not"
	echo "                   permitted in the same command as -u options. -d, -r and -k"
	echo "                   options will be executed after the secrets named in -u"
	echo "                   options are updated."
	echo
	echo "  -v               Version. Return the current version number for the secrets"
	echo "                   identified by -s option, or all version numbers, then exit."
	echo "                   If more than one secret is provided, the secret name"
	echo "                   precedes the version number. No arguments other than"
	echo "                   input-file can be included with this version of the command."
	echo
	echo "  input-file       The file to read secret information from and store the new"
	echo "                   version number in. Each line in the file should be in the"
	echo "                   following format:"
	echo
	echo "                   secret-name descriptive-text version-number default-value"
	echo
	echo "                   If a field requires a space, wrap the value in quotes."
	echo
}

#
#	Get options
#

if [ $# -eq 0 ]
then
	usage
	exit
fi

secrets_requested=()
secrets_values=()
key_file=""
version_requested=0
remove_old_secrets=0
return_names=0
quiet=0
automated=0

blocking_argument=""
last_argument=""

OPTIND=1
while getopts ":k:d:nqrs:u:v" opt
do
	if [ "${blocking_argument}" ]
	then
		if [ "${blocking_argument}" != "v" ] || [ "${opt}" != "s" ]
		then
			echo "Invalid option -${opt}: no other arguments are permitted when -${blocking_argument} is present." 1>&2
			exit 1
		fi
	fi
	case ${opt} in
		"d" )
			if [ "${data_file}" ]
			then
				echo "Invalid option: Only one -d (data file) option can be specified." 1>&2
				exit 1
			fi
			data_file=${OPTARG}
			;;

		"k" )
			if [ "${key_file}" ]
			then
				echo "Invalid option: Only one -k (key file) option can be specified." 1>&2
				exit 1
			fi
			key_file=${OPTARG}
			;;

		"n" )
			if [ "${last_argument}" ]
			then
				echo "Invalid option: -n cannot be present with other arguments." 1>&2
				exit 1
			fi
			return_names=1
			blocking_argument="${opt}"
			;;

		"q" )
			quiet=1
			;;

		"r" )
			remove_old_secrets=1
			;;

		"s" )
			if [ "${#secrets_values[@]}" -gt 0 ]
			then
				echo "Invalid option: -s options cannot be present if -u options are included." 1>&2
				exit 1
			fi
			secrets_requested+=(${OPTARG})
			;;

		"u" )
			if [ "${#secrets_values[@]}" -ne "${#secrets_requested[@]}" ]
			then
				echo "Invalid option: -u options cannot be present if -s options are included." 1>&2
				exit 1
			fi
			IFS='=' read _name _value <<<"${OPTARG}"
			secrets_requested+=( ${_name} )
			secrets_values+=( "${_value}" )
			automated=1
			;;

		"v" )
			if [ "${last_argument}" ] && [ "${last_argument}" != "s" ]
			then
				echo "Invalid option: -v cannot be present if arguments other than -s are included." 1>&2
				exit 1
			fi
			version_requested=1
			;;

		":" )
			echo "Invalid option: ${OPTARG} requires an argument." 1>&2
			exit 1
			;;

		"?" )
			echo "Invalid option: ${OPTARG}" 1>&2
			usage
			exit 1
			;;
	esac
	last_argument="${opt}"
done
shift $((OPTIND-1))
file=$1

if [ ! -f "${file}" ]
then
	echo "${file} does not exist."
	exit 1
fi

#
#	Collect data from input files
#

secrets_name=()
secrets_text=()
secrets_version=()
secrets_default=()
secrets_requested_index=()

while IFS=$'\n' read -r list_data || [ -n "${list_data}" ]
do
	IFS=$'\n' list_params=( $( xargs -n 1 <<<"${list_data}" ) )
	secrets_name+=(${list_params[0]})
	secrets_text+=(${list_params[1]})
	secrets_version+=(${list_params[2]})
	secrets_default+=(${list_params[3]:-""})
done < "$file"

# Map request secret names to indices in secrets lists
if [ ${#secrets_requested[@]} -eq 0 ]
then
	secrets_requested_index=( $( seq 0 $(( ${#secrets_name[@]} - 1 )) ) )
else
	for request in ${secrets_requested[@]}
	do
		found=0
		for i in ${!secrets_name[@]}
		do
			if [ ${found} -eq 0 ] && [ "${request}" = "${secrets_name[$i]}" ]
			then
				found=1
				secrets_requested_index+=($i)
			fi
		done
	done
fi

# Handle -n option and exit
if [ "${return_names}" -eq 1 ]
then
	for name in ${secrets_name[@]}
	do
		echo "${name}"
	done
	exit
fi

# Confirm requested secret names are present in input files
if [ ${#secrets_requested[@]} -ne 0 ] && [ ${#secrets_requested[@]} -ne ${#secrets_requested_index[@]} ]
then
	missing_secrets=()
	for requested_name in ${secrets_requested[@]}
	do
		found=0
		for i in ${secrets_requested_index[@]}
		do
			if [ "${requested_name}" = "${secrets_name[$i]}" ]
			then
				found=1
			fi
		done
		if [ ${found} -eq 0 ]
		then
			missing_secrets+=( "${requested_name}" )
		fi
	done
	echo "${missing_secrets[@]} not found" 1>&2
	exit 1
fi

#
#	Output version info and exit if requested
#

if [ "${version_requested}" -eq 1 ]
then
	if [ "${#secrets_requested[@]}" -eq 1 ]
	then
		i=${secrets_requested_index[0]}
		echo "${secrets_version[$i]}"
	else
		for i in ${secrets_requested_index[@]}
		do
			echo "${secrets_name[$i]} ${secrets_version[$i]}"
		done
	fi
	exit
fi

#
#	Gather updated secrets data
#

updated_secrets_name=()
updated_secrets_value=()
updated_secrets_version=()

if [ "${quiet}" -eq 0 ] || [ "${automated}" -eq 1 ]
then

	for i in ${!secrets_requested_index[@]}
	do
		j=${secrets_requested_index[$i]}

		if [ "${automated}" -eq 0 ]
		then
			default_value="${secrets_default[$j]}"
			default_text="${secrets_text[$j]}"

			if [ "${default_value}" ]
			then
				prompt="${default_text} (${default_value}):"
			else
				prompt="${default_text}: "
			fi

			value=""
			while [ -z "${value}" ]
			do
				read -p "${prompt}" value
				if [ -z "${value}" ]
				then
					if [ "${default_value}" ]
					then
						value="${default_value}"
					else
						echo "  ${default_text} cannot be empty. Please enter a value."
					fi
				fi
			done
		else
			value="${secrets_values[$i]}"
		fi

		updated_secrets_name+=("${secrets_name[$j]}")
		updated_secrets_value+=("${value}")
		updated_secrets_version+=( $((${secrets_version[$j]} + 1)) )
	done
else
	for i in ${secrets_requested_index[@]}
	do
		updated_secrets_name+=("${secrets_name[$i]}")
		updated_secrets_version+=("${secrets_version[$i]}")
	done
fi

#
#	Output updated secret version information to files
#

echo -n "" > "${file}"
if [ "${key_file}" ]
then
	echo -n "" > "${key_file}"
fi

for i in ${!secrets_name[@]}
do
	secret_name=${secrets_name[$i]}
	secret_text=${secrets_text[$i]}
	secret_version=${secrets_version[$i]}
	for j in ${!updated_secrets_name[@]}
	do
		if [ "${secret_name}" == "${updated_secrets_name[$j]}" ]
		then
			secret_version=${updated_secrets_version[$j]}
		fi
	done
	secret_default=${secrets_default[$i]}
	echo "\"${secret_name}\" \"${secret_text}\" \"${secret_version}\" \"${secret_default}\"" >> "${file}"

	if [ "${key_file}" ]
	then
		echo "export ${secret_name}_SECRET_VERSION=${secret_version};" >> "${key_file}"
	fi
done

#
#	Output updated secret names and values for retrieval by calling program
#

dsmachines
original_machine="${CURRENT_DOCKER_MACHINE_NAME}"

if [ "${quiet}" -eq 0 ] || [ "${automated}" -eq 1 ]
then
	if [ "${data_file}" ]
	then
		echo -n "" > "${data_file}"
		for i in ${!updated_secrets_name[@]}
		do
			echo "${updated_secrets_name[$i]}_v${updated_secrets_version[$i]} \"${updated_secrets_value[$i]}\"" >> "${data_file}"
		done
	else
		#
		#	Put updated secrets into swarm
		#

		switch_to_machine "${SWARM_MANAGER_MACHINE_NAME}"

		echo "Updating secrets..."
		for i in ${!updated_secrets_name[@]}
		do
			echo "    ${updated_secrets_name[$i]}_v${updated_secrets_version[$i]}"
			push_secret "${updated_secrets_name[$i]}_v${updated_secrets_version[$i]}" "${updated_secrets_value[$i]}"
		done

		echo
		echo "Secrets updated"
		echo
	fi
fi

if [ "${remove_old_secrets}" -eq 1 ]
then
	echo
	echo "Removing old secrets"
	echo

	echo -n "" > ./~secrets-current.txt
	secrets_filters=()
	for i in ${!updated_secrets_name[@]}
	do
		filter_value="${updated_secrets_name[$i]}_v"
		secrets_filters+=( "${filter_value}" )
		echo "${filter_value} ${updated_secrets_version[$i]}" >> ./~secrets-current.txt
	done

	switch_to_machine "${SWARM_MANAGER_MACHINE_NAME}"

	get_secrets "name" ${secrets_filters[@]} >./~secret-names.txt

	doomed_secrets=( $( awk 'function different(f, i,n) {i = match(f, /_v[0-9]+$/); if (i) {n=substr(f,1,i+1);if (n in v) return (0+substr(f,i+2)) != v[n]} } FNR == NR {v[$1] = (0+$2)} FNR != NR && different($0)' ./~secrets-current.txt ./~secret-names.txt ) )

	rm ./~secret-names.txt ./~secrets-current.txt

	if [ "${#doomed_secrets[@]}" -gt 0 ]
	then
		define -a retained_secrets
		IFS=' ' read -a retained_secrets <<<"$( remove_secrets ${doomed_secrets[@]} ) "

		echo "Old secrets removed"
		echo

		if [ ${#retained_secrets[@]} -ne 0 ]
		then
			echo "The following secrets are still being used:" >&2
			for retained_secret in ${retained_secrets[@]}
			do
				echo "  ${retained_secret}" >&2
			done
			echo
		fi
	else
		echo "No old secrets to remove"
		echo
	fi
fi

switch_to_machine "${original_machine}"
