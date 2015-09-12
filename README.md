automtud
========

The automtud is a program to enable you to use jumbo frames on a network
that has legacy 1500 byte MTU machines on it.

This is achieved by having the interface MTU set to the largest possible
size.  The network route is then set to 1500 bytes.  This allows all
normal communication to happen at the normal size.  The program will then
detect the machines on the network and attempt to probe each one w/ the
largest sized packet.  If we get a response (even if it's fragmented), we
know that we can see that the machine can receive that sized jumbo frame,
so we create/update the machine's route to be this new size.  It is assumed
that the other machine will be doing the same thing and you'll have by
directional jumbo frame working.

This should also work even if network switches don't support jumbo frame.
This is because if the switch doesn't support jumbo frames, the packet
will drop, and it'll just look like the remote side doesn't support that
sized frames.

This is currently designed to work on FreeBSD.  It has been tested w/
a late June 2015 -CURRENT and 9.2-R.

The script will figure out the largest MTU that the interface supports.
There are no issues with setting it larger than the other hosts on the
network as the optimum size will be figured out.  Once the script is
run, it will configure the host routes to have the standard 1500 byte
MTU, though this can be changed w/ the -m option, and then monitor the
arp table and probe new hosts, and delete old host routes when not
needed.

This is very alpha, so comments, bug reports and ideas are welcome.

Running automtud.sh:

	sh automtud.sh -i <interface>

You can specify more than one -i option to add additional interfaces.

Command for checking MTU of the routes:

	netstat -Wrnfinet

The most surprising thing of running this command is that things will
have larger MTUs than expected.  Do you have a machine w/ VLANs
enabled?  Well, on the untagged part, you'll now get an MTU of 1504.
Some OS's may have larger than 1500, MacOSX 10.10.5's wireless interface
accepts packets up to 1532 bytes.

Issues
======

One issue that can happen when using jumbo frames is running out of
memory.  A number of drivers may use either the zone mbuf_jumbo_9k or
mbuf_jumbo_16k which uses contiguous physical and virtual address space.
After the machine has been running a while, physical memory may be
fragmented enough to prevent a contiguous allocation of memory preventing
additional mbufs from being allocated.  This can prevent the system from
working.  This may be required for some drivers which do not support a
scatter/gather array for the packet, but most modern ethernet hardware
should fully support this.

Drivers known to use 9k or 16k physically contiguous zones:
	bce, bge, bxe, cxgb, em, igb, ixgbe, msk, mxge, nfe, nxge, qlxgb,
	re, sfxge, sk, ti, vtnet, vxge

Drivers known to require the use of a physically contigusous zone:
