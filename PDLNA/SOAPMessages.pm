package PDLNA::SOAPMessages;
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2014 Stefan Heumader <stefan@heumader.at>
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

use PDLNA::Config;
use PDLNA::SOAPClient;

sub send_sms
{
	my $service_type = shift;
	my $service_url = shift;
	my $message = shift;

	my $fullmessage = undef;
	$fullmessage .= '<Category>SMS</Category>';
	$fullmessage .= '<DisplayType>Maximum</DisplayType>';
	my $now = time();
	$fullmessage .= '<ReceiveTime><Date>'.time2str('%y-%m-%d', $now).'</Date><Time>'.time2str('%H:%M:%S', $now).'</Time></ReceiveTime>';
	$fullmessage .= '<Receiver><Number>1111</Number><Name>You</Name></Receiver>';
	$fullmessage .= '<Sender><Number>0000</Number><Name>'.$CONFIG{'PROGRAM_NAME'}.'</Name></Sender>';
	$fullmessage .= '<Body>'.$message.'</Body>';

	my $client = _soapclient($service_type, $service_url);
	$client->method('AddMessage');

	my @arguments = ();
	push (@arguments, [ 'MessageType', 'text/xml', ]);
	push (@arguments, [ 'MessageID', 1, ]);
	push (@arguments, [ 'Message', $fullmessage, ]);
	foreach my $argument (@arguments)
	{
		$client->add_argument(
			{
				'type' => 'string',
				'name' => $argument->[0],
				'value' => $argument->[1],
			}
		);
	}
	$client->send();
}

#
# HELPER FUNCTIONS
#

sub _soapclient
{
	my $service_type = shift;
	my $service_url = shift;

	my $client = PDLNA::SOAPClient->new(
		{
			'proxy' => $service_url,
			'uri' => $service_type,
		}
	);
	return $client;
}

1;
