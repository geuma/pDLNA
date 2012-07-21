package PDLNA::Log;
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

use strict;
use warnings;

use Date::Format;
use Fcntl ':flock';
use Sys::Syslog qw(:standard :macros);

use PDLNA::Config;

sub log
{
	my $message = shift;
	my $debuglevel = shift;
	my $category = shift || undef;

	if (
		(!defined($debuglevel) || $debuglevel <= $CONFIG{'DEBUG'}) &&
		(defined($category) && grep(/^$category$/, @{$CONFIG{'LOG_CATEGORY'}}))
	)
	{
		$message = add_message_info($message, $debuglevel, $category);
		write_log_msg($message, $debuglevel, $category);
	}
}

sub fatal
{
	my $message = shift;

	print STDERR $message."\n";
	print STDERR "Going to terminate $CONFIG{'PROGRAM_NAME'}/v".PDLNA::Config::print_version()." on $CONFIG{'OS'}/$CONFIG{'OS_VERSION'} with FriendlyName '$CONFIG{'FRIENDLY_NAME'}' ...\n";

	exit 1;
}

sub add_message_info
{
	my $message = shift;
	my $debuglevel = shift;
	my $category = shift;

	return $message if $CONFIG{'LOG_FILE'} eq 'SYSLOG';
	return time2str($CONFIG{'DATE_FORMAT'}, time()).' '.$category.'('.$debuglevel.'): '.$message;
}

sub write_log_msg
{
	my $message = shift;
	my $debuglevel = shift;
	my $category = shift;

	if ($CONFIG{'LOG_FILE'} eq 'STDERR')
	{
		print STDERR $message . "\n";
	}
	elsif ($CONFIG{'LOG_FILE'} eq 'SYSLOG')
	{
		openlog($CONFIG{'PROGRAM_NAME'}.' ('.$category.')', 'ndelay', LOG_LOCAL0);
		syslog(LOG_INFO, $message);
	}
	else
	{
		append_logfile($message);
	}
}

sub append_logfile
{
	my $message = shift;

	my $filesize = (stat($CONFIG{'LOG_FILE'}))[7] || 0;

	if ($filesize > $CONFIG{'LOG_FILE_MAX_SIZE'})
	{
		open(FILE, ">$CONFIG{'LOG_FILE'}");
	}
	else
	{
		open(FILE, ">>$CONFIG{'LOG_FILE'}");
	}

	flock(FILE, LOCK_EX);
	print FILE $message."\n";
	flock(FILE, LOCK_UN);
	close(FILE);
}

1;
