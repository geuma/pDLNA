package PDLNA::HTTPServer;
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

use Fcntl;
use Data::Dumper;
use Date::Format;
use GD;
use IO::Select;
use Net::Netmask;
use Socket;
use threads;
use threads::shared;
use XML::Simple;
require bytes;
no bytes;

use PDLNA::Config;
use PDLNA::ContentLibrary;
use PDLNA::Database;
use PDLNA::HTTPXML;
use PDLNA::WebUI;
use PDLNA::Log;

sub start_webserver
{
	my $device_list = shift;

	PDLNA::Log::log('Starting HTTP Server listening on '.$CONFIG{'LOCAL_IPADDR'}.':'.$CONFIG{'HTTP_PORT'}.'.', 0, 'default');

	# got inspired by: http://www.adp-gmbh.ch/perl/webserver/
	local *S;
	socket(S, PF_INET, SOCK_STREAM, getprotobyname('tcp')) || die "Can't open HTTPServer socket: $!\n";
	setsockopt(S, SOL_SOCKET, SO_REUSEADDR, 1);
	my $server_ip = inet_aton($CONFIG{'LOCAL_IPADDR'});
	bind(S, sockaddr_in($CONFIG{'HTTP_PORT'}, $server_ip));
	listen(S, 5) || die "Can't listen to HTTPServer socket: $!\n";

	my $ss = IO::Select->new();
	$ss->add(*S);

	while(1)
	{
		my @connections_pending = $ss->can_read(60);
		foreach my $connection (@connections_pending)
		{
			my $FH;
			my $remote = accept($FH, $connection);
			my ($peer_src_port, $peer_addr) = sockaddr_in($remote);
			my $peer_ip_addr = inet_ntoa($peer_addr);

			my $thread = threads->create(\&handle_connection, $FH, $peer_ip_addr, $peer_src_port, $device_list);
			$thread->detach();
		}
	}
}

sub handle_connection
{
	my $FH = shift;
	my $peer_ip_addr = shift;
	my $peer_src_port = shift;
	my $device_list = shift;

	PDLNA::Log::log('Handling HTTP connection for '.$peer_ip_addr.':'.$peer_src_port.'.', 3, 'httpgeneric');

	binmode($FH);

	my %CGI = ();
	my %ENV = ();

	my $post_xml = undef;
	my $request_line = <$FH>;
	my $first_line = '';
	while ($request_line ne "\r\n")
	{
		next unless $request_line;
		$request_line =~ s/\r\n//g;
		chomp($request_line);

		if (!$first_line)
		{
			$first_line = $request_line;

			my @parts = split(' ', $first_line);
			close $FH if @parts != 3;

			$ENV{'METHOD'} = $parts[0];
			$ENV{'OBJECT'} = $parts[1];
			$ENV{'HTTP_VERSION'} = $parts[2];
		}
		else
		{
			my ($name, $value) = split(':', $request_line, 2);
			$name = uc($name);
			$value =~ s/^\s//g;
			$CGI{$name} = $value;
		}
		$request_line = <$FH>;
	}

	my $debug_string = '';
	foreach my $key (keys %CGI)
	{
		$debug_string .= "\n\t".$key.' -> '.$CGI{$key};
	}
	PDLNA::Log::log($ENV{'METHOD'}.' '.$ENV{'OBJECT'}.' from '.$peer_ip_addr.':'.$peer_src_port.':'.$debug_string, 3, 'httpgeneric');

	# reading POSTDATA
	if ($ENV{'METHOD'} eq "POST")
	{
		if (defined($CGI{'CONTENT-LENGTH'}) && length($CGI{'CONTENT-LENGTH'}) > 0)
		{
			PDLNA::Log::log('Reading '.$CGI{'CONTENT-LENGTH'}.' bytes from request for POSTDATA.', 2, 'httpgeneric');
			read($FH, $CGI{'POSTDATA'}, $CGI{'CONTENT-LENGTH'});
		}
		else
		{
			PDLNA::Log::log('Looking for \r\n in request for POSTDATA.', 2, 'httpgeneric');
			$CGI{'POSTDATA'} = <$FH>;
		}
		PDLNA::Log::log('POSTDATA: '.$CGI{'POSTDATA'}, 3, 'httpgeneric');
		my $xmlsimple = XML::Simple->new();
		eval { $post_xml = $xmlsimple->XMLin($CGI{'POSTDATA'}) };
		if ($@)
		{
			PDLNA::Log::log('Error converting POSTDATA with XML::Simple for '.$peer_ip_addr.':'.$peer_src_port.': '.$@, 3, 'httpdir');
		}
		else
		{
			PDLNA::Log::log('Finished converting POSTDATA with XML::Simple for '.$peer_ip_addr.':'.$peer_src_port.'.', 3, 'httpdir');
		}
	}

	PDLNA::Log::log('Handling HTTP connection for '.$peer_ip_addr.':'.$peer_src_port.'.', 3, 'httpgeneric');
	# Check if the peer is one of our allowed clients
	my $client_allowed = 0;
	foreach my $block (@{$CONFIG{'ALLOWED_CLIENTS'}})
	{
		$client_allowed++ if $block->match($peer_ip_addr);
	}

	# handling different HTTP requests
	if ($client_allowed)
	{
		# adding device and/or request to PDLNA::DeviceList
		$$device_list->add({
			'ip' => $peer_ip_addr,
			'http_useragent' => $CGI{'USER-AGENT'},
		});
		my %ssdp_devices = $$device_list->devices();
		my $model_name = $ssdp_devices{$peer_ip_addr}->model_name_by_device_type('urn:schemas-upnp-org:device:MediaRenderer:1');

		PDLNA::Log::log('ModelName for '.$peer_ip_addr.' is '.$model_name.'.', 3, 'httpgeneric');
		PDLNA::Log::log($$device_list->print_object(), 3, 'httpgeneric');

		PDLNA::Log::log('Received HTTP Request from allowed client IP '.$peer_ip_addr.'.', 2, 'httpgeneric');

		if ($ENV{'OBJECT'} eq '/ServerDesc.xml') # delivering server description XML
		{
			PDLNA::Log::log('New HTTP Connection: Delivering server description XML to: '.$peer_ip_addr.':'.$peer_src_port.'.', 1, 'discovery');

			my $xml = PDLNA::HTTPXML::get_serverdescription($CGI{'USER-AGENT'});
			my @additional_header = (
				'Content-Type: text/xml; charset=utf8',
				'Content-Length: '.length($xml),
			);
			my $response = http_header({
				'statuscode' => 200,
				'additional_header' => \@additional_header,
			});
			$response .= $xml;

			print $FH $response;
		}
		elsif ($ENV{'OBJECT'} eq '/ContentDirectory1.xml') # delivering ContentDirectory XML
		{
			PDLNA::Log::log('New HTTP Connection: Delivering ContentDirectory description XML to: '.$peer_ip_addr.':'.$peer_src_port.'.', 1, 'discovery');
			my $xml = PDLNA::HTTPXML::get_contentdirectory();
			my @additional_header = (
				'Content-Type: text/xml; charset=utf8',
				'Content-Length: '.length($xml),
			);
			my $response = http_header({
				'statuscode' => 200,
				'additional_header' => \@additional_header,
			});
			$response .= $xml;

			print $FH $response;
		}
		elsif ($ENV{'OBJECT'} eq '/ConnectionManager1.xml') # delivering ConnectionManager XML
		{
			PDLNA::Log::log('New HTTP Connection: Delivering ConnectionManager description XML to: '.$peer_ip_addr.':'.$peer_src_port.'.', 1, 'discovery');
			my $xml = PDLNA::HTTPXML::get_connectionmanager();
			my @additional_header = (
				'Content-Type: text/xml; charset=utf8',
				'Content-Length: '.length($xml),
			);
			my $response = http_header({
				'statuscode' => 200,
				'additional_header' => \@additional_header,
			});
			$response .= $xml;

			print $FH $response;
		}
		elsif ($ENV{'OBJECT'} eq '/upnp/event/ContentDirectory1' || $ENV{'OBJECT'} eq '/upnp/event/ConnectionManager1')
		{
			my $response_content = '';
			$response_content = '<html><body><h1>200 OK</h1></body></html>' if $ENV{'METHOD'} eq 'UNSUBSCRIBE';

			PDLNA::Log::log('New HTTP Connection: '.$peer_ip_addr.':'.$peer_src_port.' is '.$ENV{'METHOD'}.' to '.$ENV{'OBJECT'}, 1, 'discovery');
			my @additional_header = (
				'Content-Length: '.length($response_content),
				'SID: '.$CONFIG{'UUID'},
				'Timeout: Second-'.$CONFIG{'CACHE_CONTROL'},
			);
			my $response = http_header({
				'statuscode' => 200,
				'additional_header' => \@additional_header,
			});
			$response .= $response_content;
			print $FH $response;
		}
		elsif ($ENV{'OBJECT'} eq '/upnp/control/ContentDirectory1') # handling Directory Listings
		{
			PDLNA::Log::log('New HTTP Connection: '.$peer_ip_addr.':'.$peer_src_port.' -> SoapAction: '.$ENV{'METHOD'}.' '.$CGI{'SOAPACTION'}.'.', 1, 'httpdir');
			print $FH ctrl_content_directory_1($post_xml, $CGI{'SOAPACTION'}, $ssdp_devices{$peer_ip_addr});
		}
#		elsif ($ENV{'OBJECT'} eq '/upnp/control/ConnectionManager1')
#		{
#			PDLNA::Log::log('HTTP Connection: '.$peer_ip_addr.':'.$peer_src_port.' -> SoapAction: '.$ENV{'METHOD'}.' '.$CGI{'SOAPACTION'}.'.', 1, 'httpdir');
#		}
		elsif ($ENV{'OBJECT'} =~ /^\/media\/(.*)$/) # handling media streaming
		{
			PDLNA::Log::log('New HTTP Connection: '.$peer_ip_addr.':'.$peer_src_port.' -> Request: '.$ENV{'METHOD'}.' '.$ENV{'OBJECT'}.'.', 1, 'httpstream');
			stream_media($1, $ENV{'METHOD'}, \%CGI, $FH, $model_name);
		}
		elsif ($ENV{'OBJECT'} =~ /^\/subtitle\/(.*)$/) # handling delivering of subtitles
		{
			PDLNA::Log::log('New HTTP Connection: '.$peer_ip_addr.':'.$peer_src_port.' -> Request: '.$ENV{'METHOD'}.' '.$ENV{'OBJECT'}.'.', 1, 'httpstream');
			deliver_subtitle($1, $ENV{'METHOD'}, \%CGI, $FH, $model_name);
		}
		elsif ($ENV{'OBJECT'} =~ /^\/preview\/(.*)$/) # handling media previews
		{
			PDLNA::Log::log('New HTTP Connection: '.$peer_ip_addr.':'.$peer_src_port.' -> Request: '.$ENV{'METHOD'}.' '.$ENV{'OBJECT'}.'.', 1, 'httpstream');
			print $FH preview_media($1);
		}
		elsif ($ENV{'OBJECT'} =~ /^\/icons\/(.*)$/)
		{
			PDLNA::Log::log('New HTTP Connection: '.$peer_ip_addr.':'.$peer_src_port.' -> Request: '.$ENV{'METHOD'}.' '.$ENV{'OBJECT'}.'.', 1, 'httpstream');
			print $FH logo($1);
		}
		elsif ($ENV{'OBJECT'} =~ /^\/webui\/(.*)$/) # this is just to be something different (not DLNA stuff)
		{
			print $FH PDLNA::WebUI::show($device_list, $1);
		}
		else
		{
			PDLNA::Log::log('Request not supported yet: '.$peer_ip_addr.':'.$peer_src_port.' -> Request: '.$ENV{'METHOD'}.' '.$ENV{'OBJECT'}.'.', 2, 'httpstream');
			print $FH http_header({
				'statuscode' => 501,
				'content_type' => 'text/plain',
			});
		}
	}
	else
	{
		PDLNA::Log::log('Received HTTP Request from NOT allowed client IP '.$peer_ip_addr.'.', 2, 'discovery');
		print $FH http_header({
			'statuscode' => 403,
			'content_type' => 'text/plain',
		});
	}

	close($FH);
}

sub http_header
{
	my $params = shift;

	my %HTTP_CODES = (
		200 => 'OK',
		206 => 'Partial Content',
		400 => 'Bad request',
		403 => 'Forbidden',
		404 => 'Not found',
		406 => 'Not acceptable',
		501 => 'Not implemented',
	);

	my @response = ();
	push(@response, "HTTP/1.1 ".$$params{'statuscode'}." ".$HTTP_CODES{$$params{'statuscode'}}); # TODO (maybe) differ between http protocol versions
	push(@response, "Server: ".$CONFIG{'OS'}."/".$CONFIG{'OS_VERSION'}.", UPnP/1.0, ".$CONFIG{'PROGRAM_NAME'}."/".PDLNA::Config::print_version());
	push(@response, "Content-Type: ".$params->{'content_type'}) if $params->{'content_type'};
	push(@response, "Content-Length: ".$params->{'content_length'}) if $params->{'content_length'};
	push(@response, "Date: ".PDLNA::Utils::http_date());
#	push(@response, "Last-Modified: ".PDLNA::Utils::http_date());
	if (defined($$params{'additional_header'}))
	{
		foreach my $header (@{$$params{'additional_header'}})
		{
			push(@response, $header);
		}
	}
	push(@response, 'Cache-Control: no-cache');
	push(@response, 'Connection: close');

	PDLNA::Log::log("HTTP Response Header:\n\t".join("\n\t",@response), 3, $$params{'log'}) if defined($$params{'log'});
	return join("\r\n", @response)."\r\n\r\n";
}

sub ctrl_content_directory_1
{
	my $xml = shift;
	my $action = shift;
	my $device = shift;

	my $dbh = PDLNA::Database::connect();

	PDLNA::Log::log("Function PDLNA::HTTPServer::ctrl_content_directory_1 called", 3, 'httpdir');

	my $response = undef;

	if ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#Browse"')
	{
		my $response_xml .= PDLNA::HTTPXML::get_browseresponse_header();

		my ($object_id, $starting_index, $requested_count, $filter, $browse_flag) = 0;
		# determine which 'Browse' element was used
		if (defined($xml->{'s:Body'}->{'ns0:Browse'}->{'ObjectID'})) # coherence seems to use this one
		{
			$object_id = $xml->{'s:Body'}->{'ns0:Browse'}->{'ObjectID'};
			$starting_index = $xml->{'s:Body'}->{'ns0:Browse'}->{'StartingIndex'};
			$requested_count = $xml->{'s:Body'}->{'ns0:Browse'}->{'RequestedCount'};
			$browse_flag = $xml->{'s:Body'}->{'ns0:Browse'}->{'BrowseFlag'};
			$filter = $xml->{'s:Body'}->{'ns0:Browse'}->{'Filter'};
		}
		elsif (defined($xml->{'s:Body'}->{'u:Browse'}->{'ObjectID'}))
		{
			$object_id = $xml->{'s:Body'}->{'u:Browse'}->{'ObjectID'};
			$starting_index = $xml->{'s:Body'}->{'u:Browse'}->{'StartingIndex'};
			$requested_count = $xml->{'s:Body'}->{'u:Browse'}->{'RequestedCount'};
			$browse_flag = $xml->{'s:Body'}->{'u:Browse'}->{'BrowseFlag'};
			$filter = $xml->{'s:Body'}->{'u:Browse'}->{'Filter'};
		}
		elsif (defined($xml->{'SOAP-ENV:Body'}->{'m:Browse'}->{'ObjectID'}->{'content'})) # and windows media player this one
		{
			$object_id = $xml->{'SOAP-ENV:Body'}->{'m:Browse'}->{'ObjectID'}->{'content'};
			$starting_index = $xml->{'SOAP-ENV:Body'}->{'m:Browse'}->{'StartingIndex'}->{'content'};
			$requested_count = $xml->{'SOAP-ENV:Body'}->{'m:Browse'}->{'RequestedCount'}->{'content'};
			$browse_flag = $xml->{'SOAP-ENV:Body'}->{'m:Browse'}->{'BrowseFlag'}->{'content'};
			$filter = $xml->{'SOAP-ENV:Body'}->{'m:Browse'}->{'Filter'}->{'content'};
		}
		else
		{
			PDLNA::Log::log('Unable to find (a known) ObjectID in XML (POSTDATA).', 1, 'httpdir');
			return http_header({
				'statuscode' => 501,
				'content_type' => 'text/plain',
			});
		}

		my @browsefilters = split(',', $filter) if length($filter) > 0;
		if ($browse_flag eq 'BrowseMetadata')
		{
			if (grep(/^\@parentID$/, @browsefilters))
			{
				@browsefilters = ('@id', '@parentID', '@childCount', '@restricted', 'dc:title', 'upnp:class');

				# set object_id to parentid
				my @directory_parent = ();
				PDLNA::Database::select_db(
					$dbh,
					{
						'query' => 'SELECT ID FROM DIRECTORIES WHERE PATH IN ( SELECT DIRNAME FROM DIRECTORIES WHERE ID = ? );',
						'parameters' => [ $object_id, ],
					},
					\@directory_parent,
				);
				$directory_parent[0]->{ID} = 0 if !defined($directory_parent[0]->{ID});
				$object_id = $directory_parent[0]->{ID};
			}
		}
		elsif ($browse_flag eq 'BrowseDirectChildren')
		{
			if ($browsefilters[0] eq '*')
			{
				@browsefilters = ('@id', '@parentID', '@childCount', '@restricted', 'dc:title', 'upnp:class', 'res@bitrate', 'res@duration');
			}
		}

		PDLNA::Log::log('Starting to handle Directory Listing request for: '.$object_id.'.', 3, 'httpdir');
		PDLNA::Log::log('StartingIndex: '.$starting_index.'.', 3, 'httpdir');
		PDLNA::Log::log('RequestedCount: '.$requested_count.'.', 3, 'httpdir');
		PDLNA::Log::log('BrowseFlag: '.$browse_flag.'.', 3, 'httpdir');
		PDLNA::Log::log('Filter: '.join(', ', @browsefilters).'.', 3, 'httpdir');

		$requested_count = 10 if $requested_count == 0; # if client asks for 0 items, we should return the 'default' amount

		if ($object_id =~ /^\d+$/)
		{
			PDLNA::Log::log('Adding DirectoryListing request for: '.$object_id.' to history.', 3, 'httpdir');
			$device->add_dirlist_request($object_id);

			PDLNA::Log::log('Received numeric Directory Listing request for: '.$object_id.'.', 2, 'httpdir');
			if ($browse_flag eq 'BrowseDirectChildren' || $browse_flag eq 'BrowseMetadata')
			{
				#
				# get the subdirectories for the object_id requested
				#
				my @dire_elements = ();
				PDLNA::ContentLibrary::get_subdirectories_by_id($dbh, $object_id, $starting_index, $requested_count, \@dire_elements);

				#
				# get the full amount of subdirectories for the object_id requested
				#
				my $amount_directories = PDLNA::ContentLibrary::get_amount_subdirectories_by_id($dbh, $object_id);

				#
				# get the full amount of files in the directory requested
				#
				my $amount_files = PDLNA::ContentLibrary::get_amount_subfiles_by_id($dbh, $object_id);

				$starting_index -= $amount_directories;

				#
				# get the files for the directory requested
				#
				my @file_elements = ();
				PDLNA::ContentLibrary::get_subfiles_by_id($dbh, $object_id, $starting_index, $requested_count, \@file_elements);

				#
				# build the http response
				#
				foreach my $directory (@dire_elements)
				{
					$response_xml .= PDLNA::HTTPXML::get_browseresponse_directory(
						$directory->{ID},
						$directory->{NAME},
						\@browsefilters,
						$dbh,
					);
				}

				foreach my $file (@file_elements)
				{
					$response_xml .= PDLNA::HTTPXML::get_browseresponse_item($file->{ID}, \@browsefilters, $dbh);
				}

				my $elements_in_listing = scalar(@dire_elements) + scalar(@file_elements);
				my $elements_in_directory = $amount_directories + $amount_files;

				$response_xml .= PDLNA::HTTPXML::get_browseresponse_footer($elements_in_listing, $elements_in_directory);
			}
			else
			{
				PDLNA::Log::log('BrowseFlag: '.$browse_flag.' is NOT supported yet.', 2, 'httpdir');
				return http_header({
					'statuscode' => 501,
					'content_type' => 'text/plain',
				});
			}
		}

		$response = http_header({
			'statuscode' => 200,
			'log' => 'httpdir',
			'content_length' => length($response_xml),
			'content_type' => 'text/xml; charset=utf8',
		});
		$response .= $response_xml;
	}
	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#GetSearchCapabilities"')
	{
		$response = http_header({
			'statuscode' => 200,
		});
		$response .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
		$response .= '<s:Body>';
		$response .= '<u:GetSearchCapabilitiesResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$response .= '<SearchCaps></SearchCaps>';
		$response .= '</u:GetSearchCapabilitiesResponse>';
		$response .= '</s:Body>';
		$response .= '</s:Envelope>';
	}
	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#GetSortCapabilities"')
	{
		$response = http_header({
			'statuscode' => 200,
		});
		$response .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
		$response .= '<s:Body>';
		$response .= '<u:GetSortCapabilitiesResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$response .= '<SortCaps></SortCaps>';
		$response .= '</u:GetSortCapabilitiesResponse>';
		$response .= '</s:Body>';
		$response .= '</s:Envelope>';
	}
	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#GetSystemUpdateID"')
	{
		$response = http_header({
			'statuscode' => 200,
		});
		$response .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
		$response .= '<s:Body>';
		$response .= '<u:GetSystemUpdateIDResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$response .= '<Id>0</Id>';
		$response .= '</u:GetSystemUpdateIDResponse>';
		$response .= '</s:Body>';
		$response .= '</s:Envelope>';
	}
	# OLD CODE
#	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#X_GetObjectIDfromIndex"')
#	{
#		my $media_type = '';
#		my $sort_type = '';
#		if ($xml->{'s:Body'}->{'u:X_GetObjectIDfromIndex'}->{'CategoryType'} == 14)
#		{
#			$media_type = 'I';
#			$sort_type = 'F';
#		}
#		elsif ($xml->{'s:Body'}->{'u:X_GetObjectIDfromIndex'}->{'CategoryType'} == 22)
#		{
#			$media_type = 'A';
#			$sort_type = 'F';
#		}
#		elsif ($xml->{'s:Body'}->{'u:X_GetObjectIDfromIndex'}->{'CategoryType'} == 32)
#		{
#			$media_type = 'V';
#			$sort_type = 'F';
#		}
#		PDLNA::Log::log('Getting object for '.$media_type.'_'.$sort_type.'.', 2, 'httpdir');
#
#		my $index = $xml->{'s:Body'}->{'u:X_GetObjectIDfromIndex'}->{'Index'};
#
#		my $content_type_obj = $content->get_content_type($media_type, $sort_type);
#		my $i = 0;
#		my @groups = @{$content_type_obj->content_groups()};
#		while ($index >= $groups[$i]->content_items_amount())
#		{
#			$index -= $groups[$i]->content_items_amount();
#			$i++;
#		}
#		my $content_item_obj = $groups[$i]->content_items()->[$index];
#
#		$response = http_header({
#			'statuscode' => 200,
#		});
#
#		$response .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
#		$response .= '<s:Body>';
#		$response .= '<u:X_GetObjectIDfromIndexResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
#		$response .= '<ObjectID>'.$media_type.'_'.$sort_type.'_'.$groups[$i]->beautiful_id().'_'.$content_item_obj->beautiful_id().'</ObjectID>';
#		$response .= '</u:X_GetObjectIDfromIndexResponse>';
#		$response .= '</s:Body>';
#		$response .= '</s:Envelope>';
#	}
	# TODO X_GetIndexfromRID (i think it might be the question, to which item the tv should jump ... but currently i don't understand the question (<RID></RID>)
	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#X_GetIndexfromRID"')
	{
		$response = http_header({
			'statuscode' => 200,
		});

		$response .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
		$response .= '<s:Body>';
		$response .= '<u:X_GetIndexfromRIDResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$response .= '<Index>0</Index>'; # we are setting it to 0 - so take the first item in the list to be active
		$response .= '</u:X_GetIndexfromRIDResponse>';
		$response .= '</s:Body>';
		$response .= '</s:Envelope>';
	}
	else
	{
		PDLNA::Log::log('Action: '.$action.' is NOT supported yet.', 2, 'httpdir');
		return http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
		});
	}

	return $response;
}

#
# this functions handels delivering the subtitle files
#
sub deliver_subtitle
{
	my $content_id = shift;
	my $method = shift;
	my $CGI = shift;
	my $FH = shift;
	my $model_name = shift;

	if ($content_id =~ /^(\d+)\.(\w+)$/)
	{
		my $id = $1;
		my $type = $2;

		PDLNA::Log::log('Delivering subtitle: '.$id.'.'.$type.'.', 3, 'httpstream');

		my $dbh = PDLNA::Database::connect();

		my @subtitles = ();
		PDLNA::Database::select_db(
			$dbh,
			{
				'query' => 'SELECT FULLNAME, SIZE FROM SUBTITLES WHERE ID = ? AND TYPE = ?',
				'parameters' => [ $id, $type, ],
			},
			\@subtitles,
		);

		if (defined($subtitles[0]->{FULLNAME}) && -f $subtitles[0]->{FULLNAME})
		{
			my @additional_header = ();
			if (defined($$CGI{'GETCONTENTFEATURES.DLNA.ORG'}) && $$CGI{'GETCONTENTFEATURES.DLNA.ORG'} == 1)
			{
				push(@additional_header, 'contentFeatures.dlna.org: DLNA.ORG_OP=00;DLNA.ORG_CI=0;');
			}
			if (defined($$CGI{'TRANSFERMODE.DLNA.ORG'}) && $$CGI{'TRANSFERMODE.DLNA.ORG'} eq 'Background')
			{
				push(@additional_header, 'transferMode.dlna.org: Background');
			}

			print $FH http_header({
				'content_length' => $subtitles[0]->{SIZE},
				'content_type' => 'smi/caption',
				'statuscode' => 200,
				'additional_header' => \@additional_header,
				'log' => 'httpstream',
			});

			sysopen(FILE, $subtitles[0]->{FULLNAME}, O_RDONLY);
			print $FH <FILE>;
			close(FILE);
		}
		else
		{
			print $FH http_header({
				'statuscode' => 404,
				'content_type' => 'text/plain',
			});
		}
	}
	else
	{
		print $FH http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
		});
	}
}

sub stream_media
{
	my $content_id = shift;
	my $method = shift;
	my $CGI = shift;
	my $FH = shift;
	my $model_name = shift;

	my $dbh = PDLNA::Database::connect();

	PDLNA::Log::log('ContentID: '.$content_id, 3, 'httpstream');
	if ($content_id =~ /^(\d+)\.(\w+)$/)
	{
		my $id = $1;
		PDLNA::Log::log('ID: '.$id, 3, 'httpstream');

		my @item_info;
		PDLNA::Database::select_db(
			$dbh,
			{
				'query' => 'SELECT NAME,FULLNAME,PATH,FILE_EXTENSION,SIZE,MIME_TYPE,TYPE,EXTERNAL FROM FILES WHERE ID = ?',
				'parameters' => [ $id, ],
			},
			\@item_info,
		);

		unless (defined($item_info[0]->{FULLNAME}))
		{
			PDLNA::Log::log('Content with ID '.$id.' NOT found (in media library).', 1, 'httpstream');
			print $FH http_header({
				'statuscode' => 404,
				'content_type' => 'text/plain',
				'log' => 'httpstream',
			});
			return;
		}

		if (!$item_info[0]->{EXTERNAL} && !-f $item_info[0]->{FULLNAME})
		{
			PDLNA::Log::log('Content with ID '.$id.' NOT found (on filesystem): '.$item_info[0]->{FULLNAME}.'.', 1, 'httpstream');
			print $FH http_header({
				'statuscode' => 404,
				'content_type' => 'text/plain',
				'log' => 'httpstream',
			});
			return;
		}

		# TODO sanity check for commands
#		if (!$item->file() && !($item->command()))
#		{
#			PDLNA::Log::log('Content with ID '.$id.' NOT found (command is missing).', 1, 'httpstream');
#			print $FH http_header({
#				'statuscode' => 404,
#				'content_type' => 'text/plain',
#				'log' => 'httpstream',
#			});
#			return;
#		}

		#
		# for streaming relevant code starts here
		#

		my @additional_header = ();
		push(@additional_header, 'Content-Type: '.PDLNA::Media::get_mimetype_by_modelname($item_info[0]->{MIME_TYPE}, $model_name));
		push(@additional_header, 'Content-Length: '.$item_info[0]->{SIZE}) if !$item_info[0]->{EXTERNAL};
		push(@additional_header, 'Content-Disposition: attachment; filename="'.$item_info[0]->{NAME}.'"'),
		push(@additional_header, 'Accept-Ranges: bytes');

		# Streaming of content is NOT working with SAMSUNG without this response header
		if (defined($$CGI{'GETCONTENTFEATURES.DLNA.ORG'}))
		{
			if ($$CGI{'GETCONTENTFEATURES.DLNA.ORG'} == 1)
			{
				push(@additional_header, 'contentFeatures.dlna.org: '.PDLNA::Media::dlna_contentfeatures($item_info[0]->{TYPE}, $item_info[0]->{MIME_TYPE}));
			}
			else
			{
				PDLNA::Log::log('Invalid contentFeatures.dlna.org:'.$$CGI{'GETCONTENTFEATURES.DLNA.ORG'}.'.', 1, 'httpstream');
				print $FH http_header({
					'statuscode' => 400,
					'content_type' => 'text/plain',
				});
			}
		}

		if (defined($$CGI{'GETCAPTIONINFO.SEC'}))
		{
			if ($$CGI{'GETCAPTIONINFO.SEC'} == 1)
			{
				if ($item_info[0]->{TYPE} eq 'video')
				{
#					if (my %subtitle = $item->subtitle('srt'))
#					{
#						if (defined($subtitle{'path'}) && -f $subtitle{'path'})
#						{
#							push(@additional_header, 'CaptionInfo.sec: http://'.$CONFIG{'LOCAL_IPADDR'}.':'.$CONFIG{'HTTP_PORT'}.'/subtitle/'.$id.'.srt');
#						}
#					}
				}

				unless (grep(/^contentFeatures.dlna.org:/, @additional_header))
				{
					push(@additional_header, 'contentFeatures.dlna.org: '.PDLNA::Media::dlna_contentfeatures($item_info[0]->{TYPE}, $item_info[0]->{MIME_TYPE}));
				}
			}
			else
			{
				PDLNA::Log::log('Invalid getCaptionInfo.sec:'.$$CGI{'GETCAPTIONINFO.SEC'}.'.', 1, 'httpstream');
				print $FH http_header({
					'statuscode' => 400,
					'content_type' => 'text/plain',
				});
			}
		}

		if (defined($$CGI{'GETMEDIAINFO.SEC'}))
		{
			if ($$CGI{'GETMEDIAINFO.SEC'} == 1)
			{
				if ($item_info[0]->{TYPE} eq 'video' || $item_info[0]->{TYPE} eq 'audio')
				{
					my @item_metainfo = ();
					PDLNA::Database::select_db(
						$dbh,
						{
							'query' => 'SELECT DURATION FROM FILEINFO WHERE FILEID_REF = ?',
							'parameters' => [ $id, ],
						},
						\@item_metainfo,
					);
					push(@additional_header, 'MediaInfo.sec: SEC_Duration='.$item_metainfo[0]->{DURATION}.'000;'); # in milliseconds

					unless (grep(/^contentFeatures.dlna.org:/, @additional_header))
					{
						push(@additional_header, 'contentFeatures.dlna.org: '.PDLNA::Media::dlna_contentfeatures($item_info[0]->{TYPE}, $item_info[0]->{MIME_TYPE}));
					}
				}
			}
			else
			{
				PDLNA::Log::log('Invalid getMediaInfo.sec:'.$$CGI{'GETMEDIAINFO.SEC'}.'.', 1, 'httpstream');
				print $FH http_header({
					'statuscode' => 400,
					'content_type' => 'text/plain',
				});
			}
		}

		if ($method eq 'HEAD') # handling HEAD requests
		{
			PDLNA::Log::log('Delivering content information (HEAD Request) for: '.$item_info[0]->{NAME}.'.', 1, 'httpstream');

			print $FH http_header({
				'statuscode' => 200,
				'additional_header' => \@additional_header,
				'log' => 'httpstream',
			});
		}
		elsif ($method eq 'GET') # handling GET requests
		{
			# for clients, which are not sending the Streaming value for the transferMode.dlna.org parameter
			# we set it, because they seem to ignore it
			if (defined($$CGI{'USER-AGENT'}))
			{
				if (
					$$CGI{'USER-AGENT'} =~ /^foobar2000/ || # since foobar2000 is NOT sending any TRANSFERMODE.DLNA.ORG param
					$$CGI{'USER-AGENT'} =~ /^vlc/i || # since vlc is NOT sending any TRANSFERMODE.DLNA.ORG param
					$$CGI{'USER-AGENT'} =~ /^stagefright/ || # since UPnPlay is NOT sending any TRANSFERMODE.DLNA.ORG param
					$$CGI{'USER-AGENT'} =~ /^gvfs/ || # since Totem Movie Player is NOT sending any TRANSFERMODE.DLNA.ORG param
					$$CGI{'USER-AGENT'} =~ /^\(null\)/
					)
				{
					$$CGI{'TRANSFERMODE.DLNA.ORG'} = 'Streaming';
				}
			}

			if (defined($$CGI{'TRANSFERMODE.DLNA.ORG'}))
			{
				if ($$CGI{'TRANSFERMODE.DLNA.ORG'} eq 'Streaming') # for immediate rendering of audio or video content
				{
					push(@additional_header, 'transferMode.dlna.org: Streaming');

					my $statuscode = 200;
					my ($lowrange, $highrange) = 0;
					if (
						defined($$CGI{'RANGE'}) &&
						$$CGI{'RANGE'} =~ /^bytes=(\d+)-(\d*)$/ &&
						!$item_info[0]->{EXTERNAL}
					)
					{
						PDLNA::Log::log('Delivering content for: '.$item_info[0]->{FULLNAME}.' with RANGE Request.', 1, 'httpstream');
						my $statuscode = 206;

						$lowrange = int($1);
						$highrange = $2 ? int($2) : 0;
						$highrange = $item_info[0]->{SIZE}-1 if $highrange == 0;
						$highrange = $item_info[0]->{SIZE}-1 if ($highrange >= $item_info[0]->{SIZE});

						my $bytes_to_ship = $highrange - $lowrange + 1;

						$additional_header[1] = 'Content-Length: '.$bytes_to_ship; # we need to change the Content-Length
						push(@additional_header, 'Content-Range: bytes '.$lowrange.'-'.$highrange.'/'.$item_info[0]->{SIZE});
					}

					#
					# sending the response
					#
					if (!$item_info[0]->{EXTERNAL}) # file on disk
					{
						sysopen(ITEM, $item_info[0]->{FULLNAME}, O_RDONLY);
						sysseek(ITEM, $lowrange, 0) if $lowrange;
					}
					else # transcoding / external script
					{
						# TODO implement for commands
						#open(ITEM, '-|', $item->command());
						#binmode(ITEM);
						@additional_header = map { /^(Content-Length|Accept-Ranges):/i ? () : $_ } @additional_header; # delete some header
					}
					print $FH http_header({
						'statuscode' => $statuscode,
						'additional_header' => \@additional_header,
						'log' => 'httpstream',
					});
					my $buf = undef;
					while (sysread(ITEM, $buf, $CONFIG{'BUFFER_SIZE'}))
					{
						PDLNA::Log::log('Adding '.bytes::length($buf).' bytes to Streaming connection.', 3, 'httpstream');
						print $FH $buf or return 1;
					}
					close(ITEM);
					return 1;
				}
				elsif ($$CGI{'TRANSFERMODE.DLNA.ORG'} eq 'Interactive') # for immediate rendering of images or playlist files
				{
					PDLNA::Log::log('Delivering (Interactive) content for: '.$item_info[0]->{FULLNAME}.'.', 1, 'httpstream');
					push(@additional_header, 'transferMode.dlna.org: Interactive');

					# Delivering interactive content as a whole
					print $FH http_header({
						'statuscode' => 200,
						'additional_header' => \@additional_header,
					});
					sysopen(FILE, $item_info[0]->{FULLNAME}, O_RDONLY);
					print $FH <FILE>;
					close(FILE);
				}
				else # unknown TRANSFERMODE.DLNA.ORG is set
				{
					PDLNA::Log::log('Transfermode '.$$CGI{'TRANSFERMODE.DLNA.ORG'}.' for Streaming Items is NOT supported yet.', 2, 'httpstream');
					print $FH http_header({
						'statuscode' => 501,
						'content_type' => 'text/plain',
					});
				}
			}
			else # no TRANSFERMODE.DLNA.ORG is set
			{
				PDLNA::Log::log('Delivering content information (no Transfermode) for: '.$item_info[0]->{FULLNAME}.'.', 1, 'httpstream');
				print $FH http_header({
					'statuscode' => 200,
					'additional_header' => \@additional_header,
					'log' => 'httpstream',
				});
			}
		}
		else
		{
			PDLNA::Log::log('HTTP Method '.$method.' for Streaming Items is NOT supported yet.', 2, 'httpstream');
			print $FH http_header({
				'statuscode' => 501,
				'content_type' => 'text/plain',
				'log' => 'httpstream',
			});
		}
	}
	else
	{
		PDLNA::Log::log('ContentID '.$content_id.' for Streaming Items is NOT supported yet.', 2, 'httpstream');
		print $FH http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
			'log' => 'httpstream',
		});
	}
}

sub preview_media
{
	my $content_id = shift;

	if ($content_id =~ /^(\d+)\./)
	{
		my $id = $1;

		my $dbh = PDLNA::Database::connect();

		my @item_info = ();
		PDLNA::Database::select_db(
			$dbh,
			{
				'query' => 'SELECT NAME,FULLNAME,PATH,FILE_EXTENSION,SIZE,MIME_TYPE,TYPE,EXTERNAL FROM FILES WHERE ID = ?',
				'parameters' => [ $id, ],
			},
			\@item_info,
		);

		if (defined($item_info[0]->{FULLNAME}))
		{
			if (-f $item_info[0]->{FULLNAME})
			{
				PDLNA::Log::log('Delivering preview for NON EXISTING Item is NOT supported.', 2, 'httpstream');
				return http_header({
					'statuscode' => 404,
					'content_type' => 'text/plain',
				});
			}

			if ($item_info[0]->{EXTERNAL})
			{
				PDLNA::Log::log('Delivering preview for EXTERNAL Item is NOT supported yet.', 2, 'httpstream');
				return http_header({
					'statuscode' => 501,
					'content_type' => 'text/plain',
				});
			}

			if ($item_info[0]->{TYPE} eq 'audio')
			{
				PDLNA::Log::log('Delivering preview for Audio Item is NOT supported yet.', 2, 'httpstream');
				return http_header({
					'statuscode' => 501,
					'content_type' => 'text/plain',
				});
			}

			PDLNA::Log::log('Delivering preview for: '.$item_info[0]->{FULLNAME}.'.', 2, 'httpstream');

			my $randid = '';
			my $path = $item_info[0]->{FULLNAME};
			if ($item_info[0]->{TYPE} eq 'video') # we need to create the thumbnail
			{
				$randid = PDLNA::Utils::get_randid();
				# this way is a little bit ugly ... but works for me
				system($CONFIG{'MPLAYER_BIN'}.' -vo jpeg:outdir='.$CONFIG{'TMP_DIR'}.'/'.$randid.'/ -frames 1 -ss 10 "'.$path.'" > /dev/null 2>&1');
				$path = glob("$CONFIG{'TMP_DIR'}/$randid/*");
				unless (defined($path))
				{
					PDLNA::Log::log('Problem creating temporary directory for Item Preview.', 2, 'httpstream');
					return http_header({
						'statuscode' => 404,
						'content_type' => 'text/plain',
					});
				}
			}

			# image scaling stuff
			GD::Image->trueColor(1);
			my $image = GD::Image->new($path);
			unless ($image)
			{
				PDLNA::Log::log('Problem creating GD::Image object for Item Preview.', 2, 'httpstream');
				return http_header({
					'statuscode' => 501,
					'content_type' => 'text/plain',
				});
			}
			my $height = $image->height / ($image->width/160);
			my $preview = GD::Image->new(160, $height);
			$preview->copyResampled($image, 0, 0, 0, 0, 160, $height, $image->width, $image->height);

			# remove tmp files from thumbnail generation
			if ($item_info[0]->{TYPE} eq 'video')
			{
				unlink($path);
				rmdir("$CONFIG{'TMP_DIR'}/$randid");
			}

			# the response itself
			my $response = http_header({
				'statuscode' => 200,
				'content_type' => 'image/jpeg',
			});
			$response .= $preview->jpeg();
			$response .= "\r\n";

			return $response;
		}
		else
		{
			PDLNA::Log::log('ContentID '.$id.' NOT found.', 2, 'httpstream');
			return http_header({
				'statuscode' => 404,
				'content_type' => 'text/plain',
			});
		}
	}
	else
	{
		PDLNA::Log::log('ContentID '.$content_id.' for Item Preview is NOT supported yet.', 2, 'httpstream');
		return http_header({
			'statuscode' => 404,
			'content_type' => 'text/plain',
		});
	}
}

sub logo
{
	my ($size, $type) = split('/', shift);
	$type = lc($1) if ($type =~ /\.(\w{3,4})$/);

	my $response = '';
	if ($type =~ /^(jpeg|png)$/)
	{
		PDLNA::Log::log('Delivering Logo in format '.$type.' and with '.$size.'x'.$size.' pixels.', 2, 'httpgeneric');

		GD::Image->trueColor(1);
		my $image = GD::Image->new('PDLNA/pDLNA.png');
		my $preview = GD::Image->new($size, $size);

		# all black areas of the image should be transparent
		my $black = $preview->colorAllocate(0,0,0);
		$preview->transparent($black);

		$preview->copyResampled($image, 0, 0, 0, 0, $size, $size, $image->width, $image->height);

		my @additional_header = ();
		$additional_header[0] = 'Content-Type: image/jpeg' if ($type eq 'jpeg');
		$additional_header[0] = 'Content-Type: image/png' if ($type eq 'png');

		$response = http_header({
			'statuscode' => 200,
			'additional_header' => \@additional_header,
		});
		$response .= $preview->jpeg() if ($type eq 'jpeg');
		$response .= $preview->png() if ($type eq 'png');
		$response .= "\r\n";
	}
	else
	{
		PDLNA::Log::log('Unknown Logo format '.$type.'.', 2, 'httpgeneric');
		$response = http_header({
			'statuscode' => 404,
			'content_type' => 'text/plain',
		});
	}

	return $response;
}

1;
