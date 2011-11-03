#!/usr/bin/perl
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2011 Stefan Heumader <stefan@heumader.at>
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
use Getopt::Long::Descriptive;

use lib ('./');
use PDLNA::Config;
use PDLNA::Daemon;
use PDLNA::DeviceList;
use PDLNA::HTTPServer;
use PDLNA::Log;
use PDLNA::SSDP;
use PDLNA::Status;

our @THREADS = ();
my $device_list = PDLNA::DeviceList->new();

#
# STARTUP PARAMETERS
#

my ($opt, $usage) = describe_options(
	'%c %o ',
	[ 'config|f:s', 'path to the configuration file', { default => '/etc/pdlna.conf' }, ],
	[], # just an empty line for the usage message
	[ 'help|h',	'print usage method and exit' ],
);
print($usage->text), exit if $opt->help();
my @config_file_error = ();
unless (PDLNA::Config::parse_config($opt->config, \@config_file_error))
{
	PDLNA::Log::fatal(join("\n", @config_file_error))
}
PDLNA::HTTPServer::initialize_content();

PDLNA::Daemon::daemonize(\%SIG);
PDLNA::Daemon::write_pidfile($CONFIG{'PIDFILE'}, $$);

PDLNA::Log::log("Starting $CONFIG{'PROGRAM_NAME'}/v$CONFIG{'PROGRAM_VERSION'} on $CONFIG{'OS'}/$CONFIG{'OS_VERSION'} with FriendlyName '$CONFIG{'FRIENDLY_NAME'}' with UUID $CONFIG{'UUID'}.", 0, 'default');
PDLNA::Log::log("Server is going to listen on $CONFIG{'LOCAL_IPADDR'} on interface $CONFIG{'LISTEN_INTERFACE'}.", 1, 'default');

push(@THREADS, threads->create('PDLNA::HTTPServer::start_webserver')); # starting the HTTP server in a thread

PDLNA::SSDP::add_sockets(); # add sockets for SSDP

# send some byebye messages
PDLNA::SSDP::byebye();
PDLNA::SSDP::byebye();
sleep(1);
push(@THREADS, threads->create('PDLNA::SSDP::act_on_ssdp_message', \$device_list)); # start to listen for SEARCH messages in a thread
sleep(1);

# and now we are joing the group
PDLNA::SSDP::alive();
PDLNA::SSDP::alive();
PDLNA::SSDP::alive();

push(@THREADS, threads->create('PDLNA::SSDP::send_alive_periodic')); # start to send out periodic alive messages in a thread

if ($CONFIG{'CHECK_UPDATES'})
{
	push(@THREADS, threads->create('PDLNA::Status::check_update_periodic'));
}

while(1)
{
	sleep(100);
}
