package PDLNA::Config;
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

use strict;
use warnings;

use base 'Exporter';

our @ISA = qw(Exporter);
our @EXPORT = qw(%CONFIG);

use Config::ApacheFormat;
use IO::Socket;
use IO::Interface qw(if_addr);
use Net::IP;
use Net::Netmask;
use Sys::Hostname qw(hostname);
use Config qw();

our %CONFIG = (
	# values which can be modified by configuration file
	'LOCAL_IPADDR' => undef,
	'LISTEN_INTERFACE' => undef,
	'HTTP_PORT' => 8001,
	'CACHE_CONTROL' => 1800,
	'PIDFILE' => '/var/run/pdlna.pid',
	'ALLOWED_CLIENTS' => [],
	'LOG_FILE' => 'STDERR',
	'LOG_DATE_FORMAT' => '%Y-%m-%d %H:%M:%S',
	'LOG_CATEGORY' => [],
	'DEBUG' => 0,
	'TMP_DIR' => '/tmp',
	'MPLAYER_BIN' => '/usr/bin/mplayer',
	'DIRECTORIES' => [],
	# values which can be modified manually :P
	'PROGRAM_NAME' => 'pDLNA',
	'PROGRAM_VERSION' => '0.35',
	'PROGRAM_DATE' => '2011-10-21',
	'PROGRAM_WEBSITE' => 'http://www.pdlna.com',
	'PROGRAM_AUTHOR' => 'Stefan Heumader',
	'PROGRAM_SERIAL' => 1338,
	'PROGRAM_DESC' => 'perl DLNA MediaServer',
    'OS' => $Config::Config{osname},
    'OS_VERSION' => $Config::Config{osvers},
	'HOSTNAME' => hostname(),
	'UUID' => generate_uuid(),
);
$CONFIG{'FRIENDLY_NAME'} = 'pDLNA v'.$CONFIG{'PROGRAM_VERSION'}.' on '.$CONFIG{'HOSTNAME'};

sub generate_uuid
{
	my @chars = qw(a b c d e f 0 1 2 3 4 5 6 7 8 9);

	my $uuid = '';
	while (length($uuid) < 36)
	{
		$uuid .= $chars[int(rand(@chars))];

		$uuid .= '-' if length($uuid) == 8;
		$uuid .= '-' if length($uuid) == 13;
		$uuid .= '-' if length($uuid) == 18;
		$uuid .= '-' if length($uuid) == 23;
	}

	return "uuid:".$uuid;
}

sub parse_config
{
	my $file = shift;
	my $errormsg = shift;

	if (!-f $file)
	{
		push(@{$errormsg}, 'Configfile '.$file.' not found.');
		return 0;
	}

	my $cfg = Config::ApacheFormat->new(
		valid_blocks => [qw(Directory)],
	);
	unless ($cfg->read($file))
	{
		push(@{$errormsg}, 'Configfile '.$file.' is not readable.');
		return 0;
	}

	#
	# FRIENDLY NAME PARSING
	#
	$CONFIG{'FRIENDLY_NAME'} = $cfg->get('FriendlyName') if defined($cfg->get('FriendlyName'));
	if ($CONFIG{'FRIENDLY_NAME'} !~ /^[\w\-\s\.]{1,32}$/)
	{
		push(@{$errormsg}, 'Invalid FriendlyName: Please use letters, numbers, dots, dashes, underscores and or spaces and the FriendlyName requires a name that is 32 characters or less in length.');
	}

    #
    # INTERFACE CONFIG PARSING
    #
    my $socket_obj = IO::Socket::INET->new(Proto => 'udp');
    if ($cfg->get('ListenInterface')) {
        $CONFIG{'LISTEN_INTERFACE'} = $cfg->get('ListenInterface');
    }
    # Get the first non lo interface
    else {
        foreach my $interface ($socket_obj->if_list) {
            next if $interface =~ /^lo/i;
            $CONFIG{'LISTEN_INTERFACE'} = $interface;
            last;
        }
    }

    push (@{$errormsg}, 'Invalid ListenInterface: The given interface does not exist on your machine.')
        if (! $socket_obj->if_flags($CONFIG{'LISTEN_INTERFACE'}));

    #
    # IP ADDR CONFIG PARSING
    #
    $CONFIG{'LOCAL_IPADDR'} = $cfg->get('ListenIPAddress') ? $cfg->get('ListenIPAddress') : $socket_obj->if_addr($CONFIG{'LISTEN_INTERFACE'});

    push(@{$errormsg}, 'Invalid ListenInterface: The given ListenIPAddress is not located on the given ListenInterface.')
        unless $CONFIG{'LISTEN_INTERFACE'} eq $socket_obj->addr_to_interface($CONFIG{'LOCAL_IPADDR'});

	#
	# HTTP PORT PARSING
	#
	$CONFIG{'HTTP_PORT'} = int($cfg->get('HTTPPort')) if defined($cfg->get('HTTPPort'));
	if ($CONFIG{'HTTP_PORT'} < 0 && $CONFIG{'HTTP_PORT'} > 65535)
	{
		push(@{$errormsg}, 'Invalid HTTPPort: Please specify a valid TCP port which is > 0 and < 65536.');
	}

	#
	# CHACHE CONTROL PARSING
	#
	$CONFIG{'CACHE_CONTROL'} = int($cfg->get('CacheControl')) if defined($cfg->get('CacheControl'));
	if ($CONFIG{'CACHE_CONTROL'} < 60 && $CONFIG{'CACHE_CONTROL'} > 18000)
	{
		push(@{$errormsg}, 'Invalid CacheControl: Please specify the CacheControl between 60 and 18000 seconds.');
	}

	#
	# PID FILE PARSING
	#
	$CONFIG{'PIDFILE'} = $cfg->get('PIDFile') if defined($cfg->get('PIDFile'));
	if (defined($CONFIG{'PIDFILE'}) && $CONFIG{'PIDFILE'} =~ /^\/[\w\.\_\-\/]+\w$/)
	{
		if (-e $CONFIG{'PIDFILE'})
		{
			push(@{$errormsg}, 'Warning PIDFile: The file named '.$CONFIG{'PIDFILE'}.' is already existing. Please change the filename or delete the file.');
		}
	}
	else
	{
		push(@{$errormsg}, 'Invalid PIDFile: Please specify a valid filename (full path) for the PID file.');
	}

	#
	# ALLOWED CLIENTS PARSING
	#
	if (defined($cfg->get('AllowedClients')))
	{
        # Store a list of Net::Netmask blocks that are valid for connections
		foreach my $ip_subnet (split(/\s*,\s*/, $cfg->get('AllowedClients')))
		{
            # We still need to use Net::IP as it validates that the ip/subnet is valid
			if (Net::IP->new($ip_subnet))
			{
                push (@{$CONFIG{'ALLOWED_CLIENTS'}}, Net::Netmask->new($ip_subnet));
			}
            else
            {
				push(@{$errormsg}, 'Invalid AllowedClient: '.Net::IP::Error().'.');
            }
		}
	}

	#
	# LOG FILE PARSING
	#
	$CONFIG{'LOG_FILE'} = $cfg->get('LogFile') if defined($cfg->get('LogFile'));
	unless ($CONFIG{'LOG_FILE'} eq 'STDERR' || $CONFIG{'LOG_FILE'} =~ /^\/[\w\.\_\-\/]+\w$/)
	{
		push(@{$errormsg}, 'Invalid LogFile: Available options [STDERR|<full path to LogFile>]');
	}

	#
	# LOG CATEGORY
	#
	if (defined($cfg->get('LogCategory')))
	{
		@{$CONFIG{'LOG_CATEGORY'}} = split(',', $cfg->get('LogCategory'));
		foreach my $category (@{$CONFIG{'LOG_CATEGORY'}})
		{
			unless ($category =~ /^(discovery|httpdir|httpstream|library)$/)
			{
				push(@{$errormsg}, 'Invalid LogCategory: Available options [discovery|httpdir|httpstream|library]');
			}
		}
		push(@{$CONFIG{'LOG_CATEGORY'}}, 'default');
	}

	#
	# LOG LEVEL PARSING
	#
	$CONFIG{'DEBUG'} = int($cfg->get('LogLevel')) if defined($cfg->get('LogLevel'));
	if ($CONFIG{'DEBUG'} < 0)
	{
		push(@{$errormsg}, 'Invalid LogLevel: Please specify the LogLevel with a positive integer.');
	}

	# TODO log date format
	# TODO tmp directory
	# TODO mplayer bin

	#
	# MEDIA DIRECTORY PARSING
	#
	foreach my $directory_block ($cfg->get('Directory'))
	{
		my $block = $cfg->block(Directory => $directory_block->[1]);
		if (!-d $directory_block->[1])
		{
			push(@{$errormsg}, 'Invalid Directory: \''.$directory_block->[1].'\' is not a directory.');
		}
		if ($block->get('type') !~ /^(audio|video|image|all)$/)
		{
			push(@{$errormsg}, 'Invalid Directory: \''.$directory_block->[1].'\' does not have a valid type.');
		}

		push(@{$CONFIG{'DIRECTORIES'}}, {
				'path' => $directory_block->[1],
				'type' => $block->get('type'),
			}
		);
	}

	return 1 if (scalar(@{$errormsg}) == 0);
	return 0;
}

1;
