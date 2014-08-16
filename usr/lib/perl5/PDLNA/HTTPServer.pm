package PDLNA::HTTPServer;
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
use PDLNA::Devices;
use PDLNA::FFmpeg;
use PDLNA::HTTPXML;
use PDLNA::Log;
use PDLNA::SpecificViews;
use PDLNA::WebUI;

sub start_webserver
{
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

	my $response = undef;

	PDLNA::Log::log('Incoming HTTP connection from '.$peer_ip_addr.':'.$peer_src_port.'.', 3, 'httpgeneric');

	# Check if the peer is one of our allowed clients
	my $client_allowed = 0;
	foreach my $block (@{$CONFIG{'ALLOWED_CLIENTS'}})
	{
		$client_allowed++ if $block->match($peer_ip_addr);
	}

	unless ($client_allowed)
	{
		PDLNA::Log::log('Received HTTP request from NOT allowed client IP '.$peer_ip_addr.'.', 2, 'httpgeneric');
		$response = http_header({
			'statuscode' => 403,
			'content_type' => 'text/plain',
		});

		print $FH $response;
		close($FH);
		return 0;
	}

	#
	# PARSING HTTP REQUEST
	#
	binmode($FH);

	my %CGI = ();
	my %ENV = ();

	my $post_xml = undef;
	my $request_line = <$FH>;
	my $first_line = '';
	while (defined($request_line) && $request_line ne "\r\n")
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

	if (!defined($ENV{'METHOD'}) || !defined($ENV{'OBJECT'}))
	{
		PDLNA::Log::log('ERROR: Unable to parse HTTP request from '.$peer_ip_addr.':'.$peer_src_port.'.', 0, 'httpstream');
		$response = http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
		});

		print $FH $response;
		close($FH);
		return 0;
	}

	my $debug_string = '';
	foreach my $key (keys %CGI)
	{
		$debug_string .= "\n\t".$key.' -> '.$CGI{$key};
	}
	PDLNA::Log::log($ENV{'METHOD'}.' '.$ENV{'OBJECT'}.' from '.$peer_ip_addr.':'.$peer_src_port.':'.$debug_string, 3, 'httpgeneric');

	#
	# Reading POSTDATA, PARSING XML
	#
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
			PDLNA::Log::log('ERROR: Unable to convert POSTDATA with XML::Simple for '.$peer_ip_addr.':'.$peer_src_port.': '.$@, 0, 'httpdir');
		}
		else
		{
			PDLNA::Log::log('Finished converting POSTDATA with XML::Simple for '.$peer_ip_addr.':'.$peer_src_port.'.', 3, 'httpdir');
		}
	}

	# adding device and/or request to Devices tables
	my $dbh = PDLNA::Database::connect();
	PDLNA::Devices::add_device(
		$dbh,
		{
			'ip' => $peer_ip_addr,
			'http_useragent' => $CGI{'USER-AGENT'},
		},
	);
	my $model_name = PDLNA::Devices::get_modelname_by_devicetype($dbh, $peer_ip_addr, 'urn:schemas-upnp-org:device:MediaRenderer:1');
	PDLNA::Log::log('ModelName for '.$peer_ip_addr.' is '.$model_name.'.', 2, 'httpgeneric');
	PDLNA::Database::disconnect($dbh);

	#
	# HANDLING DIFFERENT KIND OF REQUESTS
	#
	if ($ENV{'OBJECT'} eq '/ServerDesc.xml') # delivering ServerDescription XML
	{
		my $xml = PDLNA::HTTPXML::get_serverdescription($CGI{'USER-AGENT'});
		my @additional_header = (
			'Content-Type: text/xml; charset=utf8',
			'Content-Length: '.length($xml),
		);
		$response = http_header({
			'statuscode' => 200,
			'additional_header' => \@additional_header,
		});
		$response .= $xml;
	}
	elsif ($ENV{'OBJECT'} eq '/ContentDirectory1.xml') # delivering ContentDirectory XML
	{
		my $xml = PDLNA::HTTPXML::get_contentdirectory();
		my @additional_header = (
			'Content-Type: text/xml; charset=utf8',
			'Content-Length: '.length($xml),
		);
		$response = http_header({
			'statuscode' => 200,
			'additional_header' => \@additional_header,
		});
		$response .= $xml;
	}
	elsif ($ENV{'OBJECT'} eq '/ConnectionManager1.xml') # delivering ConnectionManager XML
	{
		my $xml = PDLNA::HTTPXML::get_connectionmanager();
		my @additional_header = (
			'Content-Type: text/xml; charset=utf8',
			'Content-Length: '.length($xml),
		);
		$response = http_header({
			'statuscode' => 200,
			'additional_header' => \@additional_header,
		});
		$response .= $xml;
	}
	elsif ($ENV{'OBJECT'} eq '/upnp/event/ContentDirectory1' || $ENV{'OBJECT'} eq '/upnp/event/ConnectionManager1')
	{
		my $response_content = '';
		$response_content = '<html><body><h1>200 OK</h1></body></html>' if $ENV{'METHOD'} eq 'UNSUBSCRIBE';

		my @additional_header = (
			'Content-Length: '.length($response_content),
			'SID: '.$CONFIG{'UUID'},
			'Timeout: Second-'.$CONFIG{'CACHE_CONTROL'},
		);
		$response = http_header({
			'statuscode' => 200,
			'additional_header' => \@additional_header,
		});
		$response .= $response_content;
	}
	elsif ($ENV{'OBJECT'} eq '/upnp/control/ContentDirectory1') # handling Directory Listings
	{
		$response = ctrl_content_directory_1($post_xml, $CGI{'SOAPACTION'}, $peer_ip_addr, $CGI{'USER-AGENT'});
	}
#	elsif ($ENV{'OBJECT'} eq '/upnp/control/ConnectionManager1')
#	{
#	}
	elsif ($ENV{'OBJECT'} =~ /^\/media\/(.*)$/) # handling media streaming
	{
		stream_item($1, $ENV{'METHOD'}, \%CGI, $FH, $model_name, $peer_ip_addr, $CGI{'USER-AGENT'});
	}
	elsif ($ENV{'OBJECT'} =~ /^\/preview\/(.*)$/) # handling media thumbnails
	{
		$response = preview_media($1);
	}
	elsif ($ENV{'OBJECT'} =~ /^\/icons\/(.*)$/) # handling pDLNA logo
	{
		$response = logo($1);
	}
	elsif ($ENV{'OBJECT'} =~ /^\/webui\/js.js$/) # deliver javascript code
	{
		$response = PDLNA::WebUI::javascript();
	}
	elsif ($ENV{'OBJECT'} =~ /^\/webui\/css.css$/) # deliver stylesheet
	{
		$response = PDLNA::WebUI::css();
	}
	elsif ($ENV{'OBJECT'} =~ /^\/webui\/graphs\/(.+)\.png$/) # handling delivering graphs
	{
		print $FH PDLNA::WebUI::graph($1);
		close($FH);
	}
	elsif ($ENV{'OBJECT'} =~ /^\/webui\/(.*)$/) # handling WebUI
	{
		print $FH PDLNA::WebUI::show($1);
		close($FH);
	}
	else # NOT supported request
	{
		PDLNA::Log::log('Request '.$ENV{'METHOD'}.' '.$ENV{'OBJECT'}.' from '.$peer_ip_addr.' NOT supported yet.', 2, 'httpgeneric');
		$response = http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
		});
	}

	if (defined($response))
	{
		print $FH $response;
		close($FH);
	}
	return 1;
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

#
#
# BEGINNING OF DIRECTORY CONTROLS
#
#

sub manage_browsefilters
{
	my $filter = shift;
	my $browse_flag = shift;

	my @browsefilters = split(',', $filter) if length($filter) > 0;
	@browsefilters = () if $filter eq '*';

	if ($browse_flag eq 'BrowseDirectChildren')
	{
		# these filter seem to be mandatory, so we need to put them always into the HTTP response
		foreach my $filter ('@id', '@parentID', '@childCount', '@restricted', 'dc:title', 'upnp:class')
		{
			push(@browsefilters, $filter) unless grep(/^$filter$/, @browsefilters);
		}

		if ($filter eq '*')
		{
			push(@browsefilters, 'res@bitrate');
			push(@browsefilters, 'res@duration');
		}
	}
	elsif ($browse_flag eq 'BrowseMetadata')
	{
		if (grep(/^\@parentID$/, @browsefilters))
		{
			@browsefilters = ('@id', '@parentID', '@childCount', '@restricted', 'dc:title', 'upnp:class');
		}
		else
		{
			# these filter seem to be mandatory, so we need to put them always into the HTTP response
			foreach my $filter ('@id', '@childCount', '@restricted', 'dc:title', 'upnp:class')
			{
				push(@browsefilters, $filter) unless grep(/^$filter$/, @browsefilters);
			}
		}
	}
	PDLNA::Log::log('Modified Filter: '.$filter.' to: '.join(', ', @browsefilters).')', 3, 'httpdir');

	return @browsefilters;
}

sub build_BrowseMetadata_response
{
	my $params = shift;
	PDLNA::Log::log('Starting to prepare BrowseMetadata XML response for ID: '.$$params{'item_id'}, 3, 'httpdir');

	my $dbh = PDLNA::Database::connect();

	#
	# build the http response
	#
	my $response_xml = '';
	$response_xml .= PDLNA::HTTPXML::get_browseresponse_header();

	$response_xml .= PDLNA::HTTPXML::get_browseresponse_item(
		$$params{'item_id'},
		$$params{'browsefilters'},
		$dbh,
		$$params{'peer_ip_addr'},
		$$params{'user_agent'},
	);

	$response_xml .= PDLNA::HTTPXML::get_browseresponse_footer(1, 1);

	PDLNA::Log::log('Done preparing BrowseMetadata XML response for ID: '.$$params{'item_id'}, 3, 'httpdir');

	#
	# return the http response
	#
	PDLNA::Database::disconnect($dbh);
	return $response_xml;
}

sub build_BrowseDirectChildren_response
{
	my $params = shift;
	PDLNA::Log::log('Starting to prepare BrowseDirectChildren XML response for ID: '.$$params{'item_id'}, 3, 'httpdir');

	my $dbh = PDLNA::Database::connect();

	#
	# get the subdirectories for the item_id requested
	#
	my @dire_elements = ();
	PDLNA::ContentLibrary::get_items_by_parentid(
		$dbh,
		$$params{'item_id'},
		$$params{'starting_index'},
		$$params{'requested_count'},
		0,
		\@dire_elements,
	);

	#
	# get the full amount of subdirectories for the item_id requested
	#

	my $amount_directories = PDLNA::ContentLibrary::get_amount_items_by_parentid_n_itemtype($dbh, $$params{'item_id'}, 0);

	$$params{'requested_count'} = $$params{'requested_count'} - scalar(@dire_elements); # amount of @dire_elements is already in answer
	if ($$params{'starting_index'} >= $amount_directories)
	{
		$$params{'starting_index'} = $$params{'starting_index'} - $amount_directories;
	}

	#
	# get the files for the directory requested
	#
	my @file_elements = ();
	PDLNA::ContentLibrary::get_items_by_parentid(
		$dbh,
		$$params{'item_id'},
		$$params{'starting_index'},
		$$params{'requested_count'},
		1,
		\@file_elements,
	);

	#
	# get the full amount of files in the directory requested
	#
	my $amount_files = PDLNA::ContentLibrary::get_amount_items_by_parentid_n_itemtype($dbh, $$params{'item_id'}, 1);

	#
	# build the http response
	#
	my $response_xml = '';
	$response_xml .= PDLNA::HTTPXML::get_browseresponse_header();

	foreach my $directory (@dire_elements)
	{
		$response_xml .= PDLNA::HTTPXML::get_browseresponse_container(
			$directory->{id},
			$directory->{title},
			$$params{'browsefilters'},
			$dbh,
		);
	}

	foreach my $file (@file_elements)
	{
		$response_xml .= PDLNA::HTTPXML::get_browseresponse_item(
			$file->{id},
			$$params{'browsefilters'},
			$dbh,
			$$params{'peer_ip_addr'},
			$$params{'user_agent'},
		);
	}

	my $elements_in_listing = scalar(@dire_elements) + scalar(@file_elements);
	my $elements_in_directory = $amount_directories + $amount_files;

	$response_xml .= PDLNA::HTTPXML::get_browseresponse_footer($elements_in_listing, $elements_in_directory);

	PDLNA::Log::log('Done preparing BrowseDirectChildren XML response for ID: '.$$params{'item_id'}, 3, 'httpdir');

	#
	# return the http response
	#
	PDLNA::Database::disconnect($dbh);
	return $response_xml;
}

sub ctrl_content_directory_1
{
	my $xml = shift;
	my $action = shift;
	my $peer_ip_addr = shift;
	my $user_agent = shift;

	my $response_xml = undef;

	PDLNA::Log::log("Function PDLNA::HTTPServer::ctrl_content_directory_1 called", 3, 'httpdir');

	if ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#Browse"')
	{
		my $object_id = PDLNA::HTTPXML::lookup_elementvalue_in_xml($xml, 'ObjectID');
		my $browse_flag = PDLNA::HTTPXML::lookup_elementvalue_in_xml($xml, 'BrowseFlag');
		my $starting_index = PDLNA::HTTPXML::lookup_elementvalue_in_xml($xml, 'StartingIndex') || 0;
		my $requested_count = PDLNA::HTTPXML::lookup_elementvalue_in_xml($xml, 'RequestedCount') || 0;
		my $filter = PDLNA::HTTPXML::lookup_elementvalue_in_xml($xml, 'Filter') || '';

		#
		# sanity check - we had to find an object_id and a browse_flag
		#
		unless (defined($object_id) && defined($browse_flag))
		{
			PDLNA::Log::log('ERROR: Unable to find ObjectID and/or BrowseFlag in XML (POSTDATA).', 0, 'httpdir');
			return http_header({
				'statuscode' => 501,
				'content_type' => 'text/plain',
			});
		}

		PDLNA::Log::log('Starting to handle ContentDirectory:1#Browse request: (ObjectID: '.$object_id.'; BrowseFlag: '.$browse_flag.'; StartingIndex: '.$starting_index.'; RequestedCount: '.$requested_count.'; Filter: '.$filter.')', 3, 'httpdir');

		my @browsefilters = manage_browsefilters($filter, $browse_flag);
		$requested_count = 10 if $requested_count == 0; # if client asks for 0 items, we should return the 'default' amount (in our case 10)

		#
		# building the response
		#
		if ($browse_flag eq 'BrowseDirectChildren')
		{
			if ($object_id =~ /^\d+$/)
			{
				PDLNA::Log::log('Received numeric Directory Listing request for: '.$object_id.'.', 2, 'httpdir');

				$response_xml = build_BrowseDirectChildren_response(
					{
						item_id => $object_id,
						starting_index => $starting_index,
						requested_count => $requested_count,
						browsefilters => \@browsefilters,
						peer_ip_addr => $peer_ip_addr,
						user_agent => $user_agent,
					},
				);
			}
		}
		elsif ($browse_flag eq 'BrowseMetadata')
		{
			if (grep(/^\@parentID$/, @browsefilters) && $object_id =~ /^\d+$/)
			{
				# set object_id to parent_id
				my $dbh = PDLNA::Database::connect(); # TODO find a more elegant solution instead of opening a DB connection for this requesest
				my $parent_id = PDLNA::ContentLibrary::get_parentid_by_id($dbh, $object_id);
				PDLNA::Database::disconnect($dbh);

				$response_xml = build_BrowseDirectChildren_response(
					{
						item_id => $parent_id,
						starting_index => $starting_index,
						requested_count => $requested_count,
						browsefilters => \@browsefilters,
						peer_ip_addr => $peer_ip_addr,
						user_agent => $user_agent,
					},
				);
			}
			elsif ($object_id =~ /^\d+$/)
			{
				PDLNA::Log::log('A BrowseMetadata request with NO @parentID filter has been sent for: '.$object_id.'.', 3, 'httpdir');
				$response_xml = build_BrowseMetadata_response(
					{
						item_id => $object_id,
						starting_index => $starting_index,
						requested_count => $requested_count,
						browsefilters => \@browsefilters,
						peer_ip_addr => $peer_ip_addr,
						user_agent => $user_agent,
					},
				);
			}
		}
		else
		{
			PDLNA::Log::log('ERROR: BrowseFlag '.$browse_flag.' for ContentDirectory:1#Browse requests is NOT supported yet.', 0, 'httpdir');
			return http_header({
				'statuscode' => 501,
				'content_type' => 'text/plain',
			});
		}

		PDLNA::Log::log('Finished handling ContentDirectory:1#Browse request for ID: '.$object_id.'.', 3, 'httpdir');

		#
		# old code is coming again
		#
#		elsif ($object_id =~ /^(\w)\_(\w)\_{0,1}(\d*)\_{0,1}(\d*)/)
#		{
#			PDLNA::Log::log('Received SpecificView Directory Listing request for: '.$object_id.'.', 2, 'httpdir');
#
#			my $media_type = $1;
#			my $group_type = $2;
#			my $group_id = $3;
#			my $item_id = $4;
#
#			unless (PDLNA::SpecificViews::supported_request($media_type, $group_type))
#			{
#				PDLNA::Log::log('SpecificView: '.$media_type.'_'.$group_type.' is NOT supported yet.', 2, 'httpdir');
#				return http_header({
#					'statuscode' => 501,
#					'content_type' => 'text/plain',
#				});
#			}
#
#			if (length($group_id) == 0)
#			{
#				my @group_elements = ();
#				PDLNA::SpecificViews::get_groups($dbh, $media_type, $group_type, $starting_index, $requested_count, \@group_elements);
#				my $amount_groups = PDLNA::SpecificViews::get_amount_of_groups($dbh, $media_type, $group_type);
#
#				$response_xml .= PDLNA::HTTPXML::get_browseresponse_header();
#				foreach my $group (@group_elements)
#				{
#					$response_xml .= PDLNA::HTTPXML::get_browseresponse_group_specific(
#						$group->{ID},
#						$media_type,
#						$group_type,
#						$group->{NAME},
#						\@browsefilters,
#						$dbh,
#					);
#				}
#				$response_xml .= PDLNA::HTTPXML::get_browseresponse_footer(scalar(@group_elements), $amount_groups);
#			}
#			elsif (length($group_id) > 0 && length($item_id) == 0)
#			{
#				$group_id = PDLNA::Utils::remove_leading_char($group_id, '0');
#
#				my @item_elements = ();
#				PDLNA::SpecificViews::get_items($dbh, $media_type, $group_type, $group_id, $starting_index, $requested_count, \@item_elements);
#				my $amount_items = PDLNA::SpecificViews::get_amount_of_items($dbh, $media_type, $group_type, $group_id);
#
#				$response_xml .= PDLNA::HTTPXML::get_browseresponse_header();
#				foreach my $item (@item_elements)
#				{
#					$response_xml .= PDLNA::HTTPXML::get_browseresponse_item_specific(
#						$item->{ID},
#						$media_type,
#						$group_type,
#						$group_id,
#						\@browsefilters,
#						$dbh,
#						$peer_ip_addr,
#						$user_agent,
#					);
#				}
#				$response_xml .= PDLNA::HTTPXML::get_browseresponse_footer(scalar(@item_elements), $amount_items);
#			}
#			else
#			{
#				PDLNA::Log::log('ERROR: SpecificView: Unable to understand request for ObjectID '.$object_id.'.', 0, 'httpdir');
#				return http_header({
#					'statuscode' => 501,
#					'content_type' => 'text/plain',
#				});
#			}
#		}
	}
	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#GetSearchCapabilities"')
	{
		$response_xml .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
		$response_xml .= '<s:Body>';
		$response_xml .= '<u:GetSearchCapabilitiesResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$response_xml .= '<SearchCaps></SearchCaps>';
		$response_xml .= '</u:GetSearchCapabilitiesResponse>';
		$response_xml .= '</s:Body>';
		$response_xml .= '</s:Envelope>';
	}
	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#GetSortCapabilities"')
	{
		$response_xml .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
		$response_xml .= '<s:Body>';
		$response_xml .= '<u:GetSortCapabilitiesResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$response_xml .= '<SortCaps></SortCaps>';
		$response_xml .= '</u:GetSortCapabilitiesResponse>';
		$response_xml .= '</s:Body>';
		$response_xml .= '</s:Envelope>';
	}
	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#GetSystemUpdateID"')
	{
		$response_xml .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
		$response_xml .= '<s:Body>';
		$response_xml .= '<u:GetSystemUpdateIDResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$response_xml .= '<Id>0</Id>';
		$response_xml .= '</u:GetSystemUpdateIDResponse>';
		$response_xml .= '</s:Body>';
		$response_xml .= '</s:Envelope>';
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
		$response_xml .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
		$response_xml .= '<s:Body>';
		$response_xml .= '<u:X_GetIndexfromRIDResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$response_xml .= '<Index>0</Index>'; # we are setting it to 0 - so take the first item in the list to be active
		$response_xml .= '</u:X_GetIndexfromRIDResponse>';
		$response_xml .= '</s:Body>';
		$response_xml .= '</s:Envelope>';
	}
#	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#X_SetBookmark"')
#	{
#		PDLNA::Log::log('Handling X_SetBookmark request.', 2, 'httpdir');
#		if (defined($xml->{'s:Body'}->{'u:Browse'}->{'ObjectID'}) && defined($xml->{'s:Body'}->{'u:Browse'}->{'PosSecond'}))
#		{
#			my $device_ip_id = PDLNA::Devices::get_device_ip_id_by_device_ip($dbh, $peer_ip_addr);
#			if (defined($device_ip_id))
#			{
#				my @device_bm = ();
#				PDLNA::Database::select_db(
#					$dbh,
#					{
#						'query' => 'SELECT pos_seconds FROM device_bm WHERE item_id_ref = ? AND device_ip_ref = ?',
#						'parameters' => [ $xml->{'s:Body'}->{'u:Browse'}->{'ObjectID'}, $device_ip_id, ],
#					},
#					\@device_bm,
#				);
#
#				if (defined($device_bm[0]->{pos_seconds}))
#				{
#					PDLNA::Database::update_db(
#						$dbh,
#						{
#							'query' => 'UPDATE device_bm SET pos_seconds = ? WHERE item_id_ref = ? AND device_ip_ref = ?',
#							'parameters' => [ $xml->{'s:Body'}->{'u:Browse'}->{'PosSecond'}, $xml->{'s:Body'}->{'u:Browse'}->{'ObjectID'}, $device_ip_id, ],
#						}
#					);
#				}
#				else
#				{
#					PDLNA::Database::insert_db(
#						$dbh,
#						{
#							'query' => 'INSERT INTO device_bm (item_id_ref, device_ip_ref, pos_seconds) VALUES (?,?,?)',
#							'parameters' => [ $xml->{'s:Body'}->{'u:Browse'}->{'ObjectID'}, $device_ip_id, $xml->{'s:Body'}->{'u:Browse'}->{'PosSecond'}, ],
#						}
#					);
#				}
#
#				$response_xml .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
#				$response_xml .= '<s:Body>';
#				$response_xml .= '<u:X_SetBookmarkResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
#				$response_xml .= '</u:X_SetBookmarkResponse>';
#				$response_xml .= '</s:Body>';
#				$response_xml .= '</s:Envelope>';
#			}
#			else
#			{
#				PDLNA::Log::log('Unable to find matching entry in device_ip table.', 2, 'httpdir');
#				return http_header({
#					'statuscode' => 501,
#					'content_type' => 'text/plain',
#				});
#			}
#		}
#		else
#		{
#			PDLNA::Log::log('Missing ObjectID or PosSecond parameter.', 2, 'httpdir');
#			return http_header({
#				'statuscode' => 501,
#				'content_type' => 'text/plain',
#			});
#		}
#	}
	else
	{
		PDLNA::Log::log('ERROR: Action '.$action.' is NOT supported yet.', 0, 'httpdir');
		return http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
		});
	}

	#
	# RETURN THE ANSWER
	#
	my $response = undef;
	if (defined($response_xml))
	{
		$response = http_header({
			'statuscode' => 200,
			'log' => 'httpdir',
			'content_length' => length($response_xml),
			'content_type' => 'text/xml; charset=utf8',
		});
		$response .= $response_xml;
		PDLNA::Log::log('Response: '.$response, 3, 'httpdir');
	}
	else
	{
		PDLNA::Log::log('ERROR: No Response.', 0, 'httpdir');
		$response = http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
		});
	}
	return $response;
}

#
#
# END OF DIRECTORY CONTROLS
#
#

#
#
# BEGINNING OF DELIVERING ITEMS
#
#

#
# NEW:
#
sub stream_item
{
	my $item_id = shift;
	my $method = shift;
	my $CGI = shift;
	my $FH = shift;
	my $model_name = shift;

	#
	# sanity check for ID
	#
	if ($item_id =~ /^(\d+)\.(\w+)$/)
	{
		$item_id = $1; # cut off the file_extension
	}
	else
	{
		PDLNA::Log::log('ERROR: ID '.$item_id.' for streaming items is NOT supported yet.', 0, 'httpstream');
		print $FH http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
			'log' => 'httpstream',
		});
		return;
	}

	#
	# getting information from database
	#
	my $dbh = PDLNA::Database::connect();
	my @item = PDLNA::ContentLibrary::get_item_by_id($dbh, $item_id, [ 'item_type', 'media_type', 'mime_type', 'fullname', 'title', 'size', 'duration' ]);
	my @subtitles = PDLNA::ContentLibrary::get_subtitles_by_refid($dbh, $item_id);
	PDLNA::Database::disconnect($dbh);

	#
	# sanity check for media item
	#
	unless (defined($item[0]->{fullname}))
	{
		PDLNA::Log::log('ERROR: Item with ID '.$item_id.' NOT found (in media library).', 0, 'httpstream');
		print $FH http_header({
			'statuscode' => 404,
			'content_type' => 'text/plain',
			'log' => 'httpstream',
		});
		return;
	}
	unless (-f $item[0]->{fullname})
	{
		PDLNA::Log::log('ERROR: Item with ID '.$item_id.' NOT found (on filesystem): '.$item[0]->{fullname}.'.', 0, 'httpstream');
		print $FH http_header({
			'statuscode' => 404,
			'content_type' => 'text/plain',
			'log' => 'httpstream',
		});
		return;
	}

	#
	# parse HTTP Header
	#
	my @additional_header = ();
	push(@additional_header, 'Content-Type: '.PDLNA::Media::get_mimetype_by_modelname($item[0]->{mime_type}, $model_name));
	push(@additional_header, 'Content-Length: '.$item[0]->{size});
	push(@additional_header, 'Content-Disposition: attachment; filename="'.$item[0]->{title}.'"');
	push(@additional_header, 'Accept-Ranges: bytes');

	my $dlna_contentfeatures = PDLNA::Media::get_dlnacontentfeatures($item[0]);

	unless (handle_getcontentfeatures_header($CGI, \@additional_header, $dlna_contentfeatures))
	{
		PDLNA::Log::log('ERROR: Invalid contentFeatures.dlna.org:'.$$CGI{'GETCONTENTFEATURES.DLNA.ORG'}.'.', 0, 'httpstream');
		print $FH http_header({
			'statuscode' => 400,
			'content_type' => 'text/plain',
			'log' => 'httpstream',
		});
		return;
	}

	unless (handle_getcaptioninfo_header($CGI, \@additional_header, $item[0]->{media_type}, \@subtitles, $dlna_contentfeatures))
	{
		PDLNA::Log::log('ERROR: Invalid getCaptionInfo.sec:'.$$CGI{'GETCAPTIONINFO.SEC'}.'.', 0, 'httpstream');
		print $FH http_header({
			'statuscode' => 400,
			'content_type' => 'text/plain',
			'log' => 'httpstream',
		});
		return;
	}

	unless (handle_getmediainfosec_header($CGI, \@additional_header, $item[0]->{media_type}, $item[0]->{duration}, $dlna_contentfeatures))
	{
		PDLNA::Log::log('ERROR: Invalid getMediaInfo.sec:'.$$CGI{'GETMEDIAINFO.SEC'}.'.', 0, 'httpstream');
		print $FH http_header({
			'statuscode' => 400,
			'content_type' => 'text/plain',
			'log' => 'httpstream',
		});
		return;
	}

	#
	#
	#
	if ($method eq 'HEAD') # handling HEAD requests
	{
		PDLNA::Log::log('Delivering content information (HEAD Request) for: '.$item[0]->{title}.'.', 1, 'httpstream');
		print $FH http_header({
			'statuscode' => 200,
			'additional_header' => \@additional_header,
			'log' => 'httpstream',
		});
	}
	elsif ($method eq 'GET') # handling GET requests
	{
		unless (handle_transfermode_header($CGI, \@additional_header))
		{
			PDLNA::Log::log('ERROR: Invalid Transfermode:'.$$CGI{'TRANSFERMODE.DLNA.ORG'}.'.', 0, 'httpstream');
			print $FH http_header({
				'statuscode' => 400,
				'content_type' => 'text/plain',
				'log' => 'httpstream',
			});
			return;
		}

		#
		#
		#
		if ($$CGI{'TRANSFERMODE.DLNA.ORG'} eq 'Streaming') # for immediate rendering of audio or video content
		{
			my $statuscode = 200;
			my ($lowrange, $highrange) = 0;
			if (
					defined($$CGI{'RANGE'}) &&						# if RANGE is defined as HTTP header
					$$CGI{'RANGE'} =~ /^bytes=(\d+)-(\d*)$/			# if RANGE looks like
				)
			{
				PDLNA::Log::log('Delivering content for: '.$item[0]->{fullname}.' with RANGE Request.', 1, 'httpstream');
				$statuscode = 206;

				$lowrange = int($1);
				$highrange = $2 ? int($2) : 0;
				$highrange = $item[0]->{size}-1 if $highrange == 0;
				$highrange = $item[0]->{size}-1 if $highrange >= $item[0]->{size};

				my $bytes_to_ship = $highrange - $lowrange + 1;

				$additional_header[1] = 'Content-Length: '.$bytes_to_ship; # we need to change the Content-Length
				push(@additional_header, 'Content-Range: bytes '.$lowrange.'-'.$highrange.'/'.$item[0]->{size});
			}

			sysopen(ITEM, $item[0]->{fullname}, O_RDONLY);
			sysseek(ITEM, $lowrange, 0) if $lowrange;

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
			# Delivering interactive content as a whole
			print $FH http_header({
				'statuscode' => 200,
				'additional_header' => \@additional_header,
				'log' => 'httpstream',
			});
			sysopen(FILE, $item[0]->{fullname}, O_RDONLY);
			print $FH <FILE>;
			close(FILE);
			return;
		}
		elsif ($$CGI{'TRANSFERMODE.DLNA.ORG'} eq 'Background') # for subtitles
		{
			# Delivering background content as a whole
			print $FH http_header({
				'statuscode' => 200,
				'additional_header' => \@additional_header,
				'log' => 'httpstream',
			});
			sysopen(FILE, $item[0]->{fullname}, O_RDONLY);
			print $FH <FILE>;
			close(FILE);
		}
	}
	else
	{
		PDLNA::Log::log('ERROR: HTTP Method '.$method.' for streaming items is NOT supported yet.', 0, 'httpstream');
		print $FH http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
			'log' => 'httpstream',
		});
	}
}

#
# NEW:
#
sub handle_transfermode_header
{
	my $CGI = shift;
	my $additional_header = shift;

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
		if ($$CGI{'TRANSFERMODE.DLNA.ORG'} =~ /^Streaming|Interactive|Background$/)
		{
			push(@{$additional_header}, 'transferMode.dlna.org: '.$$CGI{'TRANSFERMODE.DLNA.ORG'});
			return 1;
		}
	}
	return 0;
}

#
# NEW:
#
sub handle_getmediainfosec_header
{
	my $CGI = shift;
	my $additional_header = shift;
	my $media_type = shift;
	my $seconds = shift;
	my $dlna_contentfeatures = shift;

	if (defined($$CGI{'GETMEDIAINFO.SEC'}))
	{
		if ($$CGI{'GETMEDIAINFO.SEC'} == 1)
		{
			if ($media_type eq 'video' || $media_type eq 'audio')
			{
				push(@{$additional_header}, 'MediaInfo.sec: SEC_Duration='.$seconds.'000;'); # in milliseconds
			}

			unless (grep(/^contentFeatures.dlna.org:/, @{$additional_header}))
			{
				push(@{$additional_header}, 'contentFeatures.dlna.org: '.$dlna_contentfeatures);
			}
		}
		else
		{
			return 0;
		}
	}
	return 1;
}

#
# NEW:
#
sub handle_getcaptioninfo_header
{
	my $CGI = shift;
	my $additional_header = shift;
	my $media_type = shift;
	my $subtitles = shift;
	my $dlna_contentfeatures = shift;

	if (defined($$CGI{'GETCAPTIONINFO.SEC'}))
	{
		if ($$CGI{'GETCAPTIONINFO.SEC'} == 1)
		{
			if ($media_type eq 'video')
			{
				foreach my $subtitle (@{$subtitles})
				{
					if ($subtitle->{media_type} eq 'srt' && -f $subtitle->{fullname})
					{
						my $url = 'http://'.$CONFIG{'LOCAL_IPADDR'}.':'.$CONFIG{'HTTP_PORT'}.'/media/'.$subtitle->{id}.'.srt';
						push(@{$additional_header}, 'CaptionInfo.sec: '.$url);
					}
				}
			}

			unless (grep(/^contentFeatures.dlna.org:/, @{$additional_header}))
			{
				push(@{$additional_header}, 'contentFeatures.dlna.org: '.$dlna_contentfeatures);
			}
		}
		else
		{
			return 0;
		}
	}
	return 1;
}

#
# NEW:
# Streaming of content is NOT working with SAMSUNG without this response header
#
sub handle_getcontentfeatures_header
{
	my $CGI = shift;
	my $additional_header = shift;
	my $dlna_contentfeatures = shift;

	if (defined($$CGI{'GETCONTENTFEATURES.DLNA.ORG'}))
	{
		if ($$CGI{'GETCONTENTFEATURES.DLNA.ORG'} == 1)
		{
			push(@{$additional_header}, 'contentFeatures.dlna.org: '.$dlna_contentfeatures);
		}
		else
		{
			return 0;
		}
	}
	return 1;
}




















sub preview_media
{
	my $item_id = shift;

	#
	# sanity check for ID
	#
	if ($item_id =~ /^(\d+)\.(\w+)$/)
	{
		$item_id = $1; # cut off the file_extension
	}
	else
	{
		PDLNA::Log::log('ERROR: ID '.$item_id.' for preview items is NOT supported yet.', 0, 'httpstream');
		return http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
			'log' => 'httpstream',
		});
	}


	#
	# getting information from database
	#
	my $dbh = PDLNA::Database::connect();
	my @item = PDLNA::ContentLibrary::get_item_by_id($dbh, $item_id, [ 'media_type', 'fullname' ]);
	PDLNA::Database::disconnect($dbh);

	#
	# sanity check for media item
	#
	unless (defined($item[0]->{fullname}))
	{
		PDLNA::Log::log('ERROR: Item with ID '.$item_id.' NOT found (in media library).', 0, 'httpstream');
		return http_header({
			'statuscode' => 404,
			'content_type' => 'text/plain',
			'log' => 'httpstream',
		});
	}
	unless (-f $item[0]->{fullname})
	{
		PDLNA::Log::log('ERROR: Item with ID '.$item_id.' NOT found (on filesystem): '.$item[0]->{fullname}.'.', 0, 'httpstream');
		return http_header({
			'statuscode' => 404,
			'content_type' => 'text/plain',
			'log' => 'httpstream',
		});
	}

	if ($item[0]->{media_type} eq 'audio')
	{
		PDLNA::Log::log('ERROR: Delivering preview for audio item is NOT supported yet.', 0, 'httpstream');
		return http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
			'log' => 'httpstream',
		});
	}

	#
	#
	#
	PDLNA::Log::log('Delivering preview for: '.$item[0]->{fullname}.'.', 2, 'httpstream');

	my $randid = '';
	my $path = $item[0]->{fullname};
	if ($item[0]->{media_type} eq 'video') # we need to create the thumbnail
	{
		$randid = $CONFIG{'PROGRAM_NAME'}.'-'.PDLNA::Utils::get_randid();
		mkdir($CONFIG{'TMP_DIR'}.'/'.$randid);
		my $thumbnail_path = $CONFIG{'TMP_DIR'}.'/'.$randid.'/thumbnail.jpg';
		system($CONFIG{'FFMPEG_BIN'}.' -y -ss 20 -i "'.$path.'" -vcodec mjpeg -vframes 1 -an -f rawvideo "'.$thumbnail_path.'" > /dev/null 2>&1');

		$path = $thumbnail_path;
		unless (-f $path)
		{
			PDLNA::Log::log('ERROR: Unable to create image for item preview.', 0, 'httpstream');
			return http_header({
				'statuscode' => 404,
				'content_type' => 'text/plain',
				'log' => 'httpstream',
			});
		}
	}

	# image scaling stuff
	GD::Image->trueColor(1);
	my $image = GD::Image->new($path);
	$image = newFromJpeg GD::Image($path) unless ($image); # if  GD::Image->new doesn't work, try newFromJpeg

	unless ($image) # and if both ways did not work
	{
		PDLNA::Log::log('ERROR: Unable to create GD::Image object for item preview.', 0, 'httpstream');
		return http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
			'log' => 'httpstream',
		});
	}
	my $height = $image->height / ($image->width/160);
	my $preview = GD::Image->new(160, $height);
	$preview->copyResampled($image, 0, 0, 0, 0, 160, $height, $image->width, $image->height);

	# remove tmp files from thumbnail generation
	if ($item[0]->{media_type} eq 'video')
	{
		unlink($path);
		rmdir("$CONFIG{'TMP_DIR'}/$randid"); # TODO Windows specific
	}

	# the response itself
	my $response = http_header({
		'statuscode' => 200,
		'content_type' => 'image/jpeg',
		'log' => 'httpstream',
	});
	$response .= $preview->jpeg();
	$response .= "\r\n";

	return $response;
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
		my $image = GD::Image->new('../lib/perl5/PDLNA/pDLNA.png');
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

__END__

sub stream_media_beta
{
	my $content_id = shift;
	my $method = shift;
	my $CGI = shift;
	my $FH = shift;
	my $model_name = shift;
	my $client_ip = shift;
	my $user_agent = shift;

	#
	# ContentID verification
	#
	my $id = 0;
	if ($content_id =~ /^(\d+)\.(\w+)$/)
	{
		$id = $1;
	}
	else
	{
		PDLNA::Log::log('ERROR: ContentID '.$content_id.' for Streaming Items is NOT supported yet.', 0, 'httpstream');
		print $FH http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
			'log' => 'httpstream',
		});
		close(FILE);
		return;
	}
	PDLNA::Log::log('Found ContentID in streaming request: '.$id, 3, 'httpstream');

	#
	# getting information from database
	#
	my $dbh = PDLNA::Database::connect();

	my @item = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT NAME,FULLNAME,PATH,FILE_EXTENSION,SIZE,MIME_TYPE,TYPE,EXTERNAL FROM FILES WHERE ID = ?',
			'parameters' => [ $id, ],
		},
		\@item,
	);

	my @iteminfo = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT CONTAINER, AUDIO_CODEC, VIDEO_CODEC, DURATION FROM FILEINFO WHERE FILEID_REF = ?;',
			'parameters' => [ $id, ],
		},
		\@iteminfo,
	);

	my @subtitles = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT id, type, fullname FROM subtitles WHERE fileid_ref = ?',
			'parameters' => [ $id, ],
		},
		\@subtitles,
	);

	PDLNA::Database::disconnect($dbh);

	#
	# TODO sanity checks for file
	#

	my $transcode = 0;


	#
	# TODO HTTP response header
	#

	my @additional_header = ();
	push(@additional_header, 'Content-Type: '.PDLNA::Media::get_mimetype_by_modelname($item[0]->{MIME_TYPE}, $model_name));
	push(@additional_header, 'Content-Length: '.$item[0]->{SIZE}) if !$item[0]->{EXTERNAL}; # TODO
	push(@additional_header, 'Content-Disposition: attachment; filename="'.$item[0]->{NAME}.'"') if !$item[0]->{EXTERNAL};
	push(@additional_header, 'Accept-Ranges: bytes'); # TODO

	#
	# contentFeatures.dlna.org
	# Streaming of content is NOT working with SAMSUNG without this response header
	#
	if (defined($$CGI{'GETCONTENTFEATURES.DLNA.ORG'}))
	{
		if ($$CGI{'GETCONTENTFEATURES.DLNA.ORG'} == 1)
		{
			push(@additional_header, 'contentFeatures.dlna.org: '.PDLNA::Media::get_dlnacontentfeatures($item[0], $transcode));
		}
		else
		{
			PDLNA::Log::log('Invalid contentFeatures.dlna.org:'.$$CGI{'GETCONTENTFEATURES.DLNA.ORG'}.'.', 1, 'httpstream');
			print $FH http_header({
				'statuscode' => 400,
				'content_type' => 'text/plain',
			});
			close(FILE);
			return;
		}
	}

	#
	# SUBTITLES
	#
	if (defined($$CGI{'GETCAPTIONINFO.SEC'}))
	{
		if ($$CGI{'GETCAPTIONINFO.SEC'} == 1)
		{
			if ($item[0]->{TYPE} eq 'video')
			{
				foreach my $subtitle (@subtitles)
				{
					if ($subtitle->{type} eq 'srt' && -f $subtitle->{fullname})
					{
						push(@additional_header, 'CaptionInfo.sec: http://'.$CONFIG{'LOCAL_IPADDR'}.':'.$CONFIG{'HTTP_PORT'}.'/subtitle/'.$subtitle->{id}.'.srt');
					}
				}
			}

			unless (grep(/^contentFeatures.dlna.org:/, @additional_header))
			{
				push(@additional_header, 'contentFeatures.dlna.org: '.PDLNA::Media::get_dlnacontentfeatures($item[0], $transcode));
			}
		}
		else
		{
			PDLNA::Log::log('Invalid getCaptionInfo.sec:'.$$CGI{'GETCAPTIONINFO.SEC'}.'.', 1, 'httpstream');
			print $FH http_header({
				'statuscode' => 400,
				'content_type' => 'text/plain',
			});
			close(FILE);
			return;
		}
	}

	#
	# DURATION
	#
	if (defined($$CGI{'GETMEDIAINFO.SEC'}))
	{
		if ($$CGI{'GETMEDIAINFO.SEC'} == 1)
		{
			if ($item[0]->{TYPE} eq 'video' || $item[0]->{TYPE} eq 'audio')
			{
				push(@additional_header, 'MediaInfo.sec: SEC_Duration='.$iteminfo[0]->{DURATION}.'000;'); # in milliseconds

				unless (grep(/^contentFeatures.dlna.org:/, @additional_header))
				{
					push(@additional_header, 'contentFeatures.dlna.org: '.PDLNA::Media::get_dlnacontentfeatures($item[0], $transcode));
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
			close(FILE);
			return;
		}
	}

	#
	# HANDLING THE THE REQUESTS
	#

	if ($method eq 'HEAD') # handling HEAD requests
	{
		PDLNA::Log::log('Delivering content information (HEAD Request) for: '.$item[0]->{NAME}.'.', 1, 'httpstream');

		print $FH http_header({
			'statuscode' => 200,
			'additional_header' => \@additional_header,
			'log' => 'httpstream',
		});
		close(FILE);
		return;
	}
	elsif ($method eq 'GET') # handling GET requests
	{
		# for clients, which are not sending the Streaming value for the transferMode.dlna.org parameter
		# we set it, because they seem to ignore it
		my @useragents = (
			'foobar2000', # since foobar2000 is NOT sending any TRANSFERMODE.DLNA.ORG param
			'vlc*', # since vlc is NOT sending any TRANSFERMODE.DLNA.ORG param
			'stagefright', # since UPnPlay is NOT sending any TRANSFERMODE.DLNA.ORG param
			'gvfs', # since Totem Movie Player is NOT sending any TRANSFERMODE.DLNA.ORG param
			'(null)',
		);
		if (defined($$CGI{'USER-AGENT'}))
		{
			foreach my $ua (@useragents)
			{
				$$CGI{'TRANSFERMODE.DLNA.ORG'} = 'Streaming' if $$CGI{'USER-AGENT'} =~ /^$ua/i;
			}
		}

		#
		# transferMode handling
		#
		if (defined($$CGI{'TRANSFERMODE.DLNA.ORG'}))
		{
			if ($$CGI{'TRANSFERMODE.DLNA.ORG'} eq 'Streaming') # for immediate rendering of audio or video content
			{
				push(@additional_header, 'transferMode.dlna.org: Streaming');

				if (defined($$CGI{'TIMESEEKRANGE.DLNA.ORG'}) && $$CGI{'TIMESEEKRANGE.DLNA.ORG'} =~ /^npt=(\d+)-(\d*)/)
				{
					PDLNA::Log::log('Delivering content for: '.$item[0]->{FULLNAME}.' with TIMESEEKRANGE request.', 1, 'httpstream');

					my $startseek = $1 ? $1 : 0;
					my $endseek = $2 ? $2 : $iteminfo[0]->{DURATION};





					push(@additional_header, 'TimeSeekRange.dlna.org: npt='.PDLNA::Utils::convert_duration($startseek).'-'.PDLNA::Utils::convert_duration($endseek).'/'.PDLNA::Utils::convert_duration($iteminfo[0]->{DURATION}));
					push(@additional_header, 'X-Seek-Range: npt='.PDLNA::Utils::convert_duration($startseek).'-'.PDLNA::Utils::convert_duration($endseek).'/'.PDLNA::Utils::convert_duration($iteminfo[0]->{DURATION}));





					my $command = $CONFIG{'FFMPEG_BIN'}.' -y -ss '.$1.' -i "'.$item[0]->{FULLNAME}.'" -vcodec copy -acodec copy -f avi pipe:';

					my $statuscode = 200;
					#@additional_header = map { /^(Content-Length|Accept-Ranges):/i ? () : $_ } @additional_header; # delete some header
					@additional_header = map { /^(Accept-Ranges):/i ? () : $_ } @additional_header; # delete some header

					open(ITEM, '-|', $command);
					binmode(ITEM);

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





				}
				else
				{

















#				if ($CONFIG{'LOW_RESOURCE_MODE'})
#				{
					my $statuscode = 200;
					my ($lowrange, $highrange) = 0;
					if (defined($$CGI{'RANGE'}) && $$CGI{'RANGE'} =~ /^bytes=(\d+)-(\d*)$/)
					{
						PDLNA::Log::log('Delivering content for: '.$item[0]->{FULLNAME}.' with RANGE request.', 1, 'httpstream');
						my $statuscode = 206;

						$lowrange = int($1);
						$highrange = $2 ? int($2) : 0;
						$highrange = $item[0]->{SIZE}-1 if $highrange == 0;
						$highrange = $item[0]->{SIZE}-1 if ($highrange >= $item[0]->{SIZE});

						my $bytes_to_ship = $highrange - $lowrange + 1;

						$additional_header[1] = 'Content-Length: '.$bytes_to_ship; # we need to change the Content-Length
						push(@additional_header, 'Content-Range: bytes '.$lowrange.'-'.$highrange.'/'.$item[0]->{SIZE});
					}

					sysopen(ITEM, $item[0]->{FULLNAME}, O_RDONLY);
					sysseek(ITEM, $lowrange, 0) if $lowrange;

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
				}
#				else
#				{
#					my $statuscode = 200;
#					my $command = $CONFIG{'FFMPEG_BIN'}.' -i '.$item[0]->{FULLNAME}.' -acodec copy -f mp3 pipe:';
#					#@additional_header = map { /^(Content-Length|Accept-Ranges):/i ? () : $_ } @additional_header; # delete some header
#					@additional_header = map { /^(Accept-Ranges):/i ? () : $_ } @additional_header; # delete some header
#
#					open(ITEM, '-|', $command);
#					binmode(ITEM);
#
#					print $FH http_header({
#						'statuscode' => $statuscode,
#						'additional_header' => \@additional_header,
#						'log' => 'httpstream',
#					});
#					my $buf = undef;
#					while (sysread(ITEM, $buf, $CONFIG{'BUFFER_SIZE'}))
#					{
#						PDLNA::Log::log('Adding '.bytes::length($buf).' bytes to Streaming connection.', 3, 'httpstream');
#						print $FH $buf or return 1;
#					}
#					close(ITEM);
#				}
#


















				close($FH);
				return;
			}
			elsif ($$CGI{'TRANSFERMODE.DLNA.ORG'} eq 'Interactive') # for immediate rendering of images or playlist files
			{
				PDLNA::Log::log('Delivering (Interactive) content for: '.$item[0]->{FULLNAME}.'.', 1, 'httpstream');
				push(@additional_header, 'transferMode.dlna.org: Interactive');

				# Delivering interactive content as a whole
				print $FH http_header({
					'statuscode' => 200,
					'additional_header' => \@additional_header,
				});
				sysopen(FILE, $item[0]->{FULLNAME}, O_RDONLY);
				print $FH <FILE>;
				close(FILE);
				return;
			}
			else # unknown TRANSFERMODE.DLNA.ORG is set
			{
				PDLNA::Log::log('ERROR: Transfermode '.$$CGI{'TRANSFERMODE.DLNA.ORG'}.' for Streaming Items is NOT supported yet.', 0, 'httpstream');
				print $FH http_header({
					'statuscode' => 501,
					'content_type' => 'text/plain',
				});
				close(FILE);
				return;
			}
		}
		else # no TRANSFERMODE.DLNA.ORG is set
		{
			PDLNA::Log::log('Delivering content information (no Transfermode) for: '.$item[0]->{FULLNAME}.'.', 1, 'httpstream');
			print $FH http_header({
				'statuscode' => 200,
				'additional_header' => \@additional_header,
				'log' => 'httpstream',
			});
			close(FILE);
			return;
		}
	}
	else # unknown HTTP METHOD is set
	{
		PDLNA::Log::log('ERROR: HTTP Method '.$method.' for Streaming Items is NOT supported yet.', 0, 'httpstream');
		print $FH http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
			'log' => 'httpstream',
		});
		close(FILE);
		return;
	}
}

sub stream_media_old # with old db scheme
{
	my $content_id = shift;
	my $method = shift;
	my $CGI = shift;
	my $FH = shift;
	my $model_name = shift;
	my $client_ip = shift;
	my $user_agent = shift;

	my $dbh = PDLNA::Database::connect();

	PDLNA::Log::log('ContentID: '.$content_id, 3, 'httpstream');
	if ($content_id =~ /^(\d+)\.(\w+)$/)
	{
		my $id = $1;
		PDLNA::Log::log('ID: '.$id, 3, 'httpstream');

		#
		# getting information from database
		#
		my @item = ();
		PDLNA::Database::select_db(
			$dbh,
			{
				'query' => 'SELECT NAME,FULLNAME,PATH,FILE_EXTENSION,SIZE,MIME_TYPE,TYPE,EXTERNAL FROM FILES WHERE ID = ?',
				'parameters' => [ $id, ],
			},
			\@item,
		);

		my @iteminfo = ();
		PDLNA::Database::select_db(
			$dbh,
			{
				'query' => 'SELECT CONTAINER, AUDIO_CODEC, VIDEO_CODEC FROM FILEINFO WHERE FILEID_REF = ?;',
				'parameters' => [ $id, ],
			},
			\@iteminfo,
		);

		#
		# check if we need to transcode
		#
		my %media_data = (
			'fullname' => $item[0]->{FULLNAME},
			'external' => $item[0]->{EXTERNAL},
			'media_type' => $item[0]->{TYPE},
			'container' => $iteminfo[0]->{CONTAINER},
			'audio_codec' => $iteminfo[0]->{AUDIO_CODEC},
			'video_codec' => $iteminfo[0]->{VIDEO_CODEC},
		);
		my $transcode = 0;
		if ($transcode = PDLNA::FFmpeg::shall_we_transcode(
				\%media_data,
				{
					'ip' => $client_ip,
					'user_agent' => $user_agent,
				},
			))
		{
			$item[0]->{MIME_TYPE} = $media_data{'mime_type'};
		}

		#
		# sanity checks
		#
		unless (defined($item[0]->{FULLNAME}))
		{
			PDLNA::Log::log('Content with ID '.$id.' NOT found (in media library).', 1, 'httpstream');
			print $FH http_header({
				'statuscode' => 404,
				'content_type' => 'text/plain',
				'log' => 'httpstream',
			});
			return;
		}

		if (!$item[0]->{EXTERNAL} && !-f $item[0]->{FULLNAME})
		{
			PDLNA::Log::log('Content with ID '.$id.' NOT found (on filesystem): '.$item[0]->{FULLNAME}.'.', 1, 'httpstream');
			print $FH http_header({
				'statuscode' => 404,
				'content_type' => 'text/plain',
				'log' => 'httpstream',
			});
			return;
		}

		if ($item[0]->{EXTERNAL} && !PDLNA::Media::is_supported_stream($item[0]->{FULLNAME}) && !-x $item[0]->{FULLNAME})
		{
			PDLNA::Log::log('Content with ID '.$id.' is a SCRIPT but NOT executable: '.$item[0]->{FULLNAME}.'.', 1, 'httpstream');
			print $FH http_header({
				'statuscode' => 404,
				'content_type' => 'text/plain',
				'log' => 'httpstream',
			});
			return;
		}

		#
		# for streaming relevant code starts here
		#

		my @additional_header = ();
		push(@additional_header, 'Content-Type: '.PDLNA::Media::get_mimetype_by_modelname($item[0]->{MIME_TYPE}, $model_name));
		push(@additional_header, 'Content-Length: '.$item[0]->{SIZE}) if !$item[0]->{EXTERNAL};
		push(@additional_header, 'Content-Disposition: attachment; filename="'.$item[0]->{NAME}.'"') if !$item[0]->{EXTERNAL};
		push(@additional_header, 'Accept-Ranges: bytes'); # TODO

		# Streaming of content is NOT working with SAMSUNG without this response header
		if (defined($$CGI{'GETCONTENTFEATURES.DLNA.ORG'}))
		{
			if ($$CGI{'GETCONTENTFEATURES.DLNA.ORG'} == 1)
		{
				push(@additional_header, 'contentFeatures.dlna.org: '.PDLNA::Media::get_dlnacontentfeatures($item[0], $transcode));
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

		# subtitles
		if (defined($$CGI{'GETCAPTIONINFO.SEC'}))
		{
			if ($$CGI{'GETCAPTIONINFO.SEC'} == 1)
			{
				if ($item[0]->{TYPE} eq 'video')
				{
					my @subtitles = ();
					PDLNA::Database::select_db(
						$dbh,
						{
							'query' => 'SELECT id, type, fullname FROM subtitles WHERE fileid_ref = ?',
							'parameters' => [ $id, ],
						},
						\@subtitles,
					);
					foreach my $subtitle (@subtitles)
					{
						if ($subtitle->{type} eq 'srt' && -f $subtitle->{fullname})
						{
							push(@additional_header, 'CaptionInfo.sec: http://'.$CONFIG{'LOCAL_IPADDR'}.':'.$CONFIG{'HTTP_PORT'}.'/subtitle/'.$subtitle->{id}.'.srt');
						}
					}
				}

				unless (grep(/^contentFeatures.dlna.org:/, @additional_header))
				{
					push(@additional_header, 'contentFeatures.dlna.org: '.PDLNA::Media::get_dlnacontentfeatures($item[0], $transcode));
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

		# duration
		if (defined($$CGI{'GETMEDIAINFO.SEC'}))
		{
			if ($$CGI{'GETMEDIAINFO.SEC'} == 1)
			{
				if ($item[0]->{TYPE} eq 'video' || $item[0]->{TYPE} eq 'audio')
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
						push(@additional_header, 'contentFeatures.dlna.org: '.PDLNA::Media::get_dlnacontentfeatures($item[0], $transcode));
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
			PDLNA::Log::log('Delivering content information (HEAD Request) for: '.$item[0]->{NAME}.'.', 1, 'httpstream');

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

			# transferMode handling
			if (defined($$CGI{'TRANSFERMODE.DLNA.ORG'}))
			{
				if ($$CGI{'TRANSFERMODE.DLNA.ORG'} eq 'Streaming') # for immediate rendering of audio or video content
				{
					push(@additional_header, 'transferMode.dlna.org: Streaming');

					my $statuscode = 200;
					my ($lowrange, $highrange) = 0;
					if (
							defined($$CGI{'RANGE'}) &&						# if RANGE is defined as HTTP header
							$$CGI{'RANGE'} =~ /^bytes=(\d+)-(\d*)$/ &&		# if RANGE looks like
							!$item[0]->{EXTERNAL} &&						# if FILE is not external
							!$transcode										# if TRANSCODING is not required
						)
					{
						PDLNA::Log::log('Delivering content for: '.$item[0]->{FULLNAME}.' with RANGE Request.', 1, 'httpstream');
						my $statuscode = 206;

						$lowrange = int($1);
						$highrange = $2 ? int($2) : 0;
						$highrange = $item[0]->{SIZE}-1 if $highrange == 0;
						$highrange = $item[0]->{SIZE}-1 if ($highrange >= $item[0]->{SIZE});

						my $bytes_to_ship = $highrange - $lowrange + 1;

						$additional_header[1] = 'Content-Length: '.$bytes_to_ship; # we need to change the Content-Length
						push(@additional_header, 'Content-Range: bytes '.$lowrange.'-'.$highrange.'/'.$item[0]->{SIZE});
					}

					#
					# sending the response
					#
					if (!$item[0]->{EXTERNAL} && !$transcode) # file on disk or TRANSFERMODE is NOT required
					{
						sysopen(ITEM, $item[0]->{FULLNAME}, O_RDONLY);
						sysseek(ITEM, $lowrange, 0) if $lowrange;
					}
					else # streams, scripts, or transcoding
					{
						my $command = '';
						if (PDLNA::Media::is_supported_stream($item[0]->{FULLNAME})) # if it is a supported stream
						{
							$command = PDLNA::FFmpeg::get_ffmpeg_stream_command(\%media_data);
						}
						elsif ($transcode) # if TRANSCODING is required
						{
							$command = $media_data{'command'};
						}
						else # if it is a script
						{
							$command = $item[0]->{FULLNAME};
						}

						open(ITEM, '-|', $command);
						binmode(ITEM);
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
					PDLNA::Log::log('Delivering (Interactive) content for: '.$item[0]->{FULLNAME}.'.', 1, 'httpstream');
					push(@additional_header, 'transferMode.dlna.org: Interactive');

					# Delivering interactive content as a whole
					print $FH http_header({
						'statuscode' => 200,
						'additional_header' => \@additional_header,
					});
					sysopen(FILE, $item[0]->{FULLNAME}, O_RDONLY);
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
				PDLNA::Log::log('Delivering content information (no Transfermode) for: '.$item[0]->{FULLNAME}.'.', 1, 'httpstream');
				print $FH http_header({
					'statuscode' => 200,
					'additional_header' => \@additional_header,
					'log' => 'httpstream',
				});
			}
		}
		else # not implemented HTTP method
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
