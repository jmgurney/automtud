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
