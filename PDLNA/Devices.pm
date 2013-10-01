package PDLNA::Devices;

=head1 NAME

package PDLNA::Devices - to mange dnla devices

=head1 DESCRIPTION

In DLNA, Devices are network entities that provide services. Services are
the basic unit of control. They provide actions and maintain status.
This module browses the network and sets entries in the database
describing what is finds and uses the information later in helper
functions.

=cut


use strict;
use warnings;

=head1 LIBRARY FUNCTIONS

=over 12

=item internal libraries

=begin html

</p>
<a href="./Config.html">PDLNA::Config</a>,
<a href="./Database.html">PDLNA::Database</a>.
</p>

=end html

=item external libraries

L<File::Basename>,
L<URI::Split>,
L<XML::Simple>.

=back

=cut

use File::Basename;
use URI::Split qw(uri_split uri_join);
use XML::Simple;

use PDLNA::Config;
use PDLNA::Database;

=head1 METHODS

=over

=item add_device()

=cut


sub add_device
{
	my $dbh = shift;
	my $params = shift;

	#
	# BEGIN OF IP
	#
	my $device_ip_id = _get_device_ip_id_by_device_ip($dbh, $$params{'ip'});
	if (defined($device_ip_id))
	{
		PDLNA::Database::update_db(
			$dbh,
			{
				'query' => 'UPDATE DEVICE_IP SET LAST_SEEN = ? WHERE ID = ?',
				'parameters' => [ time(), $device_ip_id, ],
			},
		);
	}
	else
	{
		PDLNA::Database::insert_db(
			$dbh,
			{
				'query' => 'INSERT INTO DEVICE_IP (IP, LAST_SEEN) VALUES (?,?)',
				'parameters' => [ $$params{'ip'}, time(), ],
			},
		);
		$device_ip_id = _get_device_ip_id_by_device_ip($dbh, $$params{'ip'});
	}
	#
	# END OF IP
	#

	# set the user agent string of defined
	if (defined($$params{'http_useragent'}))
	{
		PDLNA::Database::update_db(
			$dbh,
			{
				'query' => 'UPDATE DEVICE_IP SET USER_AGENT = ? WHERE ID = ?',
				'parameters' => [ $$params{'http_useragent'}, $device_ip_id, ],
			},
		);
	}

	#
	# BEGIN OF UDN
	#
	return 0 unless defined($$params{'udn'});
	return 0 unless defined($$params{'ssdp_banner'});
	return 0 unless defined($$params{'device_description_location'});

	my $device_udn_id = _get_device_udn_id_by_device_ip_id($dbh, $device_ip_id, $$params{'udn'});
	if (defined($device_udn_id))
	{
		# we got nothing to do here
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
					PDLNA::Log::log('ERROR: Unable to parse XML Device Description in PDLNA::Devices: '.$@, 0, 'discovery');
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
			PDLNA::Database::insert_db(
				$dbh,
				{
					'query' => 'INSERT INTO DEVICE_UDN (DEVICE_IP_REF, UDN, SSDP_BANNER, DESC_URL, RELA_URL, BASE_URL, TYPE, MODEL_NAME, FRIENDLY_NAME) VALUES (?,?,?,?,?,?,?,?,?)',
					'parameters' => [ $device_ip_id, $$params{'udn'}, $$params{'ssdp_banner'}, $$params{'device_description_location'}, $device_udn_base_url, $device_udn_rela_url, $device_udn_devicetype, $device_udn_modelname, $device_udn_friendlyname, ],
				},
			);
			$device_udn_id = _get_device_udn_id_by_device_ip_id($dbh, $device_ip_id, $$params{'udn'});

			# create the DEVICE_SERVICE entries
			foreach my $service (keys %services)
			{
				if (defined($services{$service}->{'serviceId'}) && defined($services{$service}->{'controlURL'}) && defined($services{$service}->{'eventSubURL'}) && defined($services{$service}->{'SCPDURL'}))
				{
					PDLNA::Database::insert_db(
						$dbh,
						{
							'query' => 'INSERT INTO DEVICE_SERVICE (DEVICE_UDN_REF, SERVICE_ID, TYPE, CONTROL_URL, EVENT_URL, SCPD_URL) VALUES (?,?,?,?,?,?)',
							'parameters' => [ $device_udn_id, $services{$service}->{'serviceId'}, $services{$service}->{'serviceType'}, $services{$service}->{'controlURL'}, $services{$service}->{'eventSubURL'}, $services{$service}->{'SCPDURL'}, ],
						},
					);
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

	my $device_nts_id = _get_device_nts_id_by_device_udn_id($dbh, $device_udn_id, $$params{'nt'});
	if (defined($device_nts_id))
	{
		PDLNA::Database::update_db(
			$dbh,
			{
				'query' => 'UPDATE DEVICE_NTS SET EXPIRE = ? WHERE ID = ? AND TYPE = ?',
				'parameters' => [ $$params{'nt_time_of_expire'}, $device_nts_id, $$params{'nt'}, ],
			},
		);
	}
	else
	{
		PDLNA::Database::insert_db(
			$dbh,
			{
				'query' => 'INSERT INTO DEVICE_NTS (DEVICE_UDN_REF, TYPE, EXPIRE) VALUES (?,?,?)',
				'parameters' => [ $device_udn_id, $$params{'nt'}, $$params{'nt_time_of_expire'}, ],
			},
		);
		$device_nts_id = _get_device_nts_id_by_device_udn_id($dbh, $device_udn_id, $$params{'nt'});
	}
	#
	# END OF NTS
	#
}

=item delete_expired_devices()

=cut

sub delete_expired_devices
{
	my $dbh = PDLNA::Database::connect();

	my $time = time();

	# delete expired DEVICE_NTS entries
	my @device_nts = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT ID, EXPIRE FROM DEVICE_NTS',
			'parameters' => [ ],
		},
		\@device_nts,
	);
	foreach my $nts (@device_nts)
	{
		if ($nts->{EXPIRE} < $time)
		{
			_delete_device_nts_by_id($dbh, $nts->{ID});
		}
	}

	# delete DEVICE_UDN entries with no NTS entries
	my @device_udn = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT ID FROM DEVICE_UDN',
			'parameters' => [ ],
		},
		\@device_udn,
	);
	foreach my $udn (@device_udn)
	{
		if (_get_device_nts_amount_by_device_udn_id($dbh, $udn->{ID}) == 0)
		{
			_delete_device_udn_by_id($dbh, $udn->{ID});
		}
	}

	PDLNA::Database::disconnect($dbh);
}

=item delete_device()

=cut

sub delete_device
{
	my $dbh = shift;
	my $params = shift;

	return 0 if !defined($$params{'ip'});
	return 0 if !defined($$params{'udn'});
	return 0 if !defined($$params{'nt'});

	my $device_ip_id = _get_device_ip_id_by_device_ip($dbh, $$params{'ip'});
	my $device_udn_id = _get_device_udn_id_by_device_ip_id($dbh, $device_ip_id, $$params{'udn'}) if defined($device_ip_id);
	my $device_nts_id = _get_device_nts_id_by_device_udn_id($dbh, $device_udn_id, $$params{'nt'}) if defined($device_udn_id);

	_delete_device_nts_by_id($dbh, $device_nts_id) if defined($device_nts_id);

	if (defined($device_udn_id))
	{
		my $device_nts_amount = _get_device_nts_amount_by_device_udn_id($dbh, $device_udn_id);
		_delete_device_udn_by_id($dbh, $device_udn_id) if $device_nts_amount == 0;
	}
}

=item get_modelname_by_devicetype()

=cut

sub get_modelname_by_devicetype
{
	my $dbh = shift;
	my $ip = shift;
	my $devicetype = shift;

	my @modelnames = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT ID, MODEL_NAME FROM DEVICE_UDN WHERE DEVICE_IP_REF IN (SELECT ID FROM DEVICE_IP WHERE IP = ?)',
			'parameters' => [ $ip, ],
		},
		\@modelnames,
	);
	foreach my $modelname (@modelnames)
	{
		my @device_udns = ();
		PDLNA::Database::select_db(
			$dbh,
			{
				'query' => 'SELECT DEVICE_UDN_REF FROM DEVICE_NTS WHERE TYPE = ?',
				'parameters' => [ $devicetype, ],
			},
			\@device_udns,
		);

		if (defined($device_udns[0]->{DEVICE_UDN_REF}) && $device_udns[0]->{DEVICE_UDN_REF} == $modelname->{ID})
		{
			return $modelname->{MODEL_NAME};
		}
	}
	return '';
}

#
# HELPER FUNCTIONS
#

=item delete_device_nts_by_id()

=cut

sub _delete_device_nts_by_id
{
	my $dbh = shift;
	my $device_nts_id = shift;

	PDLNA::Database::delete_db(
		$dbh,
		{
			'query' => 'DELETE FROM DEVICE_NTS WHERE ID = ?',
			'parameters' => [ $device_nts_id, ],
		},
	);
}

=item get_device_nts_id_by_device_udn_id()


=cut

sub _get_device_nts_id_by_device_udn_id
{
	my $dbh = shift;
	my $device_udn_id = shift;
	my $device_nts_type = shift;

	my @device_nts = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT ID FROM DEVICE_NTS WHERE DEVICE_UDN_REF = ? AND TYPE = ?',
			'parameters' => [ $device_udn_id, $device_nts_type, ],
		},
		\@device_nts,
	);

	return $device_nts[0]->{ID};
}

=item get_device_nts_amount_by_device_udn_id()

=cut

sub _get_device_nts_amount_by_device_udn_id
{
	my $dbh = shift;
	my $device_udn_id = shift;

	my @device_nts_amount = ();
	PDLNA::Database::select_db(
	$dbh,
		{
			'query' => 'SELECT COUNT(ID) AS AMOUNT FROM DEVICE_NTS WHERE DEVICE_UDN_REF = ?',
			'parameters' => [ $device_udn_id, ],
		},
		\@device_nts_amount,
	);

	return $device_nts_amount[0]->{AMOUNT};
}

=item delete_device_udn_by_id()

=cut

sub _delete_device_udn_by_id
{
	my $dbh = shift;
	my $device_udn_id = shift;

	PDLNA::Database::delete_db(
		$dbh,
		{
			'query' => 'DELETE FROM DEVICE_UDN WHERE ID = ?',
			'parameters' => [ $device_udn_id, ],
		},
	);

	# delete the DEVICE_SERVICE entries
	PDLNA::Database::delete_db(
		$dbh,
		{
			'query' => 'DELETE FROM DEVICE_SERVICE WHERE DEVICE_UDN_REF = ?',
			'parameters' => [ $device_udn_id, ],
		},
	);
}

=item get_device_udn_id_by_device_ip_id()

=cut

sub _get_device_udn_id_by_device_ip_id
{
	my $dbh = shift;
	my $device_ip_id = shift;
	my $device_udn = shift;

	my @device_udn = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT ID FROM DEVICE_UDN WHERE DEVICE_IP_REF = ? AND UDN = ?',
			'parameters' => [ $device_ip_id, $device_udn, ],
		},
		\@device_udn,
	);

	return $device_udn[0]->{ID};
}

=item get_device_udn_amount_by_device_ip_id()

=cut

sub _get_device_udn_amount_by_device_ip_id
{
	my $dbh = shift;
	my $device_ip_id = shift;

	my @device_udn_amount = ();
	PDLNA::Database::select_db(
	$dbh,
		{
			'query' => 'SELECT COUNT(ID) AS AMOUNT FROM DEVICE_UDN WHERE DEVICE_IP_REF = ?',
			'parameters' => [ $device_ip_id, ],
		},
		\@device_udn_amount,
	);

	return $device_udn_amount[0]->{AMOUNT};
}

=item get_device_ip_id_by_device_ip()

=cut

sub _get_device_ip_id_by_device_ip
{
	my $dbh = shift;
	my $ip = shift;

	my @devices = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT ID FROM DEVICE_IP WHERE IP = ?',
			'parameters' => [ $ip, ],
		},
		\@devices,
	);

	return $devices[0]->{ID};
}

=item delete_device_ip_by_id()

=cut

sub _delete_device_ip_by_id
{
	my $dbh = shift;
	my $device_ip_id = shift;

	PDLNA::Database::delete_db(
		$dbh,
		{
			'query' => 'DELETE FROM DEVICE_IP WHERE ID = ?',
			'parameters' => [ $device_ip_id, ],
		},
	);
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
