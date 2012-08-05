package PDLNA::Utils;
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

use Digest::SHA1;
use LWP::UserAgent;

use PDLNA::Config;
use PDLNA::Log;

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

sub convert_bytes
{
	my $bytes = shift;

	my @size = ('B', 'kB', 'MB', 'GB', 'TB');
	my $ctr;
	for ($ctr = 0; $bytes > 1024; $ctr++)
	{
		$bytes /= 1024;
	}
	return sprintf("%.2f", $bytes).' '.$size[$ctr];
}

# well, it is not real random ... but it's adequate
sub get_randid
{
	my $sha1 = Digest::SHA1->new;
	$sha1->add(time());
	return $sha1->hexdigest;
}

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

1;
