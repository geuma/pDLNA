#!/usr/bin/perl
#
# lombix DLNA - a perl DLNA media server
# Copyright (C) 2013 Cesar Lombao <lombao@lombix.com>
#
#
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2013 Stefan Heumader <stefan@heumader.at>
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
use LDLNA::Config;
use LDLNA::ContentLibrary;
use LDLNA::Daemon;
use LDLNA::Database;
use LDLNA::HTTPServer;
use LDLNA::Log;
use LDLNA::SSDP;

#
# STARTUP PARAMETERS
#

my ($opt, $usage) = describe_options(
	'%c %o ',
	[ 'config|f:s', 'path to the configuration file', { default => '/etc/ldlna.conf' }, ],
	[], # just an empty line for the usage message
	[ 'help|h',	'print usage method and exit' ],
);
print($usage->text), exit if $opt->help();
my @config_file_error = ();
unless (LDLNA::Config::parse_config($opt->config, \@config_file_error))
{
	LDLNA::Log::fatal(join("\n", @config_file_error))
}

LDLNA::Log::log("Starting $CONFIG{'PROGRAM_NAME'}/v".LDLNA::Config::print_version()." on $CONFIG{'OS'}/$CONFIG{'OS_VERSION'} with FriendlyName '$CONFIG{'FRIENDLY_NAME'}' with UUID $CONFIG{'UUID'}.", 0, 'default');
LDLNA::Database::initialize_db();
my $ssdp = LDLNA::SSDP->new(); # initialize SSDP object

# forking
LDLNA::Daemon::daemonize(\%SIG, \$ssdp);
LDLNA::Daemon::write_pidfile($CONFIG{'PIDFILE'}, $$);

# starting thread to periodically index the configured media directories
my $thread1 = threads->create('LDLNA::ContentLibrary::index_directories_thread');
$thread1->detach();

# starting up
LDLNA::Log::log("Server is going to listen on $CONFIG{'LOCAL_IPADDR'} on interface $CONFIG{'LISTEN_INTERFACE'}.", 1, 'default');
my $thread2 = threads->create('LDLNA::HTTPServer::start_webserver'); # starting the HTTP server in a thread
$thread2->detach();


while(1)
{
    $ssdp->send_alive(2);
    $ssdp->receive_messages();
	
}
