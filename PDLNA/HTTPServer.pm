package PDLNA::HTTPServer;
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2011 Stefan Heumader <stefan@heumader.at>
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
use XML::Simple;
use Date::Format;
use GD;
use Net::Netmask;

use Socket;
use IO::Select;

use threads;
use threads::shared;

use PDLNA::Config;
use PDLNA::Log;
use PDLNA::Content;
use PDLNA::ContentLibrary;
use PDLNA::Library;
use PDLNA::HTTPXML;

our $content = undef;

our %DLNA_CONTENTFEATURES = (
	'image' => 'DLNA.ORG_PN=JPEG_LRG;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=00D00000000000000000000000000000',
	'image_sm' => 'DLNA.ORG_PN=JPEG_SM;DLNA.ORG_CI=1;DLNA.ORG_FLAGS=00D00000000000000000000000000000',
	'image_tn' => 'DLNA.ORG_PN=JPEG_TN;DLNA.ORG_CI=1;DLNA.ORG_FLAGS=00D00000000000000000000000000000',
	'video' => 'DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01500000000000000000000000000000',
	'audio' => 'DLNA.ORG_PN=MP3;DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01500000000000000000000000000000',
);

sub initialize_content
{
	#$content = PDLNA::Content->new();
	#$content->build_database();
	#PDLNA::Log::log($content->print_object(), 3, 'library');

	$content = PDLNA::ContentLibrary->new();
	PDLNA::Log::log($content->print_object(), 3, 'library');
}

sub start_webserver
{
	PDLNA::Log::log('Starting HTTP Server listening on '.$CONFIG{'LOCAL_IPADDR'}.':'.$CONFIG{'HTTP_PORT'}.'.', 0, 'default');

	# got inspired by: http://www.adp-gmbh.ch/perl/webserver/
	local *S;
	socket(S, PF_INET, SOCK_STREAM, getprotobyname('tcp')) || die "Can't open HTTPServer socket: $!\n";
	setsockopt(S, SOL_SOCKET, SO_REUSEADDR, 1);
	my $server_ip = inet_aton($CONFIG{'LOCAL_IPADDR'});
	bind(S, sockaddr_in($CONFIG{'HTTP_PORT'}, $server_ip)); # INADDR_ANY
	listen(S, 5) || die "Can't listen to HTTPServer socket: $!\n";

	my $ss = IO::Select->new();
	$ss->add(*S);

	while(1)
	{
		my @connections_pending = $ss->can_read();
		foreach my $connection (@connections_pending)
		{
			my $FH;
			my $remote = accept($FH, $connection);
			my ($peer_src_port, $peer_addr) = sockaddr_in($remote);
			my $peer_ip_addr = inet_ntoa($peer_addr);

			my $thread = threads->create(\&handle_connection, $FH, $peer_ip_addr, $peer_src_port);
			$thread->detach();
		}
	}
}

sub handle_connection
{
	my $FH = shift;
	my $peer_ip_addr = shift;
	my $peer_src_port = shift;
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

	# Check if the peer is one of our allowed clients
	my $client_allowed = 0;
	foreach my $block (@{$CONFIG{'ALLOWED_CLIENTS'}})
	{
		$client_allowed++ if $block->match($peer_ip_addr);
	}

	# handling different HTTP requests
	if ($client_allowed)
	{
		PDLNA::Log::log('Received HTTP Request from allowed client IP '.$peer_ip_addr.'.', 2, 'httpgeneric');

		if ($ENV{'OBJECT'} eq '/ServerDesc.xml') # delivering server description XML
		{
			PDLNA::Log::log('New HTTP Connection: Delivering server description XML to: '.$peer_ip_addr.':'.$peer_src_port.'.', 1, 'discovery');

			my $xml = PDLNA::HTTPXML::get_serverdescription();
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
			PDLNA::Log::log('New HTTP Connection: '.$peer_ip_addr.':'.$peer_src_port.' is '.$ENV{'METHOD'}.' to '.$ENV{'OBJECT'}, 1, 'discovery');
			my @additional_header = (
				'Content-Length: 0',
				'SID: '.$CONFIG{'UUID'},
				'Timeout: Second-'.$CONFIG{'CACHE_CONTROL'},
			);
			my $response = http_header({
				'statuscode' => 200,
				'additional_header' => \@additional_header,
			});
			print $FH $response;
		}
		elsif ($ENV{'OBJECT'} eq '/upnp/control/ContentDirectory1') # handling Directory Listings
		{
			PDLNA::Log::log('New HTTP Connection: '.$peer_ip_addr.':'.$peer_src_port.' -> SoapAction: '.$ENV{'METHOD'}.' '.$CGI{'SOAPACTION'}.'.', 1, 'httpdir');
			print $FH ctrl_content_directory_1($post_xml, $CGI{'SOAPACTION'});
		}
		elsif ($ENV{'OBJECT'} =~ /^\/media\/(.*)$/) # handling media streaming
		{
			PDLNA::Log::log('New HTTP Connection: '.$peer_ip_addr.':'.$peer_src_port.' -> Request: '.$ENV{'METHOD'}.' '.$ENV{'OBJECT'}.'.', 1, 'httpstream');
			print $FH stream_media($1, $ENV{'METHOD'}, \%CGI);
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
		elsif ($ENV{'OBJECT'} =~ /^\/library\/(.*)$/) # this is just to be something different (not DLNA stuff)
		{
			print $FH PDLNA::Library::show_library(\$content);
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
	push(@response, "Server: ".$CONFIG{'OS'}."/".$CONFIG{'OS_VERSION'}.", UPnP/1.0, ".$CONFIG{'PROGRAM_NAME'}."/".$CONFIG{'PROGRAM_VERSION'});
	push(@response, "Content-Type: ".$params->{'content_type'}) if $params->{'content_type'};
	push(@response, "Date: ".PDLNA::Utils::http_date());
#	push(@response, "Last-Modified: ".PDLNA::Utils::http_date());
	if (defined($$params{'additional_header'}))
	{
		foreach my $header (@{$$params{'additional_header'}})
		{
			push(@response, $header);
		}
	}
	push(@response, "Connection: close");

	PDLNA::Log::log("HTTP Response Header:\n\t".join("\n\t",@response), 3, $$params{'log'}) if defined($$params{'log'});
	return join("\r\n", @response)."\r\n\r\n";
}

sub ctrl_content_directory_1
{
	my $xml = shift;
	my $action = shift;

	PDLNA::Log::log("Function PDLNA::HTTPServer::ctrl_content_directory_1 called", 3, 'httpdir');

	my $response = undef;

	if ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#Browse"')
	{
		my ($object_id, $starting_index, $requested_count) = 0;
		# determine which 'Browse' element was used
		# TODO ObjectID might not be set - so what value should we suggest
		#      it seems like ObjectID is not set, when 'return' or 'upper directory' is chosen in the menu
		#      implementing a history seems stupid
		if (defined($xml->{'s:Body'}->{'ns0:Browse'}->{'ObjectID'})) # coherence seems to use this one
		{
			$object_id = $xml->{'s:Body'}->{'ns0:Browse'}->{'ObjectID'};
			$starting_index = $xml->{'s:Body'}->{'ns0:Browse'}->{'StartingIndex'};
			$requested_count = $xml->{'s:Body'}->{'ns0:Browse'}->{'RequestedCount'};
		}
		elsif (defined($xml->{'s:Body'}->{'u:Browse'}->{'ObjectID'})) # samsung uses this one
		{
			$object_id = $xml->{'s:Body'}->{'u:Browse'}->{'ObjectID'};
			$starting_index = $xml->{'s:Body'}->{'u:Browse'}->{'StartingIndex'};
			$requested_count = $xml->{'s:Body'}->{'u:Browse'}->{'RequestedCount'};
		}
		#elsif (defined($xml->{'s:Body'}->{'m:Browse'}->{'ObjectID'})) # windows media player this one
		#{
		#	$object_id = $xml->{'s:Body'}->{'m:Browse'}->{'ObjectID'};
		#	$starting_index = $xml->{'s:Body'}->{'m:Browse'}->{'StartingIndex'};
		#	$requested_count = $xml->{'s:Body'}->{'m:Browse'}->{'RequestedCount'};
		#}
		else
		{
			PDLNA::Log::log('Unable to find (a known) ObjectID in XML (POSTDATA).', 1, 'httpdir');
			return http_header({
				'statuscode' => 501,
				'content_type' => 'text/plain',
			});
		}

		#
		# TODO
		# handle those parameters
		#
		# <BrowseFlag>BrowseDirectChildren</BrowseFlag>, <BrowseFlag>BrowseMetadata</BrowseFlag>
		# <Filter>*</Filter>
		#

		PDLNA::Log::log('Starting to handle Directory Listing request for: '.$object_id.'.', 3, 'httpdir');
		PDLNA::Log::log('StartingIndex: '.$starting_index.'.', 3, 'httpdir');
		PDLNA::Log::log('RequestedCount: '.$requested_count.'.', 3, 'httpdir');

		$requested_count = 10 if $requested_count == 0; # if client asks for 0 items, we should return the 'default' amount

		if ($object_id =~ /^\d+$/)
		{
			PDLNA::Log::log('Received numeric Directory Listing request for: '.$object_id.'.', 2, 'httpdir');
			my $object = $content->get_object_by_id($object_id);

			if (defined($object) && $object->is_directory())
			{
				$response = http_header({
					'statuscode' => 200,
					'log' => 'httpdir',
				});

				$response .= PDLNA::HTTPXML::get_browseresponse_header();

				PDLNA::Log::log('Found Object with ID '.$object->id().'.', 3, 'httpdir');

				my $element_counter = 0; # just counts all elements
				my $element_listed = 0; # count the elements, which are included in the reponse

				foreach my $id (keys %{$object->directories()})
				{
					if ($element_counter >= $starting_index && $element_listed < $requested_count)
					{
						PDLNA::Log::log('Including Directory with name: '.${$object->directories()}{$id}->name().' to response.', 3, 'httpdir');
						$response .= PDLNA::HTTPXML::get_browseresponse_directory(${$object->directories()}{$id});
						$element_listed++;
					}
					$element_counter++;
				}
				foreach my $id (keys %{$object->items()})
				{
					if ($element_counter >= $starting_index && $element_listed < $requested_count)
					{
						PDLNA::Log::log('Including Item with name: '.${$object->items()}{$id}->name().' to response.', 3, 'httpdir');
						$response .= PDLNA::HTTPXML::get_browseresponse_item(${$object->items()}{$id});
						$element_listed++;
					}
					$element_counter++;
				}

				$response .= PDLNA::HTTPXML::get_browseresponse_footer($element_listed, $object->amount());
			}
			else
			{
				PDLNA::Log::log('Unable to find matching ContentDirectory by ObjectID '.$object_id.'.', 1, 'httpdir');
				return http_header({
					'statuscode' => 404,
					'content_type' => 'text/plain',
				});
			}
		}



















		elsif ($xml->{'s:Body'}->{'u:Browse'}->{'ObjectID'} =~ /^(\w)_(\w)$/)
		{
			PDLNA::Log::log("Received Directory Listing request for: ".$xml->{'s:Body'}->{'u:Browse'}->{'ObjectID'}, 3, 'httpdir');

			my $media_type = $1;
			my $sort_type = $2;

			$response = http_header({
				'statuscode' => 200,
			});

			$response .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
			$response .= '<s:Body>';
			$response .= '<u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
			$response .= '<Result>';
			$response .= '&lt;DIDL-Lite xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot; xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; xmlns:upnp=&apos;urn:schemas-upnp-org:metadata-1-0/upnp/&apos; xmlns:dlna=&quot;urn:schemas-dlna-org:metadata-1-0/&quot; xmlns:sec=&quot;http://www.sec.co.kr/&quot;&gt;';
			my $content_type_obj = $content->get_content_type($media_type, $sort_type);
			foreach my $group (@{$content_type_obj->content_groups()})
			{
				my $group_id = $group->beautiful_id();
				my $group_name = $group->name();
				my $group_childs_amount = $group->content_items_amount();

				$response .= '&lt;container id=&quot;'.$media_type.'_'.$sort_type.'_'.$group_id.'&quot; parentId=&quot;'.$media_type.'_'.$sort_type.'&quot; childCount=&quot;'.$group_childs_amount.'&quot; restricted=&quot;1&quot;&gt;';
				$response .= '&lt;dc:title&gt;'.$group_name.'&lt;/dc:title&gt;';
				$response .= '&lt;upnp:class&gt;object.container&lt;/upnp:class&gt;';
				$response .= '&lt;/container&gt;';
			}
			$response .= '&lt;/DIDL-Lite&gt;';
			$response .= '</Result>';
			$response .= '<NumberReturned>'.$content_type_obj->content_groups_amount.'</NumberReturned>';
			$response .= '<TotalMatches>'.$content_type_obj->content_groups_amount.'</TotalMatches>',
			$response .= '<UpdateID>0</UpdateID>';
			$response .= '</u:BrowseResponse>';
			$response .= '</s:Body>';
			$response .= '</s:Envelope>';
		}
		elsif ($xml->{'s:Body'}->{'u:Browse'}->{'ObjectID'} =~ /^(\w)_(\w)_(\d+)_(\d+)/)
		{
			my $media_type = $1;
			my $sort_type = $2;
			my $group_id = $3;
			my $item_id = $4;

			my $content_type_obj = $content->get_content_type($media_type, $sort_type);
			my $content_group_obj = $content_type_obj->content_groups()->[int($group_id)];
			my $foldername = $content_group_obj->name();
			my $content_item_obj = $content_group_obj->content_items()->[int($item_id)];
			my $name = $content_item_obj->name();
			my $date = $content_item_obj->date();
			my $beautiful_date = time2str("%Y-%m-%d", $date);
			my $size = $content_item_obj->size();
			my $type = $content_item_obj->type();

			$response = http_header({
				'statuscode' => 200,
			});

			my $item_name = $media_type.'_'.$sort_type.'_'.$group_id.'_'.$item_id;
			my $url = 'http://'.$CONFIG{'LOCAL_IPADDR'}.':'.$CONFIG{'HTTP_PORT'};

			$response .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
			$response .= '<s:Body>';
			$response .= '<u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
			$response .= '<Result>';
			$response .= '&lt;DIDL-Lite xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot; xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; xmlns:upnp=&apos;urn:schemas-upnp-org:metadata-1-0/upnp/&apos; xmlns:dlna=&quot;urn:schemas-dlna-org:metadata-1-0/&quot; xmlns:sec=&quot;http://www.sec.co.kr/&quot;&gt;';

			$response .= '&lt;item id=&quot;'.$item_name.'&quot; parentId=&quot;'.$media_type.'_'.$sort_type.'_'.$group_id.'&quot; restricted=&quot;1&quot;&gt;';
			$response .= '&lt;dc:title&gt;'.$name.'&lt;/dc:title&gt;';
			$response .= '&lt;upnp:class&gt;object.item.'.$type.'Item&lt;/upnp:class&gt;';

			if ($media_type eq 'A')
			{
				$response .= '&lt;upnp:album&gt;'.$content_item_obj->album().'&lt;/upnp:album&gt;';
				$response .= '&lt;dc:creator&gt;'.$content_item_obj->artist().'&lt;/dc:creator&gt;';
				$response .= '&lt;upnp:genre&gt;'.$content_item_obj->genre().'&lt;/upnp:genre&gt;';
			}
			$response .= '&lt;sec:dcmInfo&gt;';

#			$response .= 'WIDTH=1920,HEIGHT=1080,COMPOSCORE=0,COMPOID=8192,COLORSCORE=26777,COLORID=2,MONTHLY=9,ORT=1,' if $media_type eq 'I';

			$response .= 'CREATIONDATE='.$date;
			$response .= ',YEAR='.$content_item_obj->year() if $media_type eq 'A';
			$response .= ',FOLDER='.$foldername.'&lt;/sec:dcmInfo&gt;';
			$response .= '&lt;dc:date&gt;'.$beautiful_date.'&lt;/dc:date&gt;';

			# File specific information
			$response .= '&lt;res protocolInfo=&quot;http-get:*:'.$content_item_obj->mime_type().':'.$DLNA_CONTENTFEATURES{$type}.'&quot; size=&quot;'.$size.'&quot; ';
			$response .= 'duration=&quot;0:17:09&quot;&gt;' if $media_type eq 'V'; # TODO get the length of the video
			$response .= 'duration=&quot;'.$content_item_obj->duration().'&quot;&gt;' if $media_type eq 'A';
			$response .= 'resolution=&quot;'.$content_item_obj->resolution().'&quot;&gt;' if $media_type eq 'I';
			$response .= $url.'/media/'.$item_name.'.'.$content_item_obj->file_extension().'&lt;/res&gt;';

			# File preview information
			if ($media_type eq 'I' || $media_type eq 'V')
			{
				my $mime = 'image/jpeg';
				$response .= '&lt;res protocolInfo=&quot;http-get:*:'.$mime.':'.$DLNA_CONTENTFEATURES{'image_sm'}.'&quot; resolution=&quot;&quot;&gt;'.$url.'/preview/'.$item_name.'.JPEG_SM&lt;/res&gt;';
				$response .= '&lt;res protocolInfo=&quot;http-get:*:'.$mime.':'.$DLNA_CONTENTFEATURES{'image_tn'}.'&quot;&gt;'.$url.'/preview/'.$item_name.'.JPEG_TN&lt;/res&gt;';
			}

			$response .= '&lt;/item&gt;';
			$response .= '&lt;/DIDL-Lite&gt;</Result><NumberReturned>1</NumberReturned><TotalMatches>1</TotalMatches><UpdateID>0</UpdateID></u:BrowseResponse></s:Body></s:Envelope>';
		}
		else
		{
			PDLNA::Log::log('The following directory listing is NOT supported yet: '.$object_id, 3, 'httpdir');
			$response = http_header({
				'statuscode' => 501,
				'content_type' => 'text/plain',
			});
		}
	}
	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#X_GetObjectIDfromIndex"')
	{
		my $media_type = '';
		my $sort_type = '';
		if ($xml->{'s:Body'}->{'u:X_GetObjectIDfromIndex'}->{'CategoryType'} == 14)
		{
			$media_type = 'I';
			$sort_type = 'F';
		}
		elsif ($xml->{'s:Body'}->{'u:X_GetObjectIDfromIndex'}->{'CategoryType'} == 22)
		{
			$media_type = 'A';
			$sort_type = 'F';
		}
		elsif ($xml->{'s:Body'}->{'u:X_GetObjectIDfromIndex'}->{'CategoryType'} == 32)
		{
			$media_type = 'V';
			$sort_type = 'F';
		}
		PDLNA::Log::log('Getting object for '.$media_type.'_'.$sort_type.'.', 2, 'httpdir');

		my $index = $xml->{'s:Body'}->{'u:X_GetObjectIDfromIndex'}->{'Index'};

		my $content_type_obj = $content->get_content_type($media_type, $sort_type);
		my $i = 0;
		my @groups = @{$content_type_obj->content_groups()};
		while ($index >= $groups[$i]->content_items_amount())
		{
			$index -= $groups[$i]->content_items_amount();
			$i++;
		}
		my $content_item_obj = $groups[$i]->content_items()->[$index];

		$response = http_header({
			'statuscode' => 200,
		});

		$response .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
		$response .= '<s:Body>';
		$response .= '<u:X_GetObjectIDfromIndexResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$response .= '<ObjectID>'.$media_type.'_'.$sort_type.'_'.$groups[$i]->beautiful_id().'_'.$content_item_obj->beautiful_id().'</ObjectID>';
		$response .= '</u:X_GetObjectIDfromIndexResponse>';
		$response .= '</s:Body>';
		$response .= '</s:Envelope>';
	}
	# X_GetIndexfromRID (i think it might be the question, to which item the tv should jump ... but currently i don't understand the question (<RID></RID>) ... so it's still a TODO
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

sub stream_media
{
	my $content_id = shift;
	my $method = shift;
	my $CGI = shift;

	if ($content_id =~ /^(\d+)\./)
	{
		my $id = $1;

		my $item = $content->get_object_by_id($id);
		if (defined($item) && $item->is_item() && -f $item->path())
		{
			my $response = '';
			my @additional_header = (
				'Content-Type: '.$item->mime_type(),
				'Content-Length: '.$item->size(),
				'Content-Disposition: attachment; filename="'.$item->name().'"',
			);

			# Streaming of content is NOT working with SAMSUNG without this response header
			if (defined($$CGI{'GETCONTENTFEATURES.DLNA.ORG'}))
			{
				if ($$CGI{'GETCONTENTFEATURES.DLNA.ORG'} == 1)
				{
					push(@additional_header, 'contentFeatures.dlna.org: '.$DLNA_CONTENTFEATURES{$item->type()});
				}
				else
				{
					PDLNA::Log::log('Invalid contentFeatures.dlna.org:'.$$CGI{'GETCONTENTFEATURES.DLNA.ORG'}.'.', 1, 'httpstream');
					return http_header({
						'statuscode' => 400,
						'content_type' => 'text/plain',
					});
				}
			}

			if ($method eq 'HEAD') # handling HEAD requests
			{
				PDLNA::Log::log('Delivering content information (HEAD Request) for: '.$item->path().'.', 1, 'httpstream');

				return http_header({
					'statuscode' => 200,
					'additional_header' => \@additional_header,
					'log' => 'httpstream',
				});
			}
			elsif ($method eq 'GET') # handling GET requests
			{
				if (defined($$CGI{'TRANSFERMODE.DLNA.ORG'}))
				{
					if ($$CGI{'TRANSFERMODE.DLNA.ORG'} eq 'Streaming') # for immediate rendering of audio or video content
					{
						PDLNA::Log::log('Delivering (Streaming) content for: '.$item->path().'.', 1, 'httpstream');

						push(@additional_header, 'Accept-Ranges: bytes');
						my $lowrange = 0;
						my $bytes_to_ship = 102400;

						open(FILE, $item->path());
						my $buf = undef;

						# using read with offset isn't working - why is it ignoring my offset
						#read(FILE, $buf, $bytes_to_ship, $offset);

						# so we're using seek instead
						sysseek(FILE, $lowrange, 1);
						sysread(FILE, $buf, $bytes_to_ship);
						use bytes;
						PDLNA::Log::log('Length of our buffer: '.bytes::length($buf).'.', 3, 'httpstream');
						no bytes;

						$additional_header[1] = 'Content-Range: bytes '.$lowrange.'-'.$bytes_to_ship.'/'.$item->size();
						$response = http_header({
							'statuscode' => 200,
							'additional_header' => \@additional_header,
							'log' => 'httpstream',
						});
						$response .= $buf;
						#$response .= "\r\n";

						return $response;
					}
					elsif ($$CGI{'TRANSFERMODE.DLNA.ORG'} eq 'Interactive') # for immediate rendering of images or playlist files
					{
						PDLNA::Log::log('Delivering (Interactive) content for: '.$item->path().'.', 1, 'httpstream');
						push(@additional_header, 'transferMode.dlna.org: Interactive');

						# Delivering interactive content as a whole
						$response = http_header({
							'statuscode' => 200,
							'additional_header' => \@additional_header,
						});
						open(FILE, $item->path());
						while (<FILE>)
						{
							$response .= $_;
						}
						close(FILE);

						return $response;
					}
					else
					{
					}
				}
			}
			else
			{
				PDLNA::Log::log('Method '.$method.' for Streaming Items is NOT supported yet.', 2, 'httpstream');
				return http_header({
					'statuscode' => 501,
					'content_type' => 'text/plain',
				});
			}
			return $response;
		}
		else
		{
			PDLNA::Log::log('Content with ID '.$id.' NOT found: '.$item->path().'.', 1, 'httpstream');
			return http_header({
				'statuscode' => 404,
				'content_type' => 'text/plain',
			});
		}
	}



	# old stuff
	elsif ($content_id =~ /^(\w)_(\w)_(\d+)_(\d+)/)
	{
		my $media_type = $1;
		my $sort_type = $2;
		my $group_id = $3;
		my $item_id = $4;

		my $content_type_obj = $content->get_content_type($media_type, $sort_type);
		my $content_group_obj = $content_type_obj->content_groups()->[int($group_id)];
		my $content_item_obj = $content_group_obj->content_items()->[int($item_id)];
		my $path = $content_item_obj->path();
		my $size = $content_item_obj->size();
		my $type = $content_item_obj->type();

		my $response = "";
		if (-f $path)
		{
			my @additional_header = (
				'Content-Type: '.$content_item_obj->mime_type(),
				'Content-Length: '.$size,
				'Cache-Control: no-cache',
			);

			if (defined($$CGI{'GETCONTENTFEATURES.DLNA.ORG'}))
			{
				if ($$CGI{'GETCONTENTFEATURES.DLNA.ORG'} == 1)
				{
					# found no documentation for this header ... but i think it might be the correct answer
					push(@additional_header, 'contentFeatures.dlna.org:'.$DLNA_CONTENTFEATURES{$type});
				}
				else
				{
					PDLNA::Log::log('Invalid contentFeatures.dlna.org:'.$$CGI{'GETCONTENTFEATURES.DLNA.ORG'}.'.', 1, 'httpstream');
					return http_header({
						'statuscode' => 400,
						'content_type' => 'text/plain',
					});
				}
			}
			elsif (defined($$CGI{'GETCAPTIONINFO.SEC'}) && $$CGI{'GETCAPTIONINFO.SEC'} == 1)
			{
				# if GETCAPTIONINFO.SEC is set, but not GETCONTENTFEATURES.DLNA.ORG, we need to answer with the information too
				push(@additional_header, 'contentFeatures.dlna.org:'.$DLNA_CONTENTFEATURES{$type});
			}
			elsif (defined($$CGI{'GETMEDIAINFO.SEC'}) && $$CGI{'GETMEDIAINFO.SEC'} == 1)
			{
				# if GETMEDIAINFO.SEC is set, but not GETCONTENTFEATURES.DLNA.ORG, we need to answer with the information too
				push(@additional_header, 'contentFeatures.dlna.org:'.$DLNA_CONTENTFEATURES{$type});
			}

			if (defined($$CGI{'GETMEDIAINFO.SEC'}) && $$CGI{'GETMEDIAINFO.SEC'} == 1)
			{
				# found no documentation for this header ... but i think it might be the correct answer to deliver the duration in milliseconds
				# device might use this value to show the progress bar
				push(@additional_header, 'MediaInfo.sec: SEC_Duration='.$content_item_obj->duration_seconds().'000;')
			}

			if (defined($$CGI{'GETCAPTIONINFO.SEC'}) && $$CGI{'GETCAPTIONINFO.SEC'} == 1)
			{
				# TODO - WTF? - it might be the information for the caption
			}

			if (defined($$CGI{'TRANSFERMODE.DLNA.ORG'}))
			{
				if ($$CGI{'TRANSFERMODE.DLNA.ORG'} eq 'Streaming') # for immediate rendering of audio or video content
				{
					PDLNA::Log::log('Streaming content for: '.$path.'.', 1, 'httpstream');

					my $statuscode = 206;

					my $bytes_to_ship = 52428800; # 50 megabytes
					my ($lowrange, $highrange) = 0;

					if (defined($$CGI{'RANGE'}) && $$CGI{'RANGE'} =~ /^bytes=(\d+)-(\d*)$/)
					{
						#if ($lowrange > 0) {
						PDLNA::Log::log('We got a RANGE HTTP Header ('.$$CGI{'RANGE'}.') from client.', 1, 'httpstream');

						$lowrange = $1;
						}
						$highrange = $size-1;
						$highrange = $lowrange+$bytes_to_ship;

						#my $content_length = $size - $lowrange;
						my $content_length = $size;
						$additional_header[1] = 'Content-Length: '.$content_length;
#						if ($content_length < $bytes_to_ship)
#						{
#							$bytes_to_ship = $content_length;
#						}

						push(@additional_header, 'Content-Range: bytes '.$lowrange.'-'.$highrange.'/'.$size);
						#}
#					}
#					else
#					{
#						PDLNA::Log::log('We got NO RANGE HTTP Header from client.', 1, 'httpstream');
#					}
					push(@additional_header, 'transferMode.dlna.org:Streaming');

					#
					# THE RESPONSE
					#

					$response = http_header({
						'statuscode' => $statuscode,
						'additional_header' => \@additional_header,
						'log' => 'httpstream',
					});


#					if ($method eq 'GET')
#					{
						open(FILE, $path);
						my $buf = undef;

						# using read with offset isn't working - why is it ignoring my offset
						#read(FILE, $buf, $bytes_to_ship, $offset);

						# so I'm using seek instead
						sysseek(FILE, $lowrange, 1);
						sysread(FILE, $buf, $bytes_to_ship);
								use bytes;
								PDLNA::Log::log('Length of our buffer: '.bytes::length($buf).'.', 3, 'httpstream');
								no bytes;
						$response .= $buf;
						$response .= "\r\n";
#					}
					close(FILE);

				}
				elsif ($$CGI{'TRANSFERMODE.DLNA.ORG'} eq 'Interactive') # for immediate rendering of images or playlist files
				{
					PDLNA::Log::log('Delivering content for: '.$path.'.', 1, 'httpstream');
					push(@additional_header, 'transferMode.dlna.org:Interactive');

					# Delivering interactive content as a whole
					$response = http_header({
						'statuscode' => 200,
						'additional_header' => \@additional_header,
					});
					open(FILE, $path);
					while (<FILE>)
					{
						$response .= $_;
					}
					close(FILE);
				}
				else
				{
					PDLNA::Log::log('Invalid transferMode.dlna.org: '.$$CGI{'TRANSFERMODE.DLNA.ORG'}.'.', 1, 'httpstream');
					return http_header({
						'statuscode' => 404,
						'content_type' => 'text/plain',
					});
				}
			}
			else # we are handling here the HEAD requests for giving the relevant information about the media
			{
				PDLNA::Log::log('Delivering content information (HEAD request) for: '.$path.'.', 1, 'httpstream');
				$response = http_header({
					'statuscode' => 200,
					'additional_header' => \@additional_header,
					'log' => 'httpstream',
				});
			}
			return $response;
		}
		else
		{
			PDLNA::Log::log('Content NOT found: '.$path.'.', 1, 'httpstream');
			return http_header({
				'statuscode' => 404,
				'content_type' => 'text/plain',
			});
		}
	}
	else
	{
		PDLNA::Log::log('Invalid content ID: '.$content_id.'.', 1, 'httpstream');
		return http_header({
			'statuscode' => 404,
			'content_type' => 'text/plain',
		});
	}
}

sub preview_media
{
	my $content_id = shift;

	if ($content_id =~ /^(\d+)\./)
	{
		my $id = $1;

		my $item = $content->get_object_by_id($id);
		if (defined($item) && $item->is_item())
		{
			unless (-f $item->path())
			{
				PDLNA::Log::log('File '.$item->path().' NOT found.', 2, 'httpstream');
				return http_header({
					'statuscode' => 404,
					'content_type' => 'text/plain',
				});
			}

			if ($item->type() eq 'audio')
			{
				PDLNA::Log::log('Delivering preview for Audio Item is NOT supported yet.', 2, 'httpstream');
				return http_header({
					'statuscode' => 501,
					'content_type' => 'text/plain',
				});
			}

			PDLNA::Log::log('Delivering preview for: '.$item->path().'.', 2, 'httpstream');

			my $randid = '';
			my $path = $item->path();
			if ($item->type() eq 'video') # we need to create the thumbnail
			{
				$randid = PDLNA::Utils::get_randid();
				# this way is a little bit ugly ... but works for me
				system("$CONFIG{'MPLAYER_BIN'} -vo jpeg:outdir=$CONFIG{'TMP_DIR'}/$randid/ -frames 1 -ss 10 '$path' > /dev/null 2>&1");
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
			my $image = GD::Image->new($path) || die $@; # TODO fix die
			my $height = $image->height / ($image->width/160);
			my $preview = GD::Image->new(160, $height);
			$preview->copyResampled($image, 0, 0, 0, 0, 160, $height, $image->width, $image->height);

			# remove tmp files from thumbnail generation
			if ($item->type() eq 'video')
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
