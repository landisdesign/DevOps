define_swarm(){

	if [ "${SWARM_MANAGER_NAME+set}" ]
	then
		read -p "The swarm is currently identified as running on ${SWARM_MANAGER_NAME:-the current machine}. Do you want to change it ? (y/n) " change
		if [ "${change}" != "y" ]
		then
			return
		fi
	fi

	test_secret_key="local__test"

	echo
	read -s -p "Make sure your docker swarm is up and running. Press Enter to continue."
	echo
	echo
	read -p "Swarm manager name (current machine): " SWARM_MANAGER_NAME
	while ! push_secret ${test_secret_key} "test"
	do
		if [ -z "${SWARM_MANAGER_NAME}" ]
		then
			echo "The current machine is not set up as a swarm manager."
		else
			echo "Machine ${SWARM_MANAGER_NAME} is not responding as a swarm manager."
		fi
		read -p "Please re-enter the swarm manager name (current machine): " SWARM_MANAGER_NAME
	done

	echo
	if [ -z "${SWARM_MANAGER_NAME}" ]
	then
		echo "The current machine is identified as the swarm manager."
	else
		echo "Machine ${SWARM_MANAGER_NAME} is identified as the swarm manager."
	fi
	echo

	remove_secret ${test_secret_key}
}

#
#	These methods expect the swarm manager machine to be identified in SWARM_MANAGER_NAME
#

push_secret(){
	if [ -f "$2" ]
	then
		if [ -z "${SWARM_MANAGER_NAME}" ]
		then
			docker secret create $1 $2 > /dev/null 2> /dev/null
		else
			docker-machine ssh "${SWARM_MANAGER_NAME}" "docker secret create $1 $2" > /dev/null 2> /dev/null
		fi
	else
		if [ -z "${SWARM_MANAGER_NAME}" ]
		then
			echo $2 | docker secret create $1 - > /dev/null 2> /dev/null
		else
			echo $2 | docker-machine ssh "${SWARM_MANAGER_NAME}" "docker secret create $1 -" > /dev/null 2> /dev/null
		fi
	fi
}

remove_secret(){
	if [ -z "${SWARM_MANAGER_NAME}" ]
	then
		docker secret rm $1 > /dev/null 2> /dev/null
	else
		docker-machine ssh "${SWARM_MANAGER_NAME}" "docker secret rm $1" > /dev/null 2> /dev/null
	fi
}
