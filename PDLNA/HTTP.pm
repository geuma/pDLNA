package PDLNA::HTTP;
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

use HTTP::Server::Simple::CGI;
use base qw(HTTP::Server::Simple::CGI);

use Data::Dumper;
use XML::Simple;

use PDLNA::Config;
use PDLNA::Log;

our %dispatch = (
	'/ServerDesc.xml' => \&server_description,
);

sub handle_request
{
	my $self = shift;
	my $cgi  = shift;

#	print STDERR Dumper $cgi;

	my $path = $cgi->path_info();
	my $func_handler = $dispatch{$path};

	my $method = $ENV{'REQUEST_METHOD'};
	my $client = $ENV{'REMOTE_ADDR'};

	PDLNA::Log::log("HTTP Client ($client): $method $path.", 1);

	my $post_xml = undef;
	if (lc($method) eq 'post')
	{
		my $postdata = $cgi->param('POSTDATA') if lc($method) eq 'post';
		print STDERR $postdata;

		my $xmlsimple = XML::Simple->new();
		$post_xml = $xmlsimple->XMLin($postdata);
	}

	if (ref($func_handler) eq "CODE")
	{
		print "HTTP/1.0 200 OK\r\n";
		$func_handler->($cgi, $post_xml);
	}
	else
	{
		print "HTTP/1.0 404 Not found\r\n";
	}
}

sub server_description
{
	my $cgi = shift;

	my $xml_response = XML::Simple->new();
	my $xml_serverdesc = {
		'xmlns' => 'urn:schemas-upnp-org:device-1-0',
		'specVersion' => {
			'minor' => '5',
			'major' => '1'
		},
		'device' => {
			'friendlyName' => $CONFIG{'FRIENDLY_NAME'},
			'modelName' => $CONFIG{'PROGRAM_NAME'},
			'modelDescription' => $CONFIG{'PROGRAM_DESC'},
			'dlna:X_DLNADOC' => 'DMS-1.50',
			'deviceType' => 'urn:schemas-upnp-org:device:MediaServer:1',
			'serialNumber' => $CONFIG{'PROGRAM_SERIAL'},
			'sec:ProductCap' => 'smi,DCM10,getMediaInfo.sec,getCaptionInfo.sec',
			'UDN' => $CONFIG{'UUID'},
			'manufacturerURL' => $CONFIG{'PROGRAM_WEBSITE'},
			'manufacturer' => $CONFIG{'PROGRAM_AUTHOR'},
			'sec:X_ProductCap' => 'smi,DCM10,getMediaInfo.sec,getCaptionInfo.sec',
			'modelURL' => $CONFIG{'PROGRAM_WEBSITE'},
			'serviceList' => {
				'service' => [
					{
						'serviceType' => 'urn:schemas-upnp-org:service:ContentDirectory:1',
						'controlURL' => '/upnp/control/ContentDirectory1',
						'eventSubURL' => '/upnp/event/ContentDirectory1',
						'SCPDURL' => 'ContentDirectory1.xml',
						'serviceId' => 'urn:upnp-org:serviceId:ContentDirectory'
					},
					{
						'serviceType' => 'urn:schemas-upnp-org:service:ConnectionManager:1',
						'controlURL' => '/upnp/control/ConnectionManager1',
						'eventSubURL' => '/upnp/event/ConnectionManager1',
						'SCPDURL' => 'ConnectionManager1.xml',
						'serviceId' => 'urn:upnp-org:serviceId:ConnectionManager'
						},
				],
			},
			'modelNumber' => '1.0',
		},
		'xmlns:dlna' => 'urn:schemas-dlna-org:device-1-0',
		'xmlns:sec' => 'http://www.sec.co.kr/dlna'
	};
	my $response = $xml_response->XMLout(
		$xml_serverdesc,
		RootName => 'root',
		XMLDecl => '<?xml version="1.0" encoding="UTF-8"?>',
		ContentKey => '-content',
		ValueAttr => [ 'value' ],
		NoSort => 1,
		NoAttr => 1,
	);

	print $cgi->header('text/xml; charset="utf-8"');
	print $response;
}

1;
