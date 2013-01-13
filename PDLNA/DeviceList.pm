package PDLNA::DeviceList;
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2013 Stefan Heumader <stefan@heumader.at>
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

# adds/updates a new/existing Device object to the DeviceList object
sub add
{
	my $self = shift;
	my $params = shift;

	if (defined($self->{DEVICES}{$$params{'ip'}}))
	{
		$self->{DEVICES}{$$params{'ip'}}->add_udn(
			{
				'udn' => $$params{'udn'},
				'ssdp_banner' => $$params{'ssdp_banner'},
				'device_description_location' => $$params{'device_description_location'},
				'nt' => $$params{'nt'},
				'nt_time_of_expire' => $$params{'nt_time_of_expire'},
			},
		);
		$self->{DEVICES}{$$params{'ip'}}->last_seen_timestamp(time());
	}
	else
	{
		$self->{DEVICES}{$$params{'ip'}} = PDLNA::Device->new($params);
	}
}

# deletes a NT from the PDLNA::Device by IP
sub del
{
	my $self = shift;
	my $params = shift;

	if (defined($self->{DEVICES}{$$params{'ip'}}))
	{
		$self->{DEVICES}{$$params{'ip'}}->del_udn(
			{
				'udn' => $$params{'udn'},
				'nt' => $$params{'nt'},
			},
		);
	}
}

# calls del() function to deleted expired NT from database
sub delete_expired
{
	my $self = shift;

	my $time = time();
	foreach my $ip (keys %{$self->{DEVICES}})
	{
		foreach my $udn (keys %{$self->{DEVICES}{$ip}->udn()})
		{
			foreach my $nt (keys %{$self->{DEVICES}{$ip}{UDN}{$udn}->nts()})
			{
				if ($time > $self->{DEVICES}{$ip}{UDN}{$udn}{NTS}{$nt})
				{
					PDLNA::Log::log('Deleting expired NT '.$nt.' from UPnP device ('.$ip.'/'.$udn.') from database.', 2, 'discovery');
					$self->{DEVICES}{$ip}->del_udn(
						{
							'udn' => $udn,
							'nt' => $nt,
						},
					);
				}
			}
		}

		if (defined($self->{DEVICES}{$ip}))
		{
			my $udn_amount = $self->{DEVICES}{$ip}->udn_amount();
			my $expire_time = $self->{DEVICES}{$ip}->last_seen_timestamp() + $CONFIG{CACHE_CONTROL};
			if ($udn_amount == 0 && $expire_time < $time)
			{
				PDLNA::Log::log('Deleting expired UPnP device ('.$ip.') from database.', 2, 'discovery');
				delete($self->{DEVICES}->{$ip});
			}
		}
	}
	PDLNA::Log::log($self->print_object(), 3, 'discovery');
}

# returns reference to DEVICES hash
sub devices
{
	my $self = shift;
	return %{$self->{DEVICES}};
}

# returns amount of DEVICES
sub devices_amount
{
	my $self = shift;
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

	my $string = "\n\tObject PDLNA::DeviceList\n";
	foreach my $device (keys %{$self->{DEVICES}})
	{
		$string .= $self->{DEVICES}{$device}->print_object();
	}
	$string .= "\tObject PDLNA::DeviceList END";
	return $string;
}

1;
