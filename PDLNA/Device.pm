package PDLNA::Device;
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

# constructor
sub new
{
	my $class = shift;
	my $params = shift;

	my $self = ();
	$self->{IP} = $$params{'ip'};
	$self->{UUID} = $$params{'uuid'};
	$self->{SSDP_BANNER} = $$params{'ssdp_banner'};
	$self->{SSDP_DESC} = $$params{'desc_location'};
	$self->{NTS} = {
		$$params{'nt'} => $$params{'time_of_expire'},
	};

	bless($self, $class);
	return $self;
}

# add a nt type to the object with its expire time
sub add_nt
{
	my $self = shift;
	my $nt = shift;
	my $expire = shift;

	$self->{NTS}->{$nt} = $expire;
}

# delete a nt type of an object
#
# RETURNS:
# amount of nt elements in the NTS hash
sub del
{
	my $self = shift;
	my $nt = shift;

	delete($self->{NTS}->{$nt}) if defined($self->{NTS}->{$nt});

	return scalar(keys %{$self->{NTS}});
}

# prints the object information
sub print_object
{
	my $self = shift;

	my $string = '';
	$string .= "\t\tObject PDLNA::Device\n";
	$string .= "\t\t\tIP:              ".$self->{IP}."\n";
	$string .= "\t\t\tUUID:            ".$self->{UUID}."\n" if defined($self->{UUID});
	$string .= "\t\t\tNTS:\n";
	foreach my $nt (keys %{$self->{NTS}})
	{
		$string .= "\t\t\t\t".$nt." (".time2str("%Y-%m-%d %H:%M", $self->{NTS}->{$nt}).")\n"
	}
	$string .= "\t\t\tSSDP Banner:     ".$self->{SSDP_BANNER}."\n" if defined($self->{SSDP_BANNER});
	$string .= "\t\t\tDescription URL: ".$self->{SSDP_DESC}."\n" if defined($self->{SSDP_DESC});

	return $string;
}

1;
