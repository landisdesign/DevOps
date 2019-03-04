if [ ! -f ./host_env.sh ]
then
	. ./define/host_env.sh "$(pwd)"
fi

if [ ! -f ./env.sh ]
then
	. ./define/compose_env.sh
fi

if [ ! -f ./secret_keys.sh ]
then
	cd define
	if [ ! -f secrets_combined.txt ]
	then
		cat secrets_*.txt > secrets_combined.txt
	fi
	. ./secrets.sh -k ../secret_keys.sh secrets_combined.txt
	cd ..
fi

. ./host_env.sh
. ./secret_keys.sh
. ./env.sh

. ./libs/docker_utils.sh

awk -f libs/translate.awk templates/docker-compose.yml > docker-compose.yml

echo
echo "Deploying services..."
echo

commands="cd \"$(pwd)\"; docker stack deploy -c docker-compose.yml ${STACK_NAME}"

dsmachines
original_machine_name="${CURRENT_DOCKER_MACHINE_NAME}"
switch_to_machine "${SWARM_MANAGER_MACHINE_NAME}"
docker stack deploy -c docker-compose.yml ${STACK_NAME}

echo
echo "Stack ${STACK_NAME} deployed"

cd ./define
./secrets.sh -qr ./secrets_combined.txt
cd ..

switch_to_machine "${original_machine_name}"
