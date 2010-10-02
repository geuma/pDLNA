package PDLNA::Config;
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

use strict;
use warnings;

use base 'Exporter';

our @ISA = qw(Exporter);
our @EXPORT = qw(%CONFIG);

use Config::ApacheFormat;
use IO::Socket;
use Net::Interface qw(:lower);
use Net::IP;
use Sys::Info::OS;

my $os = Sys::Info::OS->new();

our %CONFIG = (
	# values which can be modified by configuration file
	'LOCAL_IPADDR' => undef,
	'LISTEN_INTERFACE' => undef,
	'HTTP_PORT' => 8001,
	'CACHE_CONTROL' => 1800,
	'LOG_FILE' => 'STDERR',
	'LOG_DATE_FORMAT' => '%Y-%m-%d %H:%M:%S',
	'DEBUG' => 0,
	'TMP_DIR' => '/tmp',
	'MPLAYER_BIN' => '/usr/bin/mplayer',
	'DIRECTORIES' => [],
	# values which can be modified manually :P
	'PROGRAM_NAME' => 'pDLNA',
	'PROGRAM_VERSION' => '0.26',
	'PROGRAM_DATE' => '2010-10-02',
	'PROGRAM_WEBSITE' => 'http://www.pdlna.com',
	'PROGRAM_AUTHOR' => 'Stefan Heumader',
	'PROGRAM_SERIAL' => 1337,
	'PROGRAM_DESC' => 'perl DLNA MediaServer',
	'OS' => $os->name(),
	'OS_VERSION' => $os->version(),
	'HOSTNAME' => $os->host_name(),
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
	$CONFIG{'LISTEN_INTERFACE'} = $cfg->get('ListenInterface') if defined($cfg->get('ListenInterface'));
	if (!defined($CONFIG{'LISTEN_INTERFACE'}))
	{
		my @all_ifs = Net::Interface->interfaces();
		foreach my $interface (@all_ifs)
		{
			# we are taking the first interface which is not a loopback device
			unless ($interface =~ /^lo/i)
			{
				$CONFIG{'LISTEN_INTERFACE'} = "$interface";
				last;
			}
		}
	}

	my $interface_object = Net::Interface->new($CONFIG{'LISTEN_INTERFACE'});
	if (!defined($interface_object))
	{
		push(@{$errormsg}, 'Invalid ListenInterface: The given interface does not exist on your machine.');
	}

	#
	# IP ADDR CONFIG PARSING
	#
	$CONFIG{'LOCAL_IPADDR'} = $cfg->get('ListenIPAddress') if defined($cfg->get('ListenIPAddress'));
	if (!defined($CONFIG{'LOCAL_IPADDR'}))
	{
		if (defined($interface_object))
		{
			my $address = $interface_object->address(undef, 0);
			$CONFIG{'LOCAL_IPADDR'} = inet_ntoa($address);
		}
	}
	else
	{
		if (my $ip = new Net::IP($CONFIG{'LOCAL_IPADDR'}))
		{
			$CONFIG{'LOCAL_IPADDR'} = $ip->ip();
		}
		else
		{
			push(@{$errormsg}, 'Invalid ListenIPAddress: '.Net::IP::Error().'.');
		}
	}

	if (defined($interface_object))
	{
		my @addresses = $interface_object->address();
		my $found = 0;
		foreach my $addr (@addresses)
		{
			$found = 1 if $CONFIG{'LOCAL_IPADDR'} eq inet_ntoa($addr);
		}

		unless ($found)
		{
			push(@{$errormsg}, 'Invalid ListenInterface: The given ListenIPAddress is not located on the given ListenInterface.');
		}
	}

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
	# LOG FILE PARSING
	#
	$CONFIG{'LOG_FILE'} = $cfg->get('LogFile') if defined($cfg->get('LogFile'));
	if ($CONFIG{'LOG_FILE'} ne 'STDERR')
	{
		push(@{$errormsg}, 'Invalid LogFile: Available options [STDERR]');
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
