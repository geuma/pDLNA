package PDLNA::Devices;
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

use File::Basename;
use URI::Split qw(uri_split uri_join);
use XML::Simple;

use PDLNA::Config;
use PDLNA::Database;

sub add_device
{
	my $params = shift;

	#
	# BEGIN OF IP
	#
	my $device_ip_id = PDLNA::Database::device_ip_touch($$params{'ip'}, $$params{'http_useragent'} );

	#
	# BEGIN OF UDN
	#
	return 0 unless defined($$params{'udn'});
	return 0 unless defined($$params{'ssdp_banner'});
	return 0 unless defined($$params{'device_description_location'});

    my $device_udn_id;
	my @results = PDLNA::Database::get_records_by("DEVICE_UDN", { DEVICE_IP_REF => $device_ip_id, UDN => $$params{'udn'}});
	
	if (@results)
	{
		# we got nothing to do here
        $device_udn_id = $results[0]->{ID};
	}
	else
	{
		my %services = ();
		my ($device_udn_base_url, $device_udn_rela_url) = '';
		my ($device_udn_devicetype, $device_udn_modelname, $device_udn_friendlyname) = '';
		if (defined($$params{'device_description_location'}))
		{
			my ($scheme, $auth, $path, $query, $frag) = uri_split($$params{'device_description_location'});
			$device_udn_base_url = uri_join($scheme, $auth);
			$device_udn_rela_url = uri_join($scheme, $auth, dirname($path));
			$device_udn_rela_url = substr($device_udn_rela_url, 0, -1) if $device_udn_rela_url =~ /\/$/; # remove / at the end (if any)

			my $response = PDLNA::Utils::fetch_http($$params{'device_description_location'});
			if ($response)
			{
				my $xs = XML::Simple->new();
				my $xml = eval { $xs->XMLin($response) };
				if ($@)
				{
					PDLNA::Log::log('Error parsing XML Device Description in PDLNA::Devices: '.$@, 3, 'discovery');
				}
				else
				{
					$device_udn_devicetype = $xml->{'device'}->{'deviceType'} if defined($xml->{'device'}->{'deviceType'});
					$device_udn_modelname = $xml->{'device'}->{'modelName'} if defined($xml->{'device'}->{'modelName'});
					$device_udn_friendlyname = $xml->{'device'}->{'friendlyName'} if defined($xml->{'device'}->{'friendlyName'});

					# add DEVICE_SERVICE
					if (ref($xml->{'device'}->{'serviceList'}->{'service'}) eq 'ARRAY') # we need to check if it is an array
					{
						foreach my $service (@{$xml->{'device'}->{'serviceList'}->{'service'}})
						{
							my %service_configuration = (
								'serviceId' => $service->{'serviceId'},
								'serviceType' => $service->{'serviceType'},
							);
							foreach my $url ('controlURL', 'eventSubURL', 'SCPDURL')
							{
								if ($service->{$url} =~ /^\//)
								{
									$service_configuration{$url} = $device_udn_base_url.$service->{$url};
								}
								else
								{
									$service_configuration{$url} = $device_udn_rela_url.'/'.$service->{$url};
								}
							}
							$services{$service->{'serviceId'}} = \%service_configuration;
						}
					}
					else
					{
						my $service = $xml->{'device'}->{'serviceList'}->{'service'};
						my %service_configuration = (
							'serviceId' => $service->{'serviceId'},
							'serviceType' => $service->{'serviceType'},
						);
						foreach my $url ('controlURL', 'eventSubURL', 'SCPDURL')
						{
							if ($service->{$url} =~ /^\//)
							{
								$service_configuration{$url} = $device_udn_base_url.$service->{$url};
							}
							else
							{
								$service_configuration{$url} = $device_udn_rela_url.'/'.$service->{$url};
							}
						}
						$services{$service->{'serviceId'}} = \%service_configuration;
					}
				}
			}
		}

		if (defined($device_udn_modelname) && defined($device_udn_friendlyname))
		{
            PDLNA::Database::device_udn_insert($device_ip_id, $$params{'udn'}, $$params{'ssdp_banner'}, $$params{'device_description_location'}, $device_udn_base_url, $device_udn_rela_url, $device_udn_devicetype, $device_udn_modelname, $device_udn_friendlyname);
			my @results = PDLNA::Database::get_records_by("DEVICE_UDN",{ DEVICE_IP_REF => $device_ip_id, UDN => $$params{'udn'}});
            $device_udn_id = $results[0]->{ID};
			# create the DEVICE_SERVICE entries
			foreach my $service (keys %services)
			{
				if (defined($services{$service}->{'serviceId'}) && defined($services{$service}->{'controlURL'}) && defined($services{$service}->{'eventSubURL'}) && defined($services{$service}->{'SCPDURL'}))
				{
                                        PDLNA::Database::device_service_insert( $device_udn_id, $services{$service}->{'serviceId'}, $services{$service}->{'serviceType'}, $services{$service}->{'controlURL'}, $services{$service}->{'eventSubURL'}, $services{$service}->{'SCPDURL'});
										
				}
			}
		}
	}
	#
	# END OF UDN
	#

	#
	# BEGIN OF NTS
	#
	return 0 unless defined($$params{'nt'});
	return 0 unless defined($$params{'nt_time_of_expire'});


    PDLNA::Database::device_nts_touch($device_udn_id,$$params{'nt'},$$params{'nt_time_of_expire'});
	#
	# END OF NTS
	#
}

sub delete_expired_devices
{

	# delete expired DEVICE_NTS entries
        PDLNA::Database::device_nts_delete_expired();
        
	# delete DEVICE_UDN entries with no NTS entries
	PDLNA::Database::device_udn_delete_without_nts();
}

sub delete_device
{
	my $params = shift;

	return 0 if !defined($$params{'ip'});
	return 0 if !defined($$params{'udn'});
	return 0 if !defined($$params{'nt'});

	my $device_ip  = PDLNA::Database::device_ip_get_id($$params{'ip'});
	my $device_udn_id = (PDLNA::Database::get_records_by("DEVICE_UDN", { DEVICE_IP_REF => $device_ip->{ID}, UDN => $$params{'udn'}}))[0]->{ID} if defined($device_ip);
    my $device_nts_id = PDLNA::Database::device_nts_get_id($device_udn_id, $$params{'nt'}) if defined($device_udn_id);

	PDLNA::Database::device_nts_delete($device_nts_id) if defined($device_nts_id);

	if (defined($device_udn_id))
	{
		my $device_nts_amount = PDLNA::Database::device_nts_amount($device_udn_id);
		PDLNA::Database::device_udn_delete_by_id($device_udn_id) if $device_nts_amount == 0;
	}
}

sub get_modelname_by_devicetype
{
	my $ip = shift;
	my $devicetype = shift;
	
	my @modelnames = PDLNA::Database::device_udn_get_modelname($ip);
        my @device_udns = PDLNA::Database::device_nts_device_udn_ref($devicetype);	
	foreach my $modelname (@modelnames)
	{
	  
		if (defined($device_udns[0]->{DEVICE_UDN_REF}) && $device_udns[0]->{DEVICE_UDN_REF} == $modelname->{ID})
		{
			return $modelname->{MODEL_NAME};
		}
	}
	return '';
}

##
##
1;
