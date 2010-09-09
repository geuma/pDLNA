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

my $osversion = `uname -r`;
chomp($osversion);

# TODO real configuration file

our %CONFIG = (
	'DEBUG' => 1,
	'LOG_FILE' => 'STDERR',
	'PROGRAM_NAME' => 'pDLNA',
	'PROGRAM_VERSION' => '0.12',
	'PROGRAM_DATE' => '2010-09-09',
	'PROGRAM_WEBSITE' => 'http://pdlna.urandom.at',
	'PROGRAM_AUTHOR' => 'Stefan Heumader',
	'PROGRAM_SERIAL' => 1337,
	'PROGRAM_DESC' => 'perl DLNA MediaServer',
	'OS' => 'Linux',
	'OS_VERSION' => $osversion,
	'LOCAL_IPADDR' => '192.168.1.130',
	'LISTEN_INTERFACE' => 'eth0',
	'HTTP_PORT' => 8001,
	'CACHE_CONTROL' => 1800,
	'UUID' => 'uuid:abfd68f2-229a-cb5d-6294-aeb7081e6a73',
	'FRIENDLY_NAME' => 'pDLNA',
);

1;
