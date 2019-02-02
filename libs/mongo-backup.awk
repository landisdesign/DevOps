BEGIN {
	FS = "!"
}

$1 && $3 {
	backup = $1
	network = $2
	host = $3
	replica = $4

	if ( (backup, replica, network) in services ) {
		services[backup, replica, network] = services[backup, replica, network] "," host
	}
	else {
		services[backup, replica, network] = host
	}

	next
}

{
	# Do not collect services that have no backup name or host identified
}

END {
	for (indices in services) {
		split(indices, fields, SUBSEP);
		printf "%s %s %s", fields[1], fields[3], services[indices]
		if (fields[1]) {
			printf " %s", fields[2]
		}
		printf "\n"
	}
}