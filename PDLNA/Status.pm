package PDLNA::Status;

=head1 NAME

package PDLNA::Status - helper module for updates.

=head1 DESCRIPTION

This module checks for pDLNA version updates or device service updates.

=cut


use strict;
use warnings;

=head1 LIBRARY FUNCTIONS

=over 12

=item internal libraries

=begin html

</p>
<a href="./Config.html">PDLNA::Config</a>,
<a href="./Database.html">PDLNA::Database</a>,
<a href="./Log.html">PDLNA::Log</a>,
<a href="./SOAPMessages.html">PDLNA::SOAPMessages</a>.
</p>

=end html

=item external libraries

L<LWP::UserAgent>,
L<XML::Simple>.

=back

=cut

use LWP::UserAgent;
use XML::Simple;

use PDLNA::Config;
use PDLNA::Database;
use PDLNA::Log;
use PDLNA::SOAPMessages;


=head1 METHODS

=over

=item check_update_periodic()

=cut


sub check_update_periodic
{
	PDLNA::Log::log('Starting thread for checking periodically for a new version of pDLNA.', 1, 'default');
	while(1)
	{
		check_update();
		sleep 86400;
	}
}

=item do_http_request()

=cut

sub do_http_request
{
	my $ua = LWP::UserAgent->new();
	$ua->agent($CONFIG{'PROGRAM_NAME'}."/".PDLNA::Config::print_version());
	my $xml_obj = XML::Simple->new();
	my $xml = {
		'deviceinformation' =>
		{
			'udn' => $CONFIG{'UUID'},
		},
		'statusinformation' =>
		{
			'version' => $CONFIG{'PROGRAM_VERSION'},
			'beta' => $CONFIG{'PROGRAM_BETA'},
		},
	};

	my $response = $ua->post(
		'http://www.pdlna.com/cgi-bin/status.pl',
		Content_Type => 'text/xml',
		Content => $xml_obj->XMLout(
			$xml,
			XMLDecl => '<?xml version="1.0" encoding="UTF-8"?>',
			NoAttr => 1,
		),
	);
	return $response;
}

=item check_update()

=cut

sub check_update
{
	my $response = do_http_request();

	if ($response->is_success)
	{
		my $xml_obj = XML::Simple->new();
		my $xml = $xml_obj->XMLin($response->decoded_content());
		PDLNA::Log::log('Check4Updates was successful: '.$xml->{'response'}->{'result'}.' ('.$xml->{'response'}->{'resultID'}.').', 1, 'default');
		if ($xml->{'response'}->{'resultID'} == 4)
		{
			PDLNA::Log::log($CONFIG{'PROGRAM_NAME'}.' is available in version '.$xml->{'response'}->{'NewVersion'}.'. Please update your installation.', 1, 'default');

			if ($CONFIG{'CHECK_UPDATES_NOTIFICATION'})
			{
				PDLNA::Log::log('Sending notification to currently connected urn:samsung.com:serviceId:MessageBoxService services.', 1, 'default');

				my $dbh = PDLNA::Database::connect();
				my @device_services = ();
				PDLNA::Database::select_db(
					$dbh,
					{
						'query' => 'SELECT TYPE, CONTROL_URL FROM DEVICE_SERVICE WHERE SERVICE_ID = ?',
						'parameters' => [ 'urn:samsung.com:serviceId:MessageBoxService' ],
					},
					\@device_services,
				);
				PDLNA::Database::disconnect($dbh);

				foreach my $service (@device_services)
				{
					PDLNA::Log::log('Sending sms to '.$service->{CONTROL_URL}.'.', 1, 'default');
					my $message = 'A new version of '.$CONFIG{'PROGRAM_NAME'}.' is available: '.$xml->{'response'}->{'NewVersion'};
					PDLNA::SOAPMessages::send_sms($service->{TYPE}, $service->{CONTROL_URL}, $message);
				}
			}
		}
	}
	else
	{
		PDLNA::Log::log('Check4Updates was NOT successful: HTTP Status Code '.$response->status_line().'.', 1, 'default');
	}
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
