#!/usr/bin/perl
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010 Stefan Heumader <stefan@heumader.at>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

use threads;

use lib ('/usr/local/bin/pdlna');
use PDLNA::SSDP;
use PDLNA::Config;
use PDLNA::HTTP;
use PDLNA::Log;

our @THREADS = ();

sub exit_daemon
{
	PDLNA::Log::log("Shutting down $CONFIG{'PROGRAM_NAME'} v$CONFIG{'PROGRAM_VERSION'}. It may take some time ...", 0);

	PDLNA::SSDP::byebye();
	PDLNA::SSDP::byebye();

	# TODO join the threads, it is ugly that way

	exit(1);
}

sub start_http_server
{
	my $foo = PDLNA::HTTP->new($CONFIG{'HTTP_PORT'});
	$foo->run();
}

$SIG{INT} = \&exit_daemon; # currently we aren't a daemon ... so we just want to shut down after a SIGINT

PDLNA::Log::log("Starting $CONFIG{'PROGRAM_NAME'}/v$CONFIG{'PROGRAM_VERSION'} on $CONFIG{'OS'}/$CONFIG{'OS_VERSION'}", 0);

push(@THREADS, threads->create('start_http_server')); # starting the HTTP server in a thread

PDLNA::SSDP::add_sockets(); # add sockets for SSDP

# send some byebye messages
PDLNA::SSDP::byebye();
PDLNA::SSDP::byebye();
sleep(3);

# and now we are joing the group
PDLNA::SSDP::alive();
PDLNA::SSDP::alive();
PDLNA::SSDP::alive();

push(@THREADS, threads->create('PDLNA::SSDP::act_on_ssdp_message')); # start to listen for SEARCH messages in a thread
push(@THREADS, threads->create('PDLNA::SSDP::send_alive_periodic')); # start to send out periodic alive messages in a thread

while(1)
{
	sleep(100);
}
