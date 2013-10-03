package PDLNA::Daemon;

=head1 NAME

package PDLNA::Daemon - to daemonise pDLNA.pl.

=head1 DESCRIPTION

This package provides the scaffolding for adding pdlna to the operating system as a daemon such as managing pidfile.

=cut


use strict;
use warnings;

=head1 LIBRARY FUNCTIONS

=over 12

=item internal libraries

=begin html

</p>
<a href="./Config.html">PDLNA::Config</a>,
<a href="./Log.html">PDLNA::Log</a>,
<a href="./SSDP.html">PDLNA::SSDP</a>.
</p>

=end html

=item external libraries

L<POSIX>,
L<Fcntl>.

=back

=cut

use POSIX qw(setsid);
use Fcntl ':flock';

use PDLNA::Config;
use PDLNA::Log;
use PDLNA::SSDP;

=head1 METHODS

=over

=item daemonize() - forks a new process to run pDLNA.

=cut


sub daemonize
{
	my $SIG = shift;
	PDLNA::Log::log('Calling PDLNA::Daemon::daemonize().', 3, 'default');
	my $ssdp = shift; # ugly, but works for now

	#
	# SIGNAL HANDLING GOT MESSED UP (currently not able to call ref of a function)
	#
	$SIG{'INT'} = sub
	{
		PDLNA::Log::log("Shutting down $CONFIG{'PROGRAM_NAME'} v".PDLNA::Config::print_version().". It may take some time ...", 0, 'default');
		$$ssdp->send_byebye(4);
		remove_pidfile($CONFIG{'PIDFILE'});
		exit(1);
	};
#	$SIG{'INT'}  = \&exit_daemon();
#	$SIG{'HUP'}  = \&exit_daemon();
#	$SIG{'ABRT'} = \&exit_daemon();
#	$SIG{'QUIT'} = \&exit_daemon();
#	$SIG{'TRAP'} = \&exit_daemon();
#	$SIG{'STOP'} = \&exit_daemon();
#	$SIG{'TERM'} = \&exit_daemon();
	$SIG{'TERM'} = sub
	{
		PDLNA::Log::log("Shutting down $CONFIG{'PROGRAM_NAME'} v".PDLNA::Config::print_version().". It may take some time ...", 0, 'default');
		$$ssdp->send_byebye(4);
		remove_pidfile($CONFIG{'PIDFILE'});
		exit(1);
	};
	$SIG{'PIPE'} = 'IGNORE'; # SIGPIPE Problem: http://www.nntp.perl.org/group/perl.perl5.porters/2004/04/msg91204.html

	my $pid = fork;
	exit if $pid;
	die "Couldn't fork: $!" unless defined($pid);
}

=item exit_daemon()

=cut

sub exit_daemon
{
	PDLNA::Log::log("Shutting down $CONFIG{'PROGRAM_NAME'} v".PDLNA::Config::print_version().". It may take some time ...", 0, 'default');
#	$$ssdp->send_byebye(4);
	remove_pidfile($CONFIG{'PIDFILE'});
	exit(1);
}

=item write_pidfile()

=cut

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

=item read_pidfile()

=cut

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

=item remove_pidfile()

=cut

sub remove_pidfile
{
	my $pidfile = $_[0];

	if (-e $pidfile)
	{
		unlink($pidfile);
	}
}


=back

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010-2013 Stefan Heumader L<E<lt>stefan@heumader.atE<gt>>.

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
You should have received a copy of the GNU General Public License
along with this program.  If not, see L<http://www.gnu.org/licenses/>.

=cut

1;
