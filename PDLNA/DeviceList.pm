package PDLNA::DeviceList;
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

use threads;
use threads::shared;

use PDLNA::Device;

# constructor
sub new
{
	my $class = shift;

	my %self : shared = ();
	my %devices : shared = ();
	$self{DEVICES} = \%devices;

	bless(\%self, $class);
	return \%self;
}

# adds a new Device object to the DeviceList object
sub add
{
	my $self = shift;
	my $params = shift;

	if (defined($self->{DEVICES}{$$params{'ip'}}))
	{
		$self->{DEVICES}{$$params{'ip'}}->http_useragent($$params{'http_useragent'});
		$self->{DEVICES}{$$params{'ip'}}->add_nt($$params{'nt'}, $$params{'time_of_expire'}) if defined($$params{'nt'});
		$self->{DEVICES}{$$params{'ip'}}->uuid($$params{'uuid'}) if defined($$params{'uuid'});
		$self->{DEVICES}{$$params{'ip'}}->ssdp_desc($$params{'desc_location'}) if defined($$params{'desc_location'});
		$self->{DEVICES}{$$params{'ip'}}->ssdp_banner($$params{'ssdp_banner'}) if defined($$params{'ssdp_banner'});
	}
	else
	{
		$self->{DEVICES}{$$params{'ip'}} = PDLNA::Device->new($params);
	}
	$self->{DEVICES}{$$params{'ip'}}->fetch_xml_info();
}

# deletes a nt type from the Device by IP
# if there's no nt type left, it deletes the whole Device object
sub del
{
	my $self = shift;
	my $ip = shift;
	my $nt = shift;

	my $elements = 1;
	$elements = $self->{DEVICES}{$ip}->del($nt) if defined($self->{DEVICES}{$ip});
	delete($self->{DEVICES}->{$ip}) if $elements == 0;
}

sub devices
{
	my $self = shift;
	return %{$self->{DEVICES}};
}

# prints the object
sub print_object
{
	my $self = shift;

	my $string = "\n\tObject PDLNA::DeviceList\n";
	foreach my $device (keys %{$self->{DEVICES}})
	{
		$string .= $self->{DEVICES}{$device}->print_object();
	}
	$string .= "\tObject PDLNA::DeviceList END";
	return $string;
}

1;
