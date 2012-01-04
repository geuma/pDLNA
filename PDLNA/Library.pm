package PDLNA::Library;
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2012 Stefan Heumader <stefan@heumader.at>
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

use PDLNA::Config;
use PDLNA::ContentLibrary;

sub show_library
{
	my $content = shift;
	my $params = shift || 0;

	my $response ="HTTP/1.0 200 OK\r\n";
	$response .= "Server: $CONFIG{'PROGRAM_NAME'} v$CONFIG{'PROGRAM_VERSION'} Webserver\r\n";
	$response .= "\r\n";

	$response .= '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">';
	$response .= '<html>';
	$response .= '<head>';
	$response .= '<title>'.$CONFIG{'FRIENDLY_NAME'}.'</title>';

	$response .= '<style type="text/css">';
	$response .= 'body {';
	$response .= 'font-family: "lucida grande", verdana, sans-serif;';
	$response .= 'color: #3d80df;';
	$response .= '}';
	$response .= 'div.left {';
	$response .= 'float: left;';
	$response .= 'width: 250px;';
	$response .= 'border: 1px solid #3d80df;';
	$response .= 'background-color: #7DAAEA;';
	$response .= '}';
	$response .= 'div.logo {';
	$response .= 'display: block;';
	$response .= 'margin-left: auto;';
	$response .= 'margin-right: auto;';
	$response .= '}';

	$response .= 'div.header {';
	$response .= 'height: 150px;';
	$response .= '}';
	$response .= 'div.right {';
	$response .= 'margin-left: 20px;';
	$response .= 'padding-left: 20px;';
	$response .= '}';
	$response .= 'div.clear {';
	$response .= 'height: 10px;';
	$response .= '}';
	$response .= 'a {';
	$response .= 'color: #FFFFFF;';
	$response .= '}';
	$response .= '</style>';

	$response .= '</head>';
	$response .= '<body>';

	$response .= '<div class="header">';
	$response .= '<div class="left header logo">';
	$response .= '<img src="/icons/128/logo.png" />';
	$response .= '</div>';
	$response .= '<div class="right header">';
	$response .= '<h3>'.$CONFIG{'FRIENDLY_NAME'}.'</h3>';
	$response .= '</div>';
	$response .= '</div>';
	$response .= '<div class="clear">&nbsp;</div>';

	$response .= '<div class="left">';
	$response .= build_directory_tree($content, 0, $params);
	$response .= '</div>';

	$response .= '<div class="right">';
	$response .= '<table>';
	my $object = $content->get_object_by_id($params);
	foreach my $id (keys %{$object->items()})
	{
		$response .= '<tr>';
		if ((${$object->items()}{$id}->type() eq 'image' && $CONFIG{'IMAGE_THUMBNAILS'}) || (${$object->items()}{$id}->type() eq 'video' && $CONFIG{'VIDEO_THUMBNAILS'}))
		{
			$response .= '<td><img src="/preview/'.$id.'.jpg" /></td>';
		}
		else
		{
			$response .= '<td>&nbsp;</td>';
		}
		$response .= '<td>'.${$object->items()}{$id}->name().'</td>';
		$response .= '</tr>';
	}
	$response .= '</table>';
	$response .= '</div>';

	$response .= '</body>';
	$response .= '</html>';

	$response .= "\r\n";
	return $response;
}

sub build_directory_tree
{
	my $content = shift;
	my $start_id = shift;
	my $end_id = shift;

	my $response = '';

	my $object = $content->get_object_by_id($start_id);
	$response .= '<ul>';
	foreach my $id (keys %{$object->directories()})
	{
		$response .= '<li><a href="/library/'.$id.'">'.${$object->directories()}{$id}->name().' ('.${$object->directories()}{$id}->amount().')</a></li>';
		my $tmpid = substr($end_id, 0, length($id));
		$response .= build_directory_tree ($content, $id, $end_id) if ($tmpid eq $id);
	}
	$response .= '</ul>';

	return $response;
}

1;
