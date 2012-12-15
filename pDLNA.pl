#!/usr/bin/perl
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2012 Stefan Heumader <stefan@heumader.at>
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
use threads::shared;
use Getopt::Long::Descriptive;

use lib ('./');
use PDLNA::Config;
use PDLNA::ContentLibrary;
use PDLNA::Daemon;
use PDLNA::Database;
use PDLNA::DeviceList;
use PDLNA::HTTPServer;
use PDLNA::Log;
use PDLNA::SSDP;
use PDLNA::Status;

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

PDLNA::Log::log("Starting $CONFIG{'PROGRAM_NAME'}/v".PDLNA::Config::print_version()." on $CONFIG{'OS'}/$CONFIG{'OS_VERSION'} with FriendlyName '$CONFIG{'FRIENDLY_NAME'}' with UUID $CONFIG{'UUID'}.", 0, 'default');

PDLNA::Database::initialize_db();

my $device_list = PDLNA::DeviceList->new(); # initialize DeviceList object
my $ssdp = PDLNA::SSDP->new(\$device_list); # initialize SSDP object

# forking
PDLNA::Daemon::daemonize(\%SIG, \$ssdp);
PDLNA::Daemon::write_pidfile($CONFIG{'PIDFILE'}, $$);

my $thread1 = threads->create('PDLNA::ContentLibrary::index_directories_thread');
$thread1->detach();

# starting up
PDLNA::Log::log("Server is going to listen on $CONFIG{'LOCAL_IPADDR'} on interface $CONFIG{'LISTEN_INTERFACE'}.", 1, 'default');
my $thread2 = threads->create('PDLNA::HTTPServer::start_webserver', \$device_list); # starting the HTTP server in a thread
$thread2->detach();

$ssdp->add_send_socket(); # add the socket for sending SSDP messages
$ssdp->add_receive_socket(); # add the socket for receiving SSDP messages
$ssdp->send_byebye(2); # send some byebye messages
$ssdp->start_listening_thread(); # start to listen for SEARCH messages in a thread
$ssdp->send_alive(6); # and now we are joing the group
$ssdp->start_sending_periodic_alive_messages_thread(); # start to send out periodic alive messages in a thread

if ($CONFIG{'CHECK_UPDATES'})
{
	my $thread2 = threads->create('PDLNA::Status::check_update_periodic');
	$thread2->detach();
}

while(1)
{
	sleep(100);
}
