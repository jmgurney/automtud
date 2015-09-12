#!/bin/sh -
#
# Copyright 2015 John-Mark Gurney.
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#
#
# Script for detecting new hosts and deciding what the MTU should
# be for the host.
#

detectmachines()
{
	awk '
function process(oldmac, newmac)
{
	for (i in newmac) {
		if (i in oldmac && oldmac[i] == newmac[i])
			continue

		if (i in oldmac)
			printf("del %s %s\n", i, oldmac[i])

		printf("add %s %s\n", i, newmac[i])
	}
	for (i in oldmac) {
		if (i in newmac)
			continue

		printf("del %s %s\n", i, oldmac[i])
	}
}

BEGIN {
	cmd = "arp -a; sleep 1"
	for (;;) {
		res=cmd | getline
		if (res == 0) {
			close(cmd)
			#print "processing" >"/dev/stderr"
			process(oldmac, newmac)
			delete oldmac
			for (i in newmac)
				oldmac[i] = newmac[i]
			delete newmac
			continue
		}
		if (res == -1) {
			print "error!" >"/dev/stderr"
			continue
		}
		if ($7 == "permanent" || $4 == "(incomplete)" || $6 !~ /'"$interfaces"'/)
			continue

		newmac[substr($2, 2, length($2) - 2)] = $6
	}
}
'

	#machines=""
	#while :; do
	#	newarp=$(arp -a | awk '$7 != "permanent" && $4 != "(incomplete)" && $6 ~ /'"$interfaces"'/ { print substr($2, 2, length($2) - 2) " " $6 }')
	#	([ -z "$machines" ] || echo "$machines"; echo "$newarp") | sort | uniq -u | sed -e 's/^/add /'
	#	machines="$newarp"
	#	sleep 1
	#done
}

probeipsize()
{
	# -s l results in a packet of l + 8 (ICMP) + 20 (IP) total length
	# XXX - it'd be nice if -t accepted fractional seconds.
	ping -r -t 1 -s $(($2 - 8 - 20)) -c 1 "$1" >/dev/null 2>&1 || return 1
}

probemachine()
{
	# Verify machine reachability

	# XXX - prime low with base MTU size
	low="$normal_mtu"
	if ! probeipsize "$1" "$low"; then
		echo 0
		return
	fi

	max=$(ifconfig "$2" | head -n 1 | awk '{print $6}')
	hi="$max" # highest common/max size goes here
	commonsizes="1500 1504 9216 9000 1480 1492 4352 4096 1532 576 7422 16114 10240 6144 8132 9022 9184"
	# XXX - collect real world stats to order these
	# 1532 - not sure, but it's my MBP 15" running MacOSX 10.10.5
	# through c's plus a few common ones
	# 6144 - alc
	# 7422 - re
	# 8132 - ale
	# 9000 - cxgb
	# 9022 - bce, cas, msk
	# 9184 - bxe
	# 9216 - alc
	# 10240 - age
	# 16114 - em, ix
	for i in $commonsizes; do
		#echo testing size: "$i" >&2
		if [ "$i" -gt "$hi" ]; then
			continue
		elif [ ! -z "$low" ] && [ "$i" -lt "$low" ]; then
			continue
		fi

		if probeipsize "$1" "$i"; then
			low="$i"

			# test if low is largest possible
			if ! probeipsize "$1" $(($low + 1)); then
				#echo "+1 probe failed" >&2
				echo "$low"
				return
			fi
		else
			hi="$i"
		fi
	done
	#echo common sizes low: "$low", hi: "$hi" >&2

	if [ x"$hi" = x"$max" ] && probeipsize "$1" "$hi"; then
		echo "$hi"
		return
	fi

	# do binary search for MTU
	while [ x"$low" != x"$hi" -a x"$(($low + 1))" != x"$hi" ]; do
		probe=$((($hi - $low) / 2 + $low))
		#echo low: "$low", hi: "$hi", probe: "$probe" >&2
		if probeipsize "$1" "$probe"; then
			low="$probe"
		else
			hi="$probe"
		fi
		sleep 1
	done
	echo "$low"
}

setupinterface()
{
	#XXX detect networks on interface
	#update network routes:
	mac=$(ifconfig "$1" | awk '$1 == "ether" { print $2 }')

	# Find interface's max MTU
	low=1500
	probe=32768
	while :; do
		if ifconfig "$1" mtu $probe 2>&1 | grep 'set mtu' >/dev/null; then
			hi=$probe
		else
			low=$probe
		fi

		if [ x"$low" == x"$hi" -o x"$(($low + 1))" == x"$hi" ]; then
			break
		fi

		probe=$((($hi - $low) / 2 + $low))
	done

	if ifconfig "$1" mtu $low 2>&1 | grep 'set mtu' >/dev/null; then
		echo Failed to set MTU on interface "$1" to $low
		exit 3
	fi

	echo Setting MTU on interface "$1" to $low.

	# get possible routes
	# XXX - not the best way to get network routes
	for i in $(netstat -rnfinet | awk '$4 == "'"$1"'" && index($1, "/") != 0 && (substr($2, 1, 4) == "link" || length($2) == 17) { print $1 }'); do
		echo setting normal mtu on interface "$1" for network "$i"
		route change "$i" -interface "$1" -mtu "$normal_mtu"
	done
}

usage()
{
	echo "Usage: $0 [ -m <minmtu> ] -i <interface> ..."
}

# XXX - params
interfaces=""
normal_mtu="1500"

while getopts hi:m: opt; do
	case "$opt" in
	i)
		xint="${OPTARG%%[^a-zA-Z0-9.]*}"
		if [ x"$xint" != x"$OPTARG" ]; then
			echo Invalid interface name: "$OPTARG"
			exit 2
		fi

		if [ -z "$interfaces" ]; then
			interfaces="$OPTARG"
		else
			interfaces="$interfaces|$OPTARG"
		fi
		;;
	m)
		xint="${OPTARG%%[^0-9]*}"
		if [ x"$xint" != x"$OPTARG" ]; then
			echo "Invalid value for min MTU: $OPTARG"
			exit 2
		fi
		normal_mtu="$OPTARG"
		;;
	h|'?')
		usage
		exit 3
	esac
done

if [ -z "$interfaces" ]; then
	echo No interfaces specified.
	usage
	exit 1
fi

# Get interfaces ready.
for i in $(echo "$interfaces" | sed -e 's/|/\
/g'); do
	echo setting up: "$i"
	setupinterface "$i"
done

# Watch for machines comming and going and adjust as needed.
detectmachines "$interfaces" | while read mode mach iface; do
	echo machine "$mach" "$mode" on interface "$iface"
	if [ x"$mode" = x"add" ]; then
		res=$(probemachine "$mach" "$iface")
		if [ x"$res" = x"0" ]; then
			# machine is down?
			echo "machine is down"
			continue
		fi

		if [ "$res" != "$normal_mtu" ]; then
			echo "adjusting $mach mtu to $res"
			route change "$mach" -interface "$iface" -mtu "$res" 2>/dev/null >/dev/null||
			route add "$mach" -interface "$iface" -mtu "$res" >/dev/null
		fi
	elif [ x"$mode" = x"del" ]; then
		route delete "$mach"
	else
		echo "Unknown mode: $mode"
	fi
done
