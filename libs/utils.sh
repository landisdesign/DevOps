build_name_value_list(){

	names=()
	values=()
	lines=()

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
}
