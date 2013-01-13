package PDLNA::DeviceUDN;
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

use Date::Format;
use File::Basename;
use URI::Split qw(uri_split uri_join);
use XML::Simple;

use PDLNA::Config;
use PDLNA::DeviceService;
use PDLNA::Log;
use PDLNA::Utils;

# constructor
sub new
{
	my $class = shift;
	my $params = shift;

	my %self : shared = (
		UDN => $$params{'udn'},
		SSDP_BANNER => $$params{'ssdp_banner'},
		DEV_DESC_URL => $$params{'device_description_location'},
		DEV_BASE_URL => '',
		DEV_RELA_URL => '',
		DEVICE_TYPE => '',
		MODEL_NAME => '',
		FRIENDLY_NAME => '',
		URI => '',
	);

	my %nts : shared = ();
	$nts{$$params{'nt'}} = $$params{'nt_time_of_expire'} if defined($$params{'nt'});
	$self{NTS} = \%nts;

	my %services : shared = ();
	if (defined($self{DEV_DESC_URL}))
	{
		my ($scheme, $auth, $path, $query, $frag) = uri_split($self{DEV_DESC_URL});
		$self{DEV_BASE_URL} = uri_join($scheme, $auth);
		$self{DEV_RELA_URL} = uri_join($scheme, $auth, dirname($path));
		$self{DEV_RELA_URL} = substr($self{DEV_RELA_URL}, 0, -1) if $self{DEV_RELA_URL} =~ /\/$/; # remove / at the end (if any)

		my $response = PDLNA::Utils::fetch_http($self{DEV_DESC_URL});
		if ($response)
		{
			my $xs = XML::Simple->new();
			my $xml = eval { $xs->XMLin($response) };
			if ($@)
			{
				PDLNA::Log::log('Error parsing XML Device Description in PDLNA::DeviceUDN:'.$@, 3, 'discovery');
			}
			else
			{
				$self{DEVICE_TYPE} = $xml->{'device'}->{'deviceType'} if defined($xml->{'device'}->{'deviceType'});
				$self{MODEL_NAME} = $xml->{'device'}->{'modelName'} if defined($xml->{'device'}->{'modelName'});
				$self{FRIENDLY_NAME} = $xml->{'device'}->{'friendlyName'} if defined($xml->{'device'}->{'friendlyName'});

				if (ref($xml->{'device'}->{'serviceList'}->{'service'}) eq 'ARRAY') # we need to check if it is an array
				{
					foreach my $service (@{$xml->{'device'}->{'serviceList'}->{'service'}})
					{
						my %service_configuration = (
							'service_id' => $service->{'serviceId'},
							'service_type' => $service->{'serviceType'},
						);
						foreach my $url ('controlURL', 'eventSubURL', 'SCPDURL')
						{
							if ($service->{$url} =~ /^\//)
							{
								$service_configuration{$url} = $self{DEV_BASE_URL}.$service->{$url};
							}
							else
							{
								$service_configuration{$url} = $self{DEV_RELA_URL}.'/'.$service->{$url};
							}
						}
						$services{$service->{'serviceId'}} = PDLNA::DeviceService->new(\%service_configuration);
					}
				}
			}
		}
	}
	$self{SERVICES} = \%services;

	bless(\%self, $class);
	return \%self;
}

# adds or updates a new/exitsing NT
sub add_nt
{
	my $self = shift;
	my $params = shift;

	$self->{NTS}->{$$params{'nt'}} = $$params{'nt_time_of_expire'};
}

# deletes an existing NT
#
# RETURNS:
# amount of nt elements in the NTS hash
sub del_nt
{
	my $self = shift;
	my $params = shift;

	if (defined($$params{'nt'}) && defined($self->{NTS}->{$$params{'nt'}}))
	{
		delete($self->{NTS}->{$$params{'nt'}});
	}
	return $self->nts_amount();
}

# return reference to NTS hash
sub nts
{
	my $self = shift;

	return $self->{NTS};
}

# returns amount of elements in NTS hash
sub nts_amount
{
	my $self = shift;

	my $amount = 0;
	foreach my $nt (keys %{$self->{NTS}})
	{
		$amount++;
	}
	return $amount;
}

# prints the object information
sub print_object
{
	my $self = shift;

	my $string = '';
	$string .= "\t\t\tObject PDLNA::DeviceUDN\n";
	$string .= "\t\t\t\tUDN:                    ".$self->{UDN}."\n" if defined($self->{UDN});
	$string .= "\t\t\t\tSSDP Banner:            ".$self->{SSDP_BANNER}."\n" if defined($self->{SSDP_BANNER});
	$string .= "\t\t\t\tDevice Description URL: ".$self->{DEV_DESC_URL}."\n" if defined($self->{DEV_DESC_URL});
	$string .= "\t\t\t\tDevice Relative URL:    ".$self->{DEV_RELA_URL}."\n" if defined($self->{DEV_RELA_URL});
	$string .= "\t\t\t\tDevice Base URL:        ".$self->{DEV_BASE_URL}."\n" if defined($self->{DEV_BASE_URL});
	$string .= "\t\t\t\tURI:                    ".$self->{URI}."\n" if defined($self->{URI});
	$string .= "\t\t\t\tNTS:\n";
	foreach my $nt (keys %{$self->{NTS}})
	{
		$string .= "\t\t\t\t\t".$nt." (expires at ".time2str($CONFIG{'DATE_FORMAT'}, $self->{NTS}->{$nt}).")\n"
	}
	$string .= "\t\t\t\tDeviceType              ".$self->{DEVICE_TYPE}."\n" if defined($self->{DEVICE_TYPE});
	$string .= "\t\t\t\tModelName               ".$self->{MODEL_NAME}."\n" if defined($self->{MODEL_NAME});
	$string .= "\t\t\t\tFriendlyName            ".$self->{FRIENDLY_NAME}."\n" if defined($self->{FRIENDLY_NAME});
	foreach my $service (keys %{$self->{SERVICES}})
	{
		$string .= $self->{SERVICES}{$service}->print_object();;
	}
	$string .= "\t\t\tObject PDLNA::DeviceUDN END\n";

	return $string;
}

sub ssdp_banner
{
	my $self = shift;
	my $ssdp_banner = shift;

	$self->{SSDP_BANNER} = $ssdp_banner if defined($ssdp_banner);
	return $self->{SSDP_BANNER} || '';
}

sub friendly_name
{
	my $self = shift;
	my $friendly_name = shift;

	$self->{FRIENDLY_NAME} = $friendly_name if defined($friendly_name);
	return $self->{FRIENDLY_NAME} || '';
}

sub model_name
{
	my $self = shift;
	my $model_name = shift;

	$self->{MODEL_NAME} = $model_name if defined($model_name);
	return $self->{MODEL_NAME} || '';
}

sub device_type
{
	my $self = shift;
	my $device_type = shift;

	$self->{DEVICE_TYPE} = $device_type if defined($device_type);
	return $self->{DEVICE_TYPE} || '';
}

sub device_description_url
{
	my $self = shift;
	my $ssdp_desc = shift;

	$self->{DEV_DESC_URL} = $ssdp_desc if defined($ssdp_desc);
	return $self->{DEV_DESC_URL} || '';
}

1;
