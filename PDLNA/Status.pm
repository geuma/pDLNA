package PDLNA::Status;
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

use LWP::UserAgent;
use XML::Simple;

use PDLNA::Config;
use PDLNA::Log;

sub check_update_periodic
{
	PDLNA::Log::log('Starting thread for checking periodically for a new version of pDLNA.', 1, 'update');
	while(1)
	{
		check_update();
		sleep 86400;
	}
}

sub check_update
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

	if ($response->is_success)
	{
		$xml = $xml_obj->XMLin($response->decoded_content());
		PDLNA::Log::log('Check4Updates was successful: '.$xml->{'response'}->{'result'}.' ('.$xml->{'response'}->{'resultID'}.').', 1, 'update');
		if ($xml->{'response'}->{'resultID'} == 4)
		{
			PDLNA::Log::log('pDLNA is available in version '.$xml->{'response'}->{'NewVersion'}.'. Please update your installation.', 1, 'update');
		}
	}
	else
	{
		PDLNA::Log::log('Check4Updates was NOT successful: HTTP Status Code '.$response->status_line().'.', 1, 'update');
	}
}

1;
