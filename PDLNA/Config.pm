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

my $osversion = `uname -r`;
chomp($osversion);
my $hostname = `hostname`;
chomp($hostname);

our %CONFIG = (
	# values which can be modified by configuration file
	'LOCAL_IPADDR' => undef,
	'LISTEN_INTERFACE' => undef,
	'HTTP_PORT' => 8001,
	'CACHE_CONTROL' => 1800,
	'LOG_FILE' => 'STDERR',
	'DEBUG' => 0,
	'DIRECTORIES' => [],
	# values which can be modified manually :P
	'PROGRAM_NAME' => 'pDLNA',
	'PROGRAM_VERSION' => '0.19',
	'PROGRAM_DATE' => '2010-09-20',
	'PROGRAM_WEBSITE' => 'http://pdlna.urandom.at',
	'PROGRAM_AUTHOR' => 'Stefan Heumader',
	'PROGRAM_SERIAL' => 1337,
	'PROGRAM_DESC' => 'perl DLNA MediaServer',
	'OS' => 'Linux',
	'OS_VERSION' => $osversion,
	'UUID' => 'uuid:abfd68f2-229a-cb5d-6294-aeb7081e6a73',
);
$CONFIG{'FRIENDLY_NAME'} = 'pDLNA v'.$CONFIG{'PROGRAM_VERSION'}.' on '.$hostname;

sub parse_config
{
	my $file = shift;
	return 0 unless -f $file;

	my $cfg = Config::ApacheFormat->new(
		valid_blocks => [qw(Directory)],
	);
	$cfg->read($file);

	$CONFIG{'FRIENDLY_NAME'} = $cfg->get('FriendlyName') if defined($cfg->get('FriendlyName'));
	$CONFIG{'LOCAL_IPADDR'} = $cfg->get('ListenIPAddress') if defined($cfg->get('ListenIPAddress'));
	$CONFIG{'LISTEN_INTERFACE'} = $cfg->get('ListenInterface') if defined($cfg->get('ListenInterface'));
	$CONFIG{'HTTP_PORT'} = $cfg->get('HTTPPort') if defined($cfg->get('HTTPPort'));
	$CONFIG{'CACHE_CONTROL'} = $cfg->get('CacheControl') if defined($cfg->get('CacheControl'));
	$CONFIG{'LOG_FILE'} = $cfg->get('LogFile') if defined($cfg->get('LogFile'));
	$CONFIG{'DEBUG'} = $cfg->get('LogLevel') if defined($cfg->get('LogLevel'));

	# Directory parsing
	foreach my $directory_block ($cfg->get('Directory'))
	{
		my $block = $cfg->block(Directory => $directory_block->[1]);
		push(@{$CONFIG{'DIRECTORIES'}}, {
				'path' => $directory_block->[1],
				'type' => $block->get('type'),
			}
		);
	}

	# TODO local ip address error handling
	# TODO listening interface error handling
	# TODO directories error handling

	return 1;
}

1;
