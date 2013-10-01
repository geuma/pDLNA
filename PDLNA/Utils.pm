package PDLNA::Utils;

=head1 NAME

package PDLNA::Utils - helper module with sundry utilities.

=head1 DESCRIPTION

This module provides various utilities to help with things.

=cut


use strict;
use warnings;

=head1 LIBRARY FUNCTIONS

=over 12

=item internal libraries

=begin html

</p>
<a href="./Config.html">PDLNA::Config</a>,
<a href="./Log.html">PDLNA::Log</a>.
</p>

=end html

=item external libraries

L<Digest::SHA>,
L<LWP::UserAgent>,
L<Time::HiRes>.

=back

=cut

use Digest::SHA;
use LWP::UserAgent;
use Time::HiRes qw(gettimeofday);

use PDLNA::Config;
use PDLNA::Log;


=head1 METHODS

=over

=item http_date()

=cut


sub http_date
{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime();

	my @months = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',);
	my @days = ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat',);

	$year += 1900;
	$hour = add_leading_char($hour, 2, '0');
	$min = add_leading_char($min, 2, '0');
	$sec = add_leading_char($sec, 2, '0');

	return "$days[$wday], $mday $months[$mon] $year $hour:$min:$sec GMT";
}

=item add_leading_char()

=cut

sub add_leading_char
{
	my $string = shift || '';
	my $length = shift;
	my $char = shift;

	while (length($string) < $length)
	{
		$string = $char . $string;
	}

	return $string;
}

=item remove_leading_char()

=cut

sub remove_leading_char
{
	my $string = shift || '';
	my $char = shift;

	while ($string =~ /^$char/)
	{
		substr($string, 0, 1) = '';
	}
	return $string;
}

=item convert_bytes()

=cut

sub convert_bytes
{
	my $bytes = shift || 0;

	my @size = ('B', 'kB', 'MB', 'GB', 'TB');
	my $ctr = 0;
	for ($ctr = 0; $bytes > 1024; $ctr++)
	{
		$bytes /= 1024;
	}
	return sprintf("%.2f", $bytes).' '.$size[$ctr];
}

=item convert_duration()

=cut

sub convert_duration
{
	my $duration_seconds = shift || 0;

	my $seconds = $duration_seconds;
	my $minutes = 0;
	$minutes = int($seconds / 60) if $seconds > 59;
	$seconds -= $minutes * 60 if $seconds;
	my $hours = 0;
	$hours = int($minutes / 60) if $minutes > 59;
	$minutes -= $hours * 60 if $hours;
	my $days = 0;
	$days = int($hours / 24) if $hours > 23;
	$hours -= $days * 24 if $days;
	my $weeks = 0;
	$weeks = int($days / 7) if $days > 6;
	$days -= $weeks * 7 if $weeks;

	my $string = '';
	$string .= $weeks.'w ' if $weeks;
	$string .= $days.'d ' if $days;
	$string .= add_leading_char($hours,2,'0').':';
	$string .= add_leading_char($minutes,2,'0').':';
	$string .= add_leading_char($seconds,2,'0');

	return $string;
}

=item get_randid() - well, it is not real random but it's adequate.

=cut

sub get_randid
{
	my $sha = Digest::SHA->new();
	$sha->add(get_timestamp_ms());
	return $sha->hexdigest();
}

=item string_shortener()

=cut

sub string_shortener
{
	my $string = shift;
	my $length = shift;

	if (length($string) > $length)
	{
		return substr($string, 0, $length-3).'...';
	}
	return $string;

}

=item fetch_http()

=cut

sub fetch_http
{
	my $url = shift;

	my $ua = LWP::UserAgent->new();
	$ua->agent($CONFIG{'PROGRAM_NAME'}."/".PDLNA::Config::print_version());
	my $request = HTTP::Request->new(GET => $url);
	my $response = $ua->request($request);
	if ($response->is_success())
	{
		PDLNA::Log::log('Fetching URL '.$url.' was successful.', 3, 'httpgeneric');
		return $response->content();
	}
	else
	{
		PDLNA::Log::log('Fetching URL '.$url.' was NOT successful ('.$response->status_line().').', 3, 'httpgeneric');
	}
	return undef;
}

=item get_timestamp_ms()

=cut

sub get_timestamp_ms
{
	my $timestamp = int (gettimeofday() * 1000);
	return $timestamp;
}

=item is_path_absolute()


=cut

#TODO windows part.
sub is_path_absolute
{
	my $path = shift;

	return 1 if $path =~ /^\//;
	return 0;
}

=item create_filesystem_path()

=cut

#TODO windows part.
sub create_filesystem_path
{
	my $items = shift;

	return join('/', @{$items});
}

=item escape_brackets()

=cut

# TODO windows part (if needed).
sub escape_brackets
{
	my $string = shift;

	$string =~ s/\[/\\[/g;
	$string =~ s/\]/\\]/g;

	return $string;
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
