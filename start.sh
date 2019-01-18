if [ ! -f ./host_env.sh ]
then
	. ./define/host_env.sh "$(pwd)"
fi

if [ ! -f ./env.sh ]
then
	. ./define/compose_env.sh
fi

if [ ! -f ./secret_key.sh ]
then
	. ./define/secrets.sh
fi

. ./host_env.sh
. ./secret_key.sh
. ./env.sh

cd templates
awk -f ../define/translate.awk docker-compose.yml > ../docker-compose.yml
cd ..

echo
echo "Deploying services..."
echo

commands="cd \"$(pwd)\"; DOCKER_SECRET_VERSION=${DOCKER_SECRET_VERSION} docker stack deploy -c docker-compose.yml ${STACK_NAME}"
if [ "${SWARM_MANAGER_NAME}" ]
then
	docker-machine ssh ${SWARM_MANAGER_NAME} "${commands}"
else
	${commands}
fi

echo
echo "Stack ${STACK_NAME} deployed"
echo
