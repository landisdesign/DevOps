build_name_value_list(){

	names=()
	values=()
	lines=()
	file=$2

	while IFS=$'\n' read -r list_data || [ -n "$list_data" ]
	do
		IFS=$'\n' lines+=("${list_data}")
	done < $1

	for line in ${lines[@]}
	do
		IFS=$'\n' list_params=( $( xargs -n1 <<<"${line}" ) )

		name="${list_params[0]}"
		prompt_text="${list_params[1]}"
		default="${list_params[2]}"
		if [ -z "${default}" ]
		then
			prompt="${prompt_text}: "
		else
			prompt="${prompt_text} (${default}):"
		fi

		input=""
		while [ -z "${input}" ]
		do
			read -p "${prompt}" input
			if [ -z "${input}" ]
			then
				if [ "${default}" ]
				then
					input="${default}"
				else
					echo "  ${prompt_text} cannot be empty. Please enter a value."
				fi
			fi
		done

		names+=("${name}")
		values+=("${input}")
	done

	if [[ "${file}" ]]
	then
		echo -n "" > ${file}
		for i in ${!names[@]}
		do
			echo "${names[$i]}=\"${values[$i]}\"; export ${names[$i]};" >> ${file}
		done
	fi
}

get_md5(){
	if builtin command -v md5sum > /dev/null
	then
		if [ -f "$1" ]
		then
			data=$( md5sum $1 )
		else
			data=$( echo "$@" | md5sum - ) # properly transfer any spaces or special characters
		fi
	else
		if [ -f "$1" ]
		then
			data=$( md5 $1 )
		else
			data=$( md5 -s "$@" ) # properly transfer any spaces or special characters
		fi
	fi

	data=$(echo "$data" | sed -n 's/.*\([0-9a-fA-F]\{32\}\).*/\1/p' )
	echo "$data"
}
