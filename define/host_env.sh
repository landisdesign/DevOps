echo
echo "Creating host environment variables..."
echo

if [ $# -gt 0 ]
then
	COMPOSE_DIR="$1"
else
	COMPOSE_DIR="$(cd ..; pwd)"
fi


. "${COMPOSE_DIR}/libs/docker_utils.sh"
dsmachines

file="${COMPOSE_DIR}/host_env.sh"

echo "SWARM_MANAGER_MACHINE_NAME='${SWARM_MANAGER_MACHINE_NAME}'; export SWARM_MANAGER_MACHINE_NAME;" > "${file}"
echo "COMPOSE_DIR='${COMPOSE_DIR}'; export COMPOSE_DIR;" >> "${file}"
chmod 777 "${file}"

echo
echo "host_env.sh created"
echo