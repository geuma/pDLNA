package PDLNA::Log;

=head1 NAME

package PDLNA::Log - helper module for logging.

=head1 DESCRIPTION

This module provides application logging.

=cut


use strict;
use warnings;

=head1 LIBRARY FUNCTIONS

=over 12

=item internal libraries

=begin html

</p>
<a href="./Config.html">PDLNA::Config</a>.
</p>

=end html

=item external libraries

L<Date::Format>,
L<Fcntl>,
L<Sys::Syslog>.

=back

=cut

use Date::Format;
use Fcntl ':flock';
use Sys::Syslog qw(:standard :macros);

use PDLNA::Config;


=head1 METHODS

=over

=item log()

=cut

sub log
{
	my $message = shift;
	my $debuglevel = shift || 0;
	my $category = shift || undef;

	if (
		$debuglevel == 0 ||
		(
			$debuglevel <= $CONFIG{'DEBUG'} &&
			(defined($category) && grep(/^$category$/, @{$CONFIG{'LOG_CATEGORY'}}))
		)
	)
	{
		$message = add_message_info($message, $debuglevel, $category);
		write_log_msg($message, $debuglevel, $category);
	}
}

=item fatal()

=cut

sub fatal
{
	my $message = shift;

	print STDERR $message."\n";
	print STDERR "Going to terminate $CONFIG{'PROGRAM_NAME'}/v".PDLNA::Config::print_version()." on $CONFIG{'OS'}/$CONFIG{'OS_VERSION'} with FriendlyName '$CONFIG{'FRIENDLY_NAME'}' ...\n";

	exit 1;
}

=item add_message_info()

=cut

sub add_message_info
{
	my $message = shift;
	my $debuglevel = shift;
	my $category = shift;

	return $message if $CONFIG{'LOG_FILE'} eq 'SYSLOG';
	return time2str($CONFIG{'DATE_FORMAT'}, time()).' '.$category.'('.$debuglevel.'): '.$message;
}

=item write_log_msg()

=cut

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

=item append_logfile()

=cut

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
