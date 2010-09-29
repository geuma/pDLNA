package PDLNA::Log;
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

use Date::Format;

use PDLNA::Config;

sub log
{
	my $message = shift;
	my $debuglevel = shift;

	$message = add_date($message);

	write_log_msg($message) if (!defined($debuglevel) || $debuglevel <= $CONFIG{'DEBUG'});
}

sub fatal
{
	my $message = shift;
	PDLNA::Log::log($message);
	exit 1;
}

sub add_date
{
	my $message = shift;
	return time2str($CONFIG{'LOG_DATE_FORMAT'}, time()).' '.$message;
}

sub write_log_msg
{
	my $message = shift;

	if ($CONFIG{'LOG_FILE'} eq 'STDERR')
	{
		print STDERR $message . "\n";
	}
	elsif ($CONFIG{'LOG_FILE'} eq 'SYSLOG')
	{
		# TODO syslog functionality
	}
	else
	{
		append_logfile($message);
	}
}

sub append_logfile
{
	# TODO logfile functionality
}

1;
