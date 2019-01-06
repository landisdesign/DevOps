echo
echo "Creating docker-compose variables..."
echo

if [ -z "${COMPOSE_DIR+set}" ]
then
	. ./host_env.sh $(cd ..; pwd)
fi

. "${COMPOSE_DIR}/libs/utils.sh"

build_name_value_list "${COMPOSE_DIR}/define/compose_list.txt"

env_file="${COMPOSE_DIR}/.env"
sh_file="${COMPOSE_DIR}/env.sh"

for i in ${!names[@]}
do
	case ${i} in
		0)
			echo "${names[i]}=${values[i]}" > "${env_file}"
			echo "${names[i]}=${values[i]}; export ${names[i]}" > "${sh_file}"
			;;
		*)
			echo "${names[i]}=${values[i]}" >> "${env_file}"
			echo "${names[i]}=${values[i]}; export ${names[i]}" >> "${sh_file}"
			;;
	esac
done
chmod 777 "${env_file}" "${sh_file}"

echo
echo ".env file created."
echo "env.sh file created."
echo