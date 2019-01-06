echo
echo "Creating secrets..."
echo

if [ -z "${COMPOSE_DIR+set}" ]
then
	. ./host_env.sh $(cd ..; pwd)
fi

. "${COMPOSE_DIR}/libs/utils.sh"
. "${COMPOSE_DIR}/libs/docker_utils.sh"

build_name_value_list "${COMPOSE_DIR}/define/secrets_list.txt"

# Generate version string
if builtin command -v md5sum > /dev/null
then
	md5_app=md5sum
else
	md5_app=md5
fi
secret_version=( $(echo "${names[@]} ${values[@]}" -n | ${md5_app}) )
DOCKER_SECRET_VERSION="${secret_version[0]}"

file="${COMPOSE_DIR}/secret_key.sh"
echo "DOCKER_SECRET_VERSION=\"${DOCKER_SECRET_VERSION}\"; export DOCKER_SECRET_VERSION" > "${file}"
. "${file}"

# Generate Secrets
echo
echo -n "Generating secrets with key ${DOCKER_SECRET_VERSION}"

for i in ${!names[@]}
do
	name=${names[$i]}_${DOCKER_SECRET_VERSION}
	value=${values[$i]}
	push_secret ${name} ${value}
	echo -n "."
done

echo
echo
echo "Secrets created with key ${DOCKER_SECRET_VERSION}"
echo