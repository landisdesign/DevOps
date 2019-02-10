NR == FNR { # In the network file, create map
	network[$1] = $2
}

NR != FNR { # In the service file, use map
	$2 = network[$2]
	print
}
