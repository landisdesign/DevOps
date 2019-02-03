#!/bin/bash

. ./docker_utils.sh

usage(){
	echo
	echo "Usage: secret [-s secret-name] [-c combined-file] [-d data-file] [-v] file [file...]"
	echo
	echo "  -s secret-name   The name of the secret to be updated. This option can be"
	echo "                   repeated with different secret names. If not provided, all"
	echo "                   secret data in the provided files will be updated."
	echo
	echo "  -c combined-file The name of the file to output combined version data to."
	echo "                   The data provided in the input files will be combined"
	echo "                   into this file, leaving the original files untouched."
	echo
	echo "  -r               Removes the previous version of the specified secrets. If"
	echo "                   this option is specified, -k and -d are ignored, and no"
	echo "                   updated data is requested."
	echo
	echo "  -k key-file      The name of the file to output environment variable"
	echo "                   settings for use in Docker Swarm compose files"
	echo
	echo "  -d data-file     The name of the file to output updated secret names and"
	echo "                   values. This should be deleted immediately after the"
	echo "                   data has been placed into the relevant secrets."
	echo
	echo "  -v               Return the current version number for the secrets"
	echo "                   identified by -s option, or all version numbers. If more"
	echo "                   than one secret is provided, the secret name precedes the"
	echo "                   version number."
	echo
	echo "                   If neither -v nor -d are provided, the updated data will"
	echo "                   be stored as secrets on the swarm manager."
	echo
	echo "  file [file...]   The files to read secret information from. At least one"
	echo "                   file must be provided. Each line in a file should be in"
	echo "                   the following format:"
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
combined_file=""
key_file=""
version_requested=0
old_secrets_removed=0

OPTIND=1
while getopts ":s:c:k:d:vr" opt
do
	case ${opt} in
		"s" )
			secrets_requested+=(${OPTARG})
			;;

		"c" )
			if [ "${combined_file}" ]
			then
				echo "Invalid option: Only one -c (combined file) option can be specified." 1>&2
				exit 1
			fi
			combined_file=${OPTARG}
			;;

		"k" )
			if [ "${key_file}" ]
			then
				echo "Invalid option: Only one -k (key file) option can be specified." 1>&2
				exit 1
			fi
			key_file=${OPTARG}
			;;

		"d" )
			if [ "${data_file}" ]
			then
				echo "Invalid option: Only one -d (data file) option can be specified." 1>&2
				exit 1
			fi
			data_file=${OPTARG}
			;;

		"v" )
			version_requested=1
			;;

		"r" )
			old_secrets_removed=1
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
done
shift $((OPTIND-1))
files_requested=($@)

if [ -z "${files_requested}" ]
then
	echo "No files identified. At least one file must be identified."
	exit 1
fi
for file in ${files_requested[@]}
do
	if [ ! -e "${file}" ]
	then
		echo "File not found: ${file}"
		exit 1
	fi
done

#
#	Collect data from input files
#

secrets_name=()
secrets_text=()
secrets_version=()
secrets_default=()
secrets_index=()

for file in ${files_requested[@]}
do
	while IFS=$'\n' read -r list_data || [ -n "${list_data}" ]
	do
		IFS=$'\n' list_params=( $( xargs -n1 <<<"${list_data}" ) )
		current_secret_index=${#secrets_name[@]}
		current_secret_name=${list_params[0]}
		secrets_name+=(${current_secret_name})
		secrets_text+=(${list_params[1]})
		secrets_version+=(${list_params[2]})
		secrets_default+=(${list_params[3]:-""})
		secrets_file+=($file)
		if [ ${#secrets_requested[@]} -eq 0 ]
		then
			secrets_index+=(${current_secret_index})
		else
			found=0
			for request in ${secrets_requested[@]}
			do
				if [ ${found} -eq 0 ] && [ "${request}" = "${current_secret_name}" ]
				then
					found=1
					secrets_index+=(${current_secret_index})
				fi
			done
		fi
	done < "$file"
done

# Confirm requested secret names are present in input files
if [ ${#secrets_requested[@]} -ne 0 ] && [ ${#secrets_requested[@]} -ne ${#secrets_index[@]} ]
then
	missing_secrets=()
	for requested_name in ${secrets_requested[@]}
	do
		found=0
		for i in ${secrets_index[@]}
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
		i=${secrets_index[0]}
		echo "${secrets_version[$i]}"
	else
		for i in ${secrets_index[@]}
		do
			echo "${secrets_name[$i]} ${secrets_version[$i]}"
		done
	fi
	if [ "${old_secrets_removed}" -eq 0 ]
	then
		exit
	fi
fi

#
#	Gather updated secrets data
#

updated_secrets_name=()
updated_secrets_value=()
updated_secrets_version=()

for i in ${!secrets_index[@]}
do
	j=${secrets_index[$i]}
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

	updated_secrets_name+=("${secrets_name[$j]}")
	updated_secrets_value+=("${value}")
	updated_secrets_version+=( $((${secrets_version[$j]} + 1)) )
done

#
#	Output updated secret version information to files
#

out="${combined_file}"

use_combined_file="${combined_file:+y}"
if [ "${use_combined_file}" = "y" ]
then
	echo -n "" > "${out}"
fi

if [ "${key_file}" ]
then
	echo -n "" > "${key_file}"
fi

for i in ${!secrets_name[@]}
do
	if [ "${use_combined_file}" != "y" ] && [ "${out}" != "${secrets_file[$i]}" ]
	then
		out="${secrets_file[$i]}"
		echo -n "" > "${out}"
	fi
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
	echo "\"${secret_name}\" \"${secret_text}\" \"${secret_version}\" \"${secret_default}\"" >> "${out}"

	if [ "${key_file}" ]
	then
		echo "export ${secret_name}_SECRET_VERSION=${secret_version};" >> "${key_file}"
	fi
done

#
#	Output updated secret names and values for retrieval by calling program
#

if [ "${data_file}" ]
then
	echo -n "" > "${data_file}"
	for i in ${!updated_secrets_name[@]}
	do
		echo "${updated_secrets_name[$i]}_v${updated_secrets_version[$i]} \"${updated_secrets_value[$i]}\"" >> "${data_file}"
	done
	exit
fi

#
#	Put updated secrets into swarm
#

if [ -z "${SWARM_MANAGER_NAME:+set}" ]
then
	define_swarm
fi

echo
echo "Updating secrets..."
for i in ${!updated_secrets_name[@]}
do
	echo "    ${updated_secrets_name[$i]}_v${updated_secrets_version[$i]}"
	push_secret "${updated_secrets_name[$i]}_v${updated_secrets_version[$i]}" "${updated_secrets_value[$i]}"
done

echo
echo "Secrets updated"
echo