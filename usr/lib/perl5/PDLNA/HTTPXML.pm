package PDLNA::HTTPXML;
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2015 Stefan Heumader <stefan@heumader.at>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY, without even the implied warranty of
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
use PDLNA::Database;
use PDLNA::FFmpeg;
use PDLNA::SpecificViews;
use PDLNA::Utils;

sub get_browseresponse_header
{
	my @xml = (
		'<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">',
		'<s:Body>',
		'<u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">',
		'<Result>',
		'&lt;DIDL-Lite xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot;',
		' xmlns:sec=&quot;http://www.sec.co.kr/dlna&quot;',
		' xmlns:dlna=&quot;urn:schemas-dlna-org:metadata-1-0/&quot;',
		' xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot;',
		' xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot;',
		'&gt;',
	);

	return join('', @xml);
}

sub get_browseresponse_footer
{
	my $number_returned = shift;
	my $total_matches = shift;

	my @xml = (
		'&lt;/DIDL-Lite&gt;',
		'</Result>',
		'<NumberReturned>'.PDLNA::Utils::encode_xml($number_returned).'</NumberReturned>',
		'<TotalMatches>'.PDLNA::Utils::encode_xml($total_matches).'</TotalMatches>',
		'<UpdateID>0</UpdateID>',
		'</u:BrowseResponse>',
		'</s:Body>',
		'</s:Envelope>',
	);

	return join('', @xml);
}

sub get_browseresponse_group_specific
{
	my $group_id = shift;
	my $media_type = shift;
	my $group_type = shift;
	my $group_name = shift;
	my $filter = shift;
	my $dbh = shift;

	my $group_elements_amount = PDLNA::SpecificViews::get_amount_of_items($dbh, $media_type, $group_type, $group_id);
	my $group_parent_id = $media_type.'_'.$group_type;

	my @xml = ();
	push(@xml, '&lt;container ');
	push(@xml, 'id=&quot;'.$group_parent_id.'_'.PDLNA::Utils::add_leading_char($group_id, 4, '0').'&quot; ') if grep(/^\@id$/, @{$filter});
	push(@xml, 'parentID=&quot;'.$group_parent_id.'&quot; ') if grep(/^\@parentID$/, @{$filter});
	push(@xml, 'restricted=&quot;1&quot; ') if grep(/^\@restricted$/, @{$filter});
	push(@xml, 'childCount=&quot;'.$group_elements_amount.'&quot;&gt;') if grep(/^\@childCount$/, @{$filter});
	push(@xml, '&lt;dc:title&gt;'.$group_name.'&lt;/dc:title&gt;') if grep(/^dc:title$/, @{$filter});
	push(@xml, '&lt;upnp:class&gt;object.container&lt;/upnp:class&gt;') if grep(/^upnp:class$/, @{$filter});
	push(@xml, '&lt;/container&gt;');

	return join('', @xml);
}

sub get_browseresponse_item_specific
{
	my $item_id = shift;
	my $media_type = shift;
	my $group_type = shift;
	my $group_id = shift;
	my $filter = shift;
	my $dbh = shift;
	my $client_ip = shift;
	my $user_agent = shift;

	my $item_parent_id = $media_type.'_'.$group_type.'_'.PDLNA::Utils::add_leading_char($group_id, 4, '0');

	my @xml = ();
	push(@xml, '&lt;item ');
	push(@xml, 'id=&quot;'.$item_parent_id.'_'.PDLNA::Utils::add_leading_char($item_id, 3, '0').'&quot; ') if grep(/^\@id$/, @{$filter});
	push(@xml, 'parentID=&quot;'.$item_parent_id.'&quot; ') if grep(/^\@parentID$/, @{$filter});

	get_browseresponse_item_detailed($item_id, $filter, $dbh, $client_ip, $user_agent, \@xml);
	return join('', @xml);
}

sub get_browseresponse_container
{
	my $id = shift;
	my $title = shift;
	my $filter = shift;
	my $dbh = shift;

	my $parent_id = PDLNA::ContentLibrary::get_parentid_by_id($dbh, $id);
	my $amount = PDLNA::ContentLibrary::get_amount_size_items_by($dbh, 'parent_id', $id);

	my @xml = ();
	push(@xml, '&lt;container ');
	push(@xml, 'id=&quot;'.PDLNA::Utils::encode_xml($id).'&quot; ') if grep(/^\@id$/, @{$filter});
	push(@xml, 'parentID=&quot;'.PDLNA::Utils::encode_xml($parent_id).'&quot; ') if grep(/^\@parentID$/, @{$filter});
#	searchable=&quot;0&quot;
	push(@xml, 'restricted=&quot;1&quot; ') if grep(/^\@restricted$/, @{$filter});
	push(@xml, 'childCount=&quot;'.PDLNA::Utils::encode_xml($amount).'&quot;&gt;') if grep(/^\@childCount$/, @{$filter});
	push(@xml, '&lt;dc:title&gt;'.PDLNA::Utils::encode_xml($title).'&lt;/dc:title&gt;') if grep(/^dc:title$/, @{$filter});
	push(@xml, '&lt;upnp:class&gt;object.container&lt;/upnp:class&gt;') if grep(/^upnp:class$/, @{$filter});
#	&lt;upnp:objectUpdateID&gt;5&lt;/upnp:objectUpdateID&gt;
#	&lt;sec:initUpdateID&gt;5&lt;/sec:initUpdateID&gt;
#	&lt;sec:classCount class=&quot;object.container&quot;&gt;0&lt;/sec:classCount&gt;
#	&lt;sec:classCount class=&quot;object.item.imageItem&quot;&gt;0&lt;/sec:classCount&gt;
#	&lt;sec:classCount class=&quot;object.item.audioItem&quot;&gt;0&lt;/sec:classCount&gt;
#	&lt;sec:classCount class=&quot;object.item.videoItem&quot;&gt;0&lt;/sec:classCount&gt;
	push(@xml, '&lt;/container&gt;');

	return join('', @xml);
}

sub get_browseresponse_item
{
	my $id = shift;
	my $filter = shift;
	my $dbh = shift;
	my $client_ip = shift;
	my $user_agent = shift;

	my @xml = ();

	push(@xml, '&lt;item ');
	push(@xml, 'id=&quot;'.PDLNA::Utils::encode_xml($id).'&quot; ') if grep(/^\@id$/, @{$filter});
	get_browseresponse_item_detailed($id, $filter, $dbh, $client_ip, $user_agent, \@xml);
	push(@xml, '&lt;/item&gt;');

	return join('', @xml);
}

sub get_browseresponse_item_detailed
{
	my $id = shift;
	my $filter = shift;
	my $dbh = shift;
	my $client_ip = shift;
	my $user_agent = shift;
	my $xml = shift;

	my @item = PDLNA::ContentLibrary::get_item_by_id($dbh, $id, [ 'item_type', 'media_type', 'mime_type', 'title', 'size', 'file_extension', 'date', 'duration', 'width', 'height' ]);

	#
	# GENERAL ITEM DESCRIPTION
	#
	push(@{$xml}, 'parentID=&quot;'.PDLNA::Utils::encode_xml($item[0]->{parent_id}).'&quot; ') if grep(/^\@parentID$/, @{$filter});
	push(@{$xml}, 'restricted=&quot;1&quot;&gt;') if grep(/^\@restricted$/, @{$filter});
	push(@{$xml}, '&lt;dc:title&gt;'.PDLNA::Utils::encode_xml($item[0]->{title}).'&lt;/dc:title&gt;') if grep(/^dc:title$/, @{$filter});
	push(@{$xml}, '&lt;upnp:class&gt;object.item.'.PDLNA::Utils::encode_xml($item[0]->{media_type}).'Item&lt;/upnp:class&gt;') if grep(/^upnp:class$/, @{$filter});
	my $date = time2str("%Y-%m-%d", $item[0]->{date});
	push(@{$xml}, '&lt;dc:date&gt;'.PDLNA::Utils::encode_xml($date).'&lt;/dc:date&gt;') if grep(/^dc:date$/, @{$filter});
	push(@{$xml}, '&lt;sec:modifiationDate&gt;'.PDLNA::Utils::encode_xml($date).'&lt;/sec:modifiationDate&gt;') if grep(/^sec:modifiationDate$/, @{$filter});

	if (grep(/^sec:dcmInfo$/, @{$filter}))
	{
		my @infos = ();

		if ($item[0]->{media_type} eq 'image')
		{
			push(@infos, 'WIDTH='.PDLNA::Utils::encode_xml($item[0]->{width}));
			push(@infos, 'HEIGHT='.PDLNA::Utils::encode_xml($item[0]->{height}));
		}
		push(@infos, 'CREATIONDATE='.PDLNA::Utils::encode_xml($item[0]->{date}));

		push(@{$xml}, '&lt;sec:dcmInfo&gt;'.join(',', @infos).'&lt;/sec:dcmInfo&gt;');
	}

	#
	# RESOURCE ITEM DESCRIPTION
	#
	my $url_scheme = 'http://'.PDLNA::Utils::encode_xml($CONFIG{'LOCAL_IPADDR'}).':'.PDLNA::Utils::encode_xml($CONFIG{'HTTP_PORT'});

	push(@{$xml}, '&lt;res ');
	if ($item[0]->{media_type} eq 'audio' || $item[0]->{media_type} eq 'video')
	{
		my $duration = PDLNA::Utils::convert_duration($item[0]->{duration});
		push(@{$xml}, 'duration=&quot;'.PDLNA::Utils::encode_xml($duration).'&quot; ') if grep(/^res\@duration$/, @{$filter});
	}
	push(@{$xml}, 'size=&quot;'.PDLNA::Utils::encode_xml($item[0]->{size}).'&quot; ') if grep(/^res\@size$/, @{$filter});
	push(@{$xml}, 'protocolInfo=&quot;http-get:*:'.PDLNA::Utils::encode_xml($item[0]->{mime_type}).':'.PDLNA::Media::get_dlnacontentfeatures($item[0]).'&quot; ');
	push(@{$xml}, '&gt;');
	push(@{$xml}, $url_scheme.'/media/'.PDLNA::Utils::encode_xml($id.'.'.$item[0]->{file_extension}));
	push(@{$xml}, '&lt;/res&gt;');

	#
	# THUMBNAILS
	#
	if (($item[0]->{media_type} eq 'image' && $CONFIG{'IMAGE_THUMBNAILS'}) || ($item[0]->{media_type} && $CONFIG{'VIDEO_THUMBNAILS'}))
	{
		push(@{$xml}, '&lt;res protocolInfo=');
		push(@{$xml}, '&quot;http-get:*:image/jpeg:'.PDLNA::Utils::encode_xml(PDLNA::Media::get_dlnacontentfeatures('JPEG_TN', 1)).'&quot; ');
		push(@{$xml}, '&gt;');
		push(@{$xml}, $url_scheme.'/preview/'.PDLNA::Utils::encode_xml($id).'.jpg');
		push(@{$xml}, '&lt;/res&gt;');
	}

	#
	# SUBTITLES
	#
	if ($item[0]->{media_type} eq 'video' && grep(/^sec:CaptionInfoEx$/, @{$filter}))
	{
		my @subtitles = PDLNA::ContentLibrary::get_subtitles_by_refid($dbh, $id);
		foreach my $subtitle (@subtitles)
		{
			push(@{$xml}, '&lt;sec:CaptionInfoEx sec:type=&quot;'.PDLNA::Utils::encode_xml($subtitle->{media_type}).'&quot; &gt;');
			push(@{$xml}, $url_scheme.'/media/'.PDLNA::Utils::encode_xml($subtitle->{id}.'.'.$subtitle->{file_extension}));
			push(@{$xml}, '&lt;/sec:CaptionInfoEx&gt;');
		}
	}
}
sub foo {

	my $item_id = 0;
	my $xml;
	my $dbh;
	my ($client_ip, $user_agent, $filter);

	my @item = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT NAME, FULLNAME, TYPE, DATE, SIZE, MIME_TYPE, FILE_EXTENSION, EXTERNAL FROM FILES WHERE ID = ?;',
			'parameters' => [ $item_id, ],
		},
		\@item,
	);

	my @iteminfo = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT WIDTH, HEIGHT, BITRATE, DURATION, ARTIST, ALBUM, GENRE, YEAR, TRACKNUM, CONTAINER, AUDIO_CODEC, VIDEO_CODEC FROM FILEINFO WHERE FILEID_REF = ?;',
			'parameters' => [ $item_id, ],
		},
		\@iteminfo,
	);

	#
	# check if we need to transcode the content
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
		$iteminfo[0]->{CONTAINER} = $media_data{'container'};
		$iteminfo[0]->{AUDIO_CODEC} = $media_data{'audio_codec'};
		$iteminfo[0]->{VIDEO_CODEC} = $media_data{'video_codec'};
		$iteminfo[0]->{BITRATE} = 0;
		$iteminfo[0]->{VBR} = 0;
	}
	#
	# end of checking for transcoding
	#

	if ($item[0]->{TYPE} eq 'audio')
	{
		push(@{$xml}, '&lt;upnp:artist&gt;'.PDLNA::Utils::encode_xml($iteminfo[0]->{ARTIST}).'&lt;/upnp:artist&gt;') if grep(/^upnp:artist$/, @{$filter});
		push(@{$xml}, '&lt;dc:creator&gt;'.PDLNA::Utils::encode_xml($iteminfo[0]->{ARTIST}).'&lt;/dc:creator&gt;') if grep(/^dc:creator$/, @{$filter});
		push(@{$xml}, '&lt;upnp:album&gt;'.PDLNA::Utils::encode_xml($iteminfo[0]->{ALBUM}).'&lt;/upnp:album&gt;') if grep(/^upnp:album$/, @{$filter});
		push(@{$xml}, '&lt;upnp:genre&gt;'.PDLNA::Utils::encode_xml($iteminfo[0]->{GENRE}).'&lt;/upnp:genre&gt;') if grep(/^upnp:genre$/, @{$filter});
		push(@{$xml}, '&lt;upnp:originalTrackNumber&gt;'.PDLNA::Utils::encode_xml($iteminfo[0]->{TRACKNUM}).'&lt;/upnp:originalTrackNumber&gt;') if grep(/^upnp:originalTrackNumber$/, @{$filter});
		# albumArtURI
	}
	elsif ($item[0]->{TYPE} eq 'image')
	{
#		&lt;sec:manufacturer&gt;NIKON CORPORATION&lt;/sec:manufacturer&gt;
#		&lt;sec:fvalue&gt;4.5&lt;/sec:fvalue&gt;
#		&lt;sec:exposureTime&gt;0.008&lt;/sec:exposureTime&gt;
#		&lt;sec:iso&gt;2500&lt;/sec:iso&gt;
#		&lt;sec:model&gt;NIKON D700&lt;/sec:model&gt;
#		&lt;sec:composition&gt;0&lt;/sec:composition&gt;
#		&lt;sec:color&gt;0&lt;/sec:color&gt;
	}

	push(@{$xml}, '&lt;upnp:playbackCount&gt;0&lt;/upnp:playbackCount&gt;') if grep(/^upnp:playbackCount$/, @{$filter});
	push(@{$xml}, '&lt;sec:preference&gt;0&lt;/sec:preference&gt;') if grep(/^sec:preference$/, @{$filter});
	push(@{$xml}, '&lt;dc:date&gt;'.PDLNA::Utils::encode_xml(time2str("%Y-%m-%d", $item[0]->{DATE})).'&lt;/dc:date&gt;') if grep(/^dc:date$/, @{$filter});
	push(@{$xml}, '&lt;sec:modifiationDate&gt;'.PDLNA::Utils::encode_xml(time2str("%Y-%m-%d", $item[0]->{DATE})).'&lt;/sec:modifiationDate&gt;') if grep(/^sec:modifiationDate$/, @{$filter});

	if (grep(/^sec:dcmInfo$/, @{$filter}))
	{
		my @infos = ();
#		push(@infos, 'MOODSCORE=0') if $item->type() eq 'audio';
#		push(@infos, 'MOODID=5') if $item->type() eq 'audio';
#
		push(@infos, 'WIDTH='.PDLNA::Utils::encode_xml($iteminfo[0]->{WIDTH})) if $item[0]->{TYPE} eq 'image';
		push(@infos, 'HEIGHT='.PDLNA::Utils::encode_xml($iteminfo[0]->{HEIGHT})) if $item[0]->{TYPE} eq 'image';
#		push(@infos, 'COMPOSCORE=0') if $item->type() eq 'image';
#		push(@infos, 'COMPOID=0') if $item->type() eq 'image';
#		push(@infos, 'COLORSCORE=0') if $item->type() eq 'image';
#		push(@infos, 'COLORID=0') if $item->type() eq 'image';
#		push(@infos, 'MONTHLY=12') if $item->type() eq 'image';
#		push(@infos, 'ORT=1') if $item->type() eq 'image';
#
		push(@infos, 'CREATIONDATE='.PDLNA::Utils::encode_xml($item[0]->{DATE}));
#		push(@infos, 'YEAR='.time2str("%Y", $item->date())) if $item->type() eq 'audio';
#		push(@infos, 'FOLDER=') if $item->type() =~ /^(image|video)$/;

		#
		# BOOKMARKS
		#
		if ($item[0]->{TYPE} eq 'video')
		{
			my $bookmark = 0;

			my $device_ip_id = PDLNA::Devices::get_device_ip_id_by_device_ip($dbh, $client_ip);
			if (defined($device_ip_id))
			{
				$bookmark = PDLNA::Database::select_db_field_int(
					$dbh,
					{
						'query' => 'SELECT pos_seconds FROM device_bm WHERE item_id_ref = ? AND device_ip_ref = ?',
						'parameters' => [ $item_id, $device_ip_id, ],
					},
				);
			}
			push(@infos, 'BM='.PDLNA::Utils::encode_xml($bookmark));
		}

		push(@{$xml}, '&lt;sec:dcmInfo&gt;'.join(',', @infos).'&lt;/sec:dcmInfo&gt;');
	}

	my $url_scheme = 'http://'.PDLNA::Utils::encode_xml($CONFIG{'LOCAL_IPADDR'}).':'.PDLNA::Utils::encode_xml($CONFIG{'HTTP_PORT'});

	push(@{$xml}, '&lt;res ');
	if ($item[0]->{TYPE} eq 'video')
	{
#		push(@xml, 'sec:acodec=&quot;'..'&quot; ');
#		push(@xml, 'sec:vcodec=&quot;'..'&quot; ');
#		sec:acodec=&quot;ac3&quot; sec:vcodec=&quot;mpeg2video&quot;
	}
	if ($item[0]->{TYPE} eq 'audio' || $item[0]->{TYPE} eq 'video')
	{
		push(@{$xml}, 'bitrate=&quot;'.PDLNA::Utils::encode_xml($iteminfo[0]->{BITRATE}).'&quot; ') if grep(/^res\@bitrate$/, @{$filter});
		push(@{$xml}, 'duration=&quot;'.PDLNA::Utils::encode_xml(PDLNA::Utils::convert_duration($iteminfo[0]->{DURATION})).'&quot; ') if grep(/^res\@duration$/, @{$filter});
	}
	if ($item[0]->{TYPE} eq 'image' || $item[0]->{TYPE} eq 'video')
	{
		push(@{$xml}, 'resolution=&quot;'.PDLNA::Utils::encode_xml($iteminfo[0]->{WIDTH}).'x'.PDLNA::Utils::encode_xml($iteminfo[0]->{HEIGHT}).'&quot; ') if grep(/^res\@resolution$/, @{$filter});
	}
	if ($transcode == 0 || $item[0]->{EXTERNAL} == 0) # just add the size attribute if file is local and not transcoded
	{
		push(@{$xml}, 'size=&quot;'.PDLNA::Utils::encode_xml($item[0]->{SIZE}).'&quot; ') if grep(/^res\@size$/, @{$filter});
	}
	push(@{$xml}, 'protocolInfo=&quot;http-get:*:'.PDLNA::Utils::encode_xml($item[0]->{MIME_TYPE}).':'.PDLNA::Utils::encode_xml(PDLNA::Media::get_dlnacontentfeatures($item[0], $transcode)).'&quot; ');
	push(@{$xml}, '&gt;');
	push(@{$xml}, $url_scheme.'/media/'.PDLNA::Utils::encode_xml($item_id).'.'.PDLNA::Utils::encode_xml($item[0]->{FILE_EXTENSION}));
	push(@{$xml}, '&lt;/res&gt;');

	# File preview information
	if (
#			$item->file() && # no thumbnails for commands or streams
			($item[0]->{TYPE} eq 'image' && $CONFIG{'IMAGE_THUMBNAILS'}) || ($item[0]->{TYPE} eq 'video' && $CONFIG{'VIDEO_THUMBNAILS'})
		)
	{
		push(@{$xml}, '&lt;res protocolInfo=');
		push(@{$xml}, '&quot;http-get:*:image/jpeg:'.PDLNA::Utils::encode_xml(PDLNA::Media::get_dlnacontentfeatures(undef, 1, 'JPEG_TN')).'&quot; ');
		push(@{$xml}, '&gt;');
		push(@{$xml}, $url_scheme.'/preview/'.PDLNA::Utils::encode_xml($item_id).'.jpg');
		push(@{$xml}, '&lt;/res&gt;');
	}

	# subtitles
	if ($item[0]->{TYPE} eq 'video' && grep(/^sec:CaptionInfoEx$/, @{$filter}))
	{
		my @subtitles = ();
		PDLNA::Database::select_db(
			$dbh,
			{
				'query' => 'SELECT id, type FROM subtitles WHERE fileid_ref = ?',
				'parameters' => [ $item_id, ],
			},
			\@subtitles,
		);

		foreach my $subtitle (@subtitles)
		{
			push(@{$xml}, '&lt;sec:CaptionInfoEx sec:type=&quot;'.PDLNA::Utils::encode_xml($subtitle->{type}).'&quot; &gt;');
			push(@{$xml}, $url_scheme.'/subtitle/'.PDLNA::Utils::encode_xml($subtitle->{id}).'.'.PDLNA::Utils::encode_xml($subtitle->{type}));
			push(@{$xml}, '&lt;/sec:CaptionInfoEx&gt;');
		}
	}
	push(@{$xml}, '&lt;/item&gt;');
}

#
# This is not the most elegant solution,
# but at least it is more generic
#
# TODO: make me more beautiful
#
sub lookup_elementvalue_in_xml
{
	my $xml = shift;
	my $name = shift;

	foreach my $key1 (%{$xml})
	{
		if ($key1 =~ /:Body$/)
		{
			foreach my $key2 (%{$xml->{$key1}})
			{
				if ($key2 =~ /:Browse$/)
				{
					if (ref($xml->{$key1}->{$key2}->{$name}) eq 'HASH')
					{
						return $xml->{$key1}->{$key2}->{$name}->{'content'};
					}
					else
					{
						return $xml->{$key1}->{$key2}->{$name};
					}
				}
			}
		}
	}
	return undef;
}

sub get_serverdescription
{
	my $user_agent = shift || '';

	my @xml = (
		#'<?xml version="1.0" encoding="utf-8"?>',
		'<?xml version="1.0"?>',
		'<root xmlns="urn:schemas-upnp-org:device-1-0">',
		'<specVersion>',
		'<major>1</major>',
		'<minor>5</minor>',
		'</specVersion>',
		'<device>',
	);

	# this seems to break some clients
	if ($user_agent eq 'SamsungWiselinkPro/1.0')
	{
		#push(@xml, '<dlna:X_DLNADOC>DMS-1.50</dlna:X_DLNADOC>');
		push(@xml, '<dlna:X_DLNADOC xmlns:dlna="urn:schemas-dlna-org:device-1-0">DMS-1.50</dlna:X_DLNADOC>');
		push(@xml, '<dlna:X_DLNADOC xmlns:dlna="urn:schemas-dlna-org:device-1-0">M-DMS-1.50</dlna:X_DLNADOC>');
		push(@xml, '<dlna:X_DLNACAP xmlns:dlna="urn:schemas-dlna-org:device-1-0">av-upload,image-upload,audio-upload</dlna:X_DLNACAP>');
	}
	push(@xml, '<deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType>');
	push(@xml, '<presentationURL>http://'.PDLNA::Utils::encode_xml($CONFIG{'LOCAL_IPADDR'}).':'.PDLNA::Utils::encode_xml($CONFIG{'HTTP_PORT'}).'/</presentationURL>');
	push(@xml, '<friendlyName>'.PDLNA::Utils::encode_xml($CONFIG{'FRIENDLY_NAME'}).'</friendlyName>');
	push(@xml, '<manufacturer>'.PDLNA::Utils::encode_xml($CONFIG{'PROGRAM_AUTHOR'}).'</manufacturer>');
	push(@xml, '<manufacturerURL>'.PDLNA::Utils::encode_xml($CONFIG{'AUTHOR_WEBSITE'}).'</manufacturerURL>');
	push(@xml, '<modelDescription>'.PDLNA::Utils::encode_xml($CONFIG{'PROGRAM_DESC'}).'</modelDescription>');
	push(@xml, '<modelName>'.PDLNA::Utils::encode_xml($CONFIG{'PROGRAM_NAME'}).'</modelName>');
	push(@xml, '<modelNumber>'.PDLNA::Utils::encode_xml(PDLNA::Config::print_version()).'</modelNumber>');
	push(@xml, '<modelURL>'.PDLNA::Utils::encode_xml($CONFIG{'PROGRAM_WEBSITE'}).'</modelURL>');
	push(@xml, '<serialNumber>'.PDLNA::Utils::encode_xml($CONFIG{'PROGRAM_SERIAL'}).'</serialNumber>');

	# specific views
	my $dcm10 = '';
	if ($CONFIG{'SPECIFIC_VIEWS'})
	{
		$dcm10 = 'DCM10,';
	}

	if ($user_agent eq 'SamsungWiselinkPro/1.0')
	{
		push(@xml, '<sec:ProductCap>smi,'.$dcm10.'getMediaInfo.sec,getCaptionInfo.sec</sec:ProductCap>');
		push(@xml, '<sec:X_ProductCap>smi,'.$dcm10.'getMediaInfo.sec,getCaptionInfo.sec</sec:X_ProductCap>');
	}

	push(@xml, '<UDN>'.PDLNA::Utils::encode_xml($CONFIG{'UUID'}).'</UDN>');

	my %TYPES = (
		'png' => 'png',
		'jpeg' => 'jpeg',
		#'bmp' => 'x-ms-bmp',
	);
	push(@xml, '<iconList>');
	foreach my $size ('120', '48', '32')
	{
		foreach my $type (keys %TYPES)
		{
			push(@xml, '<icon>');
			push(@xml, '<mimetype>image/'.$TYPES{$type}.'</mimetype>');
			push(@xml, '<width>'.$size.'</width>');
			push(@xml, '<height>'.$size.'</height>');
			push(@xml, '<depth>24</depth>');
			push(@xml, '<url>/icons/'.$size.'/icon.'.$type.'</url>');
			push(@xml, '</icon>');
		}
	}
	push(@xml, '</iconList>');
	push(@xml, '<serviceList>');
	push(@xml, '<service>');
	push(@xml, '<serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>');
	push(@xml, '<serviceId>urn:upnp-org:serviceId:ConnectionManager</serviceId>');
	push(@xml, '<SCPDURL>ConnectionManager1.xml</SCPDURL>');
	push(@xml, '<controlURL>/upnp/control/ConnectionManager1</controlURL>');
	push(@xml, '<eventSubURL>/upnp/event/ConnectionManager1</eventSubURL>');
	push(@xml, '</service>');
	push(@xml, '<service>');
	push(@xml, '<serviceType>urn:schemas-upnp-org:service:ContentDirectory:1</serviceType>');
	push(@xml, '<serviceId>urn:upnp-org:serviceId:ContentDirectory</serviceId>');
	push(@xml, '<SCPDURL>ContentDirectory1.xml</SCPDURL>');
	push(@xml, '<controlURL>/upnp/control/ContentDirectory1</controlURL>');
	push(@xml, '<eventSubURL>/upnp/event/ContentDirectory1</eventSubURL>');
	push(@xml, '</service>');
	push(@xml, '</serviceList>');
	push(@xml, '</device>');
	push(@xml, '<URLBase>http://'.PDLNA::Utils::encode_xml($CONFIG{'LOCAL_IPADDR'}).':'.PDLNA::Utils::encode_xml($CONFIG{'HTTP_PORT'}).'/</URLBase>');
	push(@xml, '</root>');

	return join('', @xml);
}

sub get_contentdirectory
{
	my @xml = (
		'<?xml version="1.0" encoding="utf-8"?>',
			'<scpd xmlns="urn:schemas-upnp-org:service-1-0">',
			'<specVersion>',
				'<major>1</major>',
				'<minor>0</minor>',
			'</specVersion>',
			'<actionList>',
				'<action>',
					'<name>Browse</name>',
					'<argumentList>',
						'<argument>',
							'<name>ObjectID</name>',
							'<direction>in</direction>',
							'<relatedStateVariable>A_ARG_TYPE_ObjectID</relatedStateVariable>',
						'</argument>',
						'<argument>',
							'<name>BrowseFlag</name>',
							'<direction>in</direction>',
							'<relatedStateVariable>A_ARG_TYPE_BrowseFlag</relatedStateVariable>',
						'</argument>',
						'<argument>',
							'<name>Filter</name>',
							'<direction>in</direction>',
							'<relatedStateVariable>A_ARG_TYPE_Filter</relatedStateVariable>',
						'</argument>',
						'<argument>',
							'<name>StartingIndex</name>',
							'<direction>in</direction>',
							'<relatedStateVariable>A_ARG_TYPE_Index</relatedStateVariable>',
						'</argument>',
						'<argument>',
							'<name>RequestedCount</name>',
							'<direction>in</direction>',
							'<relatedStateVariable>A_ARG_TYPE_Count</relatedStateVariable>',
						'</argument>',
						'<argument>',
							'<name>SortCriteria</name>',
							'<direction>in</direction>',
							'<relatedStateVariable>A_ARG_TYPE_SortCriteria</relatedStateVariable>',
						'</argument>',
						'<argument>',
							'<name>Result</name>',
							'<direction>out</direction>',
							'<relatedStateVariable>A_ARG_TYPE_Result</relatedStateVariable>',
						'</argument>',
						'<argument>',
							'<name>NumberReturned</name>',
							'<direction>out</direction>',
							'<relatedStateVariable>A_ARG_TYPE_Count</relatedStateVariable>',
						'</argument>',
						'<argument>',
							'<name>TotalMatches</name>',
							'<direction>out</direction>',
							'<relatedStateVariable>A_ARG_TYPE_Count</relatedStateVariable>',
						'</argument>',
						'<argument>',
							'<name>UpdateID</name>',
							'<direction>out</direction>',
							'<relatedStateVariable>A_ARG_TYPE_UpdateID</relatedStateVariable>',
						'</argument>',
					'</argumentList>',
				'</action>',
				'<action>',
					'<name>GetSearchCapabilities</name>',
					'<argumentList>',
						'<argument>',
							'<name>SearchCaps</name>',
							'<direction>out</direction>',
							'<relatedStateVariable>SearchCapabilities</relatedStateVariable>',
						'</argument>',
					'</argumentList>',
				'</action>',
				'<action>',
					'<name>GetSortCapabilities</name>',
					'<argumentList>',
						'<argument>',
							'<name>SortCaps</name>',
							'<direction>out</direction>',
							'<relatedStateVariable>SortCapabilities</relatedStateVariable>',
						'</argument>',
					'</argumentList>',
				'</action>',
				'<action>',
					'<name>GetSystemUpdateID</name>',
					'<argumentList>',
						'<argument>',
							'<name>Id</name>',
							'<direction>out</direction>',
							'<relatedStateVariable>SystemUpdateID</relatedStateVariable>',
						'</argument>',
					'</argumentList>',
				'</action>',
				'<action>',
					'<name>X_SetBookmark</name>',
					'<argumentList>',
						'<argument>',
							'<name>CategoryType</name>',
							'<direction>in</direction>',
							'<relatedStateVariable>A_ARG_TYPE_CategoryType</relatedStateVariable>',
						'</argument>',
						'<argument>',
							'<name>RID</name>',
							'<direction>in</direction>',
							'<relatedStateVariable>A_ARG_TYPE_RID</relatedStateVariable>',
						'</argument>',
						'<argument>',
							'<name>ObjectID</name>',
							'<direction>in</direction>',
							'<relatedStateVariable>A_ARG_TYPE_ObjectID</relatedStateVariable>',
						'</argument>',
						'<argument>',
							'<name>PosSecond</name>',
							'<direction>in</direction>',
							'<relatedStateVariable>A_ARG_TYPE_PosSec</relatedStateVariable>',
						'</argument>',
					'</argumentList>',
				'</action>',
			'</actionList>',
			'<serviceStateTable>',
				'<stateVariable sendEvents="no">',
					'<name>A_ARG_TYPE_BrowseFlag</name>',
					'<dataType>string</dataType>',
					'<allowedValueList>',
						'<allowedValue>BrowseMetadata</allowedValue>',
						'<allowedValue>BrowseDirectChildren</allowedValue>',
					'</allowedValueList>',
				'</stateVariable>',
				'<stateVariable sendEvents="yes">',
					'<name>SystemUpdateID</name>',
					'<dataType>ui4</dataType>',
				'</stateVariable>',
				'<stateVariable sendEvents="yes">',
					'<name>ContainerUpdateIDs</name>',
					'<dataType>string</dataType>',
				'</stateVariable>',
				'<stateVariable sendEvents="no">',
					'<name>A_ARG_TYPE_Count</name>',
					'<dataType>ui4</dataType>',
				'</stateVariable>',
				'<stateVariable sendEvents="no">',
					'<name>A_ARG_TYPE_SortCriteria</name>',
					'<dataType>string</dataType>',
				'</stateVariable>',
				'<stateVariable sendEvents="no">',
					'<name>SortCapabilities</name>',
					'<dataType>string</dataType>',
				'</stateVariable>',
				'<stateVariable sendEvents="no">',
					'<name>A_ARG_TYPE_Index</name>',
					'<dataType>ui4</dataType>',
				'</stateVariable>',
				'<stateVariable sendEvents="no">',
					'<name>A_ARG_TYPE_ObjectID</name>',
					'<dataType>string</dataType>',
				'</stateVariable>',
				'<stateVariable sendEvents="no">',
					'<name>A_ARG_TYPE_UpdateID</name>',
					'<dataType>ui4</dataType>',
				'</stateVariable>',
				'<stateVariable sendEvents="no">',
					'<name>A_ARG_TYPE_Result</name>',
					'<dataType>string</dataType>',
				'</stateVariable>',
				'<stateVariable sendEvents="no">',
					'<name>SearchCapabilities</name>',
					'<dataType>string</dataType>',
				'</stateVariable>',
				'<stateVariable sendEvents="no">',
					'<name>A_ARG_TYPE_Filter</name>',
					'<dataType>string</dataType>',
				'</stateVariable>',
				'<stateVariable sendEvents="no">',
					'<name>A_ARG_TYPE_CategoryType</name>',
					'<dataType>ui4</dataType>',
					'<defaultValue />',
				'</stateVariable>',
				'<stateVariable sendEvents="no">',
					'<name>A_ARG_TYPE_RID</name>',
					'<dataType>ui4</dataType>',
					'<defaultValue />',
				'</stateVariable>',
				'<stateVariable sendEvents="no">',
					'<name>A_ARG_TYPE_PosSec</name>',
					'<dataType>ui4</dataType>',
					'<defaultValue />',
				'</stateVariable>',
			'</serviceStateTable>',
		'</scpd>',
	);

	return join('', @xml);
}

sub get_connectionmanager
{
	my @xml = (
		'<?xml version="1.0" encoding="utf-8"?>',
		'<scpd xmlns="urn:schemas-upnp-org:service-1-0">',
		'<specVersion>',
		'<major>1</major>',
		'<minor>0</minor>',
		'</specVersion>',
		'<actionList>',
		'<action>',
		'<name>GetCurrentConnectionIDs</name>',
		'<argumentList>',
		'<argument>',
		'<name>ConnectionIDs</name>',
		'<direction>out</direction>',
		'<relatedStateVariable>CurrentConnectionIDs</relatedStateVariable>',
		'</argument>',
		'</argumentList>',
		'</action>',
		'<action>',
		'<name>GetCurrentConnectionInfo</name>',
		'<argumentList>',
		'<argument>',
		'<name>ConnectionID</name>',
		'<direction>in</direction>',
		'<relatedStateVariable>A_ARG_TYPE_ConnectionID</relatedStateVariable>',
		'</argument>',
		'<argument>',
		'<name>RcsID</name>',
		'<direction>out</direction>',
		'<relatedStateVariable>A_ARG_TYPE_RcsID</relatedStateVariable>',
		'</argument>',
		'<argument>',
		'<name>AVTransportID</name>',
		'<direction>out</direction>',
		'<relatedStateVariable>A_ARG_TYPE_AVTransportID</relatedStateVariable>',
		'</argument>',
		'<argument>',
		'<name>ProtocolInfo</name>',
		'<direction>out</direction>',
		'<relatedStateVariable>A_ARG_TYPE_ProtocolInfo</relatedStateVariable>',
		'</argument>',
		'<argument>',
		'<name>PeerConnectionManager</name>',
		'<direction>out</direction>',
		'<relatedStateVariable>A_ARG_TYPE_ConnectionManager</relatedStateVariable>',
		'</argument>',
		'<argument>',
		'<name>PeerConnectionID</name>',
		'<direction>out</direction>',
		'<relatedStateVariable>A_ARG_TYPE_ConnectionID</relatedStateVariable>',
		'</argument>',
		'<argument>',
		'<name>Direction</name>',
		'<direction>out</direction>',
		'<relatedStateVariable>A_ARG_TYPE_Direction</relatedStateVariable>',
		'</argument>',
		'<argument>',
		'<name>Status</name>',
		'<direction>out</direction>',
		'<relatedStateVariable>A_ARG_TYPE_ConnectionStatus</relatedStateVariable>',
		'</argument>',
		'</argumentList>',
		'</action>',
		'<action>',
		'<name>GetProtocolInfo</name>',
		'<argumentList>',
		'<argument>',
		'<name>Source</name>',
		'<direction>out</direction>',
		'<relatedStateVariable>SourceProtocolInfo</relatedStateVariable>',
		'</argument>',
		'<argument>',
		'<name>Sink</name>',
		'<direction>out</direction>',
		'<relatedStateVariable>SinkProtocolInfo</relatedStateVariable>',
		'</argument>',
		'</argumentList>',
		'</action>',
		'</actionList>',
		'<serviceStateTable>',
		'<stateVariable sendEvents="no">',
		'<name>A_ARG_TYPE_ProtocolInfo</name>',
		'<dataType>string</dataType>',
		'</stateVariable>',
		'<stateVariable sendEvents="no">',
		'<name>A_ARG_TYPE_ConnectionStatus</name>',
		'<dataType>string</dataType>',
		'<allowedValueList>',
		'<allowedValue>OK</allowedValue>',
		'<allowedValue>ContentFormatMismatch</allowedValue>',
		'<allowedValue>InsufficientBandwidth</allowedValue>',
		'<allowedValue>UnreliableChannel</allowedValue>',
		'<allowedValue>Unknown</allowedValue>',
		'</allowedValueList>',
		'</stateVariable>',
		'<stateVariable sendEvents="no">',
		'<name>A_ARG_TYPE_AVTransportID</name>',
		'<dataType>i4</dataType>',
		'</stateVariable>',
		'<stateVariable sendEvents="no">',
		'<name>A_ARG_TYPE_RcsID</name>',
		'<dataType>i4</dataType>',
		'</stateVariable>',
		'<stateVariable sendEvents="no">',
		'<name>A_ARG_TYPE_ConnectionID</name>',
		'<dataType>i4</dataType>',
		'</stateVariable>',
		'<stateVariable sendEvents="no">',
		'<name>A_ARG_TYPE_ConnectionManager</name>',
		'<dataType>string</dataType>',
		'</stateVariable>',
		'<stateVariable sendEvents="yes">',
		'<name>SourceProtocolInfo</name>',
		'<dataType>string</dataType>',
		'</stateVariable>',
		'<stateVariable sendEvents="yes">',
		'<name>SinkProtocolInfo</name>',
		'<dataType>string</dataType>',
		'</stateVariable>',
		'<stateVariable sendEvents="no">',
		'<name>A_ARG_TYPE_Direction</name>',
		'<dataType>string</dataType>',
		'<allowedValueList>',
		'<allowedValue>Input</allowedValue>',
		'<allowedValue>Output</allowedValue>',
		'</allowedValueList>',
		'</stateVariable>',
		'<stateVariable sendEvents="yes">',
		'<name>CurrentConnectionIDs</name>',
		'<dataType>string</dataType>',
		'</stateVariable>',
		'</serviceStateTable>',
		'</scpd>',
	);

	return join('', @xml);
}

1;
