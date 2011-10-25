package PDLNA::HTTPXML;
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
use PDLNA::ContentDirectory;
use PDLNA::ContentItem;

sub get_browseresponse_header
{
	my @xml = (
		'<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">',
		'<s:Body>',
		'<u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">',
		'<Result>',
		'&lt;DIDL-Lite xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot; xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot;&gt;',
	);

	return join("\n", @xml);
}

sub get_browseresponse_footer
{
	my $number_returned = shift;
	my $total_matches = shift;

	my @xml = (
		'&lt;/DIDL-Lite&gt;',
		'</Result>',
		'<NumberReturned>'.$number_returned.'</NumberReturned>',
		'<TotalMatches>'.$total_matches.'</TotalMatches>',
		'<UpdateID>0</UpdateID>',
		'</u:BrowseResponse>',
		'</s:Body>',
		'</s:Envelope>',
	);

	return join("\n", @xml);
}

sub get_browseresponse_directory
{
	my $directory = shift;

	my @xml = (
		'&lt;container ',
		'id=&quot;'.$directory->id().'&quot; ',
		'parentID=&quot;'.$directory->parent_id().'&quot; ',
		'restricted=&quot;1&quot; ',
		'childCount=&quot;'.$directory->amount().'&quot;&gt;',
		'&lt;dc:title&gt;'.$directory->name().'&lt;/dc:title&gt;',
		'&lt;upnp:class&gt;object.container&lt;/upnp:class&gt;',
		'&lt;/container&gt;',
	);

	return join("\n", @xml);
}

sub get_browseresponse_item
{
	my $item = shift;

	my @xml = ();
	push(@xml, '&lt;item ');
	push(@xml, 'id=&quot;'.$item->id().'&quot; ');
	push(@xml, 'parentID=&quot;'.$item->parent_id().'&quot; ');
	push(@xml, 'restricted=&quot;1&quot;&gt;');
	push(@xml, '&lt;dc:title&gt;'.$item->name().'&lt;/dc:title&gt;');

	push(@xml, '&lt;upnp:class&gt;object.item.audioItem.musicTrack&lt;/upnp:class&gt;') if $item->type() eq 'audio';
	push(@xml, '&lt;upnp:class&gt;object.item.imageItem&lt;/upnp:class&gt;') if $item->type() eq 'image';
	push(@xml, '&lt;upnp:class&gt;object.item.videoItem&lt;/upnp:class&gt;') if $item->type() eq 'video';

	if ($item->type() eq 'audio')
	{
		push(@xml, '&lt;upnp:artist&gt;'.$item->artist().'&lt;/upnp:artist&gt;');
		push(@xml, '&lt;dc:creator&gt;'.$item->artist().'&lt;/dc:creator&gt;');
		push(@xml, '&lt;upnp:album&gt;'.$item->album().'&lt;/upnp:album&gt;');
		push(@xml, '&lt;upnp:genre&gt;'.$item->genre().'&lt;/upnp:genre&gt;');
		push(@xml, '&lt;upnp:originalTrackNumber&gt;'.$item->tracknum().'&lt;/upnp:originalTrackNumber&gt;');
	}

	if ($item->type() eq 'audio' || $item->type() eq 'image')
	{
		push(@xml, '&lt;dc:date&gt;'. time2str("%Y-%m-%d", $item->date()).'&lt;/dc:date&gt;');
	}

	push(@xml, '&lt;res protocolInfo=');
	push(@xml, '&quot;http-get:*:'.$item->mime_type().':*&quot; ');
	push(@xml, 'size=&quot;'.$item->size().'&quot; ');
	if ($item->type() eq 'audio' || $item->type() eq 'video')
	{
		push(@xml, 'bitrate=&quot;'.$item->bitrate().'&quot; ');
		push(@xml, 'duration=&quot;'.$item->duration().'&quot; ');
	}
	if ($item->type() eq 'image' || $item->type() eq 'video')
	{
		push(@xml, 'resolution=&quot;'.$item->resolution().'&quot; ');
	}
	push(@xml, '&gt;');
	push(@xml, 'http://'.$CONFIG{'LOCAL_IPADDR'}.':'.$CONFIG{'HTTP_PORT'}.'/media/'.$item->id().'.'.$item->file_extension());
	push(@xml, '&lt;/res&gt;');

	# File preview information
	if ($item->type() eq 'image' || $item->type() eq 'video')
	{
		push(@xml, '&lt;res protocolInfo=');
		push(@xml, '&quot;http-get:*:image/jpeg:DLNA.ORG_PN=JPEG_TN;DLNA.ORG_CI=1;DLNA.ORG_FLAGS=00D00000000000000000000000000000&quot; ');
		push(@xml, '&gt;');
		push(@xml, 'http://'.$CONFIG{'LOCAL_IPADDR'}.':'.$CONFIG{'HTTP_PORT'}.'/preview/'.$item->id().'.jpg');
		push(@xml, '&lt;/res&gt;');
	}
	push(@xml, '&lt;/item&gt;');

	return join('', @xml);
}

sub get_serverdescription
{
	my @xml = (
		'<?xml version="1.0"?>',
		'<root xmlns="urn:schemas-upnp-org:device-1-0">',
		'<specVersion>',
		'<major>1</major>',
		'<minor>0</minor>',
		'</specVersion>',
		'<device>',
		'<deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType>',
		'<presentationURL>http://'.$CONFIG{'LOCAL_IPADDR'}.':'.$CONFIG{'HTTP_PORT'}.'/</presentationURL>',
		'<friendlyName>'.$CONFIG{'FRIENDLY_NAME'}.'</friendlyName>',
		'<manufacturer>'.$CONFIG{'PROGRAM_AUTHOR'}.'</manufacturer>',
		'<manufacturerURL>'.$CONFIG{'PROGRAM_WEBSITE'}.'</manufacturerURL>',
		'<modelDescription>'.$CONFIG{'PROGRAM_DESC'}.'</modelDescription>',
		'<modelName>'.$CONFIG{'PROGRAM_NAME'}.'</modelName>',
		'<modelNumber>'.$CONFIG{'PROGRAM_VERSION'}.'</modelNumber>',
		'<serialNumber>'.$CONFIG{'PROGRAM_SERIAL'}.'</serialNumber>',
		'<UDN>'.$CONFIG{'UUID'}.'</UDN>',
		'<iconList>',
	);
	my %TYPES = (
		'png' => 'png',
		'jpeg' => 'jpeg',
		#'bmp' => 'x-ms-bmp',
	);
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
	push(@xml, '<URLBase>http://'.$CONFIG{'LOCAL_IPADDR'}.':'.$CONFIG{'HTTP_PORT'}.'/</URLBase>');
	push(@xml, '</root>');

	return join("\n", @xml);
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
		'</serviceStateTable>',
		'</scpd>',
	);

	return join("\n", @xml);
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

	return join("\n", @xml);
}

1;
