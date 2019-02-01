vms=$(docker-machine ls -q)

for dir in $@
do
	workdir=$(basename "$dir")
	for vm in ${vms[@]}
	do
		docker-machine ssh "${vm}" "sudo mkdir -p \"${dir}\""
		vboxmanage sharedfolder add "${vm}" --name "${workdir}" --hostpath "${dir}" --transient
		docker-machine ssh "${vm}" "sudo mount -t vboxsf -o uid=\"0\",gid=\"0\" \"${workdir}\" \"${dir}\""
	done
done

echo "Mount points \"$@\" created on virtual machines ${vms[@]}"

