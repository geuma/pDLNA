package PDLNA::DeviceList;
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

use PDLNA::Device;

# constructor
sub new
{
	my $class = shift;

	my $self = ();
	$self->{DEVICES} = ();

	bless($self, $class);
	return $self;
}

# adds a new Device object to the DeviceList object
sub add
{
	my $self = shift;
	my $params = shift;

	if (defined($self->{DEVICES}->{$$params{'ip'}}))
	{
		$self->{DEVICES}->{$$params{'ip'}}->add_nt($$params{'nt'}, $$params{'time_of_expire'});
	}
	else
	{
		$self->{DEVICES}->{$$params{'ip'}} = PDLNA::Device->new($params);
	}
}

# deletes a nt type from the Device by IP
# if there's no nt type left, it deletes the whole Device object
sub del
{
	my $self = shift;
	my $ip = shift;
	my $nt = shift;

	my $elements = 1;
	$elements = $self->{DEVICES}->{$ip}->del($nt) if defined($self->{DEVICES}->{$ip});
	delete($self->{DEVICES}->{$ip}) if $elements == 0;
}

# prints the object
sub print_object
{
	my $self = shift;

	my $string = "\n\tObject PDLNA::DeviceList\n";
	foreach my $device (keys %{$self->{DEVICES}})
	{
		$string .= $self->{DEVICES}->{$device}->print_object();
	}
	return $string;
}

1;
