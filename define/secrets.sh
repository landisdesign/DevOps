echo
echo "Creating secrets..."
echo

# make sure COMPOSE_DIR is populated
if [ -z "${COMPOSE_DIR+set}" ]
then
	. ./host_env.sh $(cd ..; pwd)
fi

. "${COMPOSE_DIR}/libs/utils.sh"
. "${COMPOSE_DIR}/libs/docker_utils.sh"

secrets_key_file="${COMPOSE_DIR}/secret_key.sh"

if [ -f "${secrets_key_file}" ]
then
	. "${secrets_key_file}"
	OLD_DOCKER_SECRET_VERSION="${DOCKER_SECRET_VERSION}"
else
	OLD_DOCKER_SECRET_VERSION=""
fi

secrets_names=("mongo" "mongo_cluster")

secrets_files=()
secrets_digest=""

for i in ${!secrets_names[@]}
do
	secrets_name=${secrets_names[$i]}
	secrets_list="${COMPOSE_DIR}/define/secrets_${secrets_name}.txt"
	secrets_file="$(pwd)/secrets_${secrets_name}.sh"

	build_name_value_list "${secrets_list}" "${secrets_file}"

	secrets_md5=$(get_md5 "${secrets_file}")
	secrets_digest="${secrets_digest} ${secrets_md5}"
	secrets_files+=("${secrets_file}")
done

# compact all files' MD5 digests into one key
DOCKER_SECRET_VERSION=$( echo "${secrets_digest}" | get_md5 - )

echo "DOCKER_SECRET_VERSION=\"${DOCKER_SECRET_VERSION}\"; export DOCKER_SECRET_VERSION" > "${secrets_key_file}"
if [ "${OLD_DOCKER_SECRET_VERSION}" ]
then
	echo "OLD_DOCKER_SECRET_VERSION=\"${OLD_DOCKER_SECRET_VERSION}\"; export OLD_DOCKER_SECRET_VERSION" >> "${secrets_key_file}"
fi
. "${secrets_key_file}"

# Generate Secrets
echo
echo "Saving secrets files..."

for i in ${!secrets_names[@]}
do
	name=${secrets_names[$i]}_${DOCKER_SECRET_VERSION}
	value=${secrets_files[$i]}
	push_secret ${name} ${value}
	rm ${value}
	echo "${name}"
done

echo
echo "Secrets saved"
echo