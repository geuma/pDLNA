package PDLNA::Daemon;
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

use POSIX qw(setsid);
use Fcntl ':flock';

use PDLNA::Config;
use PDLNA::Log;
use PDLNA::SSDP;

sub daemonize
{
	my $SIG = $_[0];

	$$SIG{'INT'} = \&exit_daemon;
	$$SIG{'HUP'} = \&exit_daemon;
	$$SIG{'ABRT'} = \&exit_daemon;
	$$SIG{'QUIT'} = \&exit_daemon;
	$$SIG{'TRAP'} = \&exit_daemon;
	$$SIG{'STOP'} = \&exit_daemon;
	$$SIG{'TERM'} = \&exit_daemon;
	$$SIG{'PIPE'} = 'IGNORE'; # SIGPIPE Problem: http://www.nntp.perl.org/group/perl.perl5.porters/2004/04/msg91204.html

	my $pid = fork;
	exit if $pid;
	die "Couldn't fork: $!" unless defined($pid);
}

sub exit_daemon
{
	PDLNA::Log::log("Shutting down $CONFIG{'PROGRAM_NAME'} v$CONFIG{'PROGRAM_VERSION'}. It may take some time ...", 0, 'default');

	PDLNA::SSDP::byebye();
	PDLNA::SSDP::byebye();

	remove_pidfile($CONFIG{'PIDFILE'});

	# TODO join the threads, it is ugly that way

	exit(1);
}

sub write_pidfile
{
	my $pidfile = $_[0];
	my $pid = $_[1];

	open(FILE, ">$pidfile");
	flock(FILE, LOCK_EX);
	print FILE $pid;
	flock(FILE, LOCK_UN);
	close(FILE);
}

sub read_pidfile
{
	my $pidfile = $_[0];

	my $pid = -1;

	if (-e $pidfile)
	{
		open(FILE, $pidfile);
		$pid = <FILE>;
		close(FILE);
	}

	chomp ($pid);

	return $pid;
}

sub remove_pidfile
{
	my $pidfile = $_[0];

	if (-e $pidfile)
	{
		unlink($pidfile);
	}
}

1;
