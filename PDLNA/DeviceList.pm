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

use PDLNA::Config;
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
	#lock($self);
	my $params = shift;

	if (defined($self->{DEVICES}{$$params{'ip'}}))
	{
		$self->{DEVICES}{$$params{'ip'}}->http_useragent($$params{'http_useragent'});
		$self->{DEVICES}{$$params{'ip'}}->add_nt($$params{'nt'}, $$params{'time_of_expire'}) if defined($$params{'nt'});
		$self->{DEVICES}{$$params{'ip'}}->uuid($$params{'uuid'}) if defined($$params{'uuid'});
		$self->{DEVICES}{$$params{'ip'}}->ssdp_desc($$params{'desc_location'}) if defined($$params{'desc_location'});
		$self->{DEVICES}{$$params{'ip'}}->ssdp_banner($$params{'ssdp_banner'}) if defined($$params{'ssdp_banner'});
		$self->{DEVICES}{$$params{'ip'}}->last_seen_timestamp(time());
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
	#lock($self);
	my $ip = shift;
	my $nt = shift;

	my $elements = 1;
	$elements = $self->{DEVICES}{$ip}->del($nt) if defined($self->{DEVICES}{$ip});
	delete($self->{DEVICES}->{$ip}) if $elements == 0;
}

# calls del() function to deleted expired NT types from database
sub delete_expired
{
	my $self = shift;
	#lock($self);

	my $time = time();

	foreach my $ip (keys %{$self->{DEVICES}})
	{
		foreach my $nt (keys %{$self->{DEVICES}{$ip}{NTS}})
		{
			if ($time > $self->{DEVICES}{$ip}{NTS}{$nt})
			{
				PDLNA::Log::log('Deleting expired NT '.$nt.' for UPnP device ('.$ip.') from database.', 2, 'discovery');
				$self->del($ip, $nt);
			}
		}

		if (defined($self->{DEVICES}{$ip}))
		{
			my $elements = 1;
			$elements = $self->{DEVICES}{$ip}->nts_amount() if defined($self->{DEVICES}{$ip});
			my $expire_time = $self->{DEVICES}{$ip}->last_seen_timestamp() + $CONFIG{CACHE_CONTROL};
			if ($expire_time < $time && $elements == 0)
			{
				PDLNA::Log::log('Deleting expired UPnP device ('.$ip.') from database.', 2, 'discovery');
				delete($self->{DEVICES}->{$ip});
			}
		}
		PDLNA::Log::log($self->print_object(), 3, 'discovery');
	}
}

sub devices
{
	my $self = shift;
	#lock($self);
	return %{$self->{DEVICES}};
}

sub devices_amount
{
	my $self = shift;
	#lock($self);
	my $amount = 0;
	foreach my $ip (keys %{$self->{DEVICES}})
	{
		$amount++;
	}
	return $amount;
}

# prints the object
sub print_object
{
	my $self = shift;
	#lock($self);

	my $string = "\n\tObject PDLNA::DeviceList\n";
	foreach my $device (keys %{$self->{DEVICES}})
	{
		$string .= $self->{DEVICES}{$device}->print_object();
	}
	$string .= "\tObject PDLNA::DeviceList END";
	return $string;
}

1;
