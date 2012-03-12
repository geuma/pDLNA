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

use Date::Format;

use PDLNA::Config;
use PDLNA::ContentLibrary;
use PDLNA::Utils;

sub show_library
{
	my $content = shift;
	my $params = shift || 0;
#	if ($params =~ /^(\d+)\./)
#	{
#		$params = $1;
#	}

	my $response ="HTTP/1.0 200 OK\r\n";
	$response .= "Server: $CONFIG{'PROGRAM_NAME'} v".PDLNA::Config::print_version()." Webserver\r\n";
	$response .= "Content-Type: text/html\r\n";
	$response .= "\r\n";

	$response .= '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">'."\n";
	$response .= '<html>';
	$response .= '<head>';
	$response .= '<title>'.$CONFIG{'FRIENDLY_NAME'}.'</title>';

	$response .= '<style type="text/css">';
	$response .= 'body {';
	$response .= 'font-family: "lucida grande", verdana, sans-serif;';
	$response .= 'font-size: 10pt;';
	$response .= 'color: #3d80df;';
	$response .= '}';
	$response .= '#container {';
	$response .= 'width: 960px;';
	$response .= 'margin-left: auto;';
	$response .= 'margin-right: auto;';
	$response .= 'border: 1px solid #3d80df;';
	$response .= 'margin-top: 50px;';
	$response .= '}';
	$response .= '#content {';
	$response .= 'float: left;';
	$response .= 'width: 620px;';
	$response .= 'padding-bottom: 20px;';
	$response .= '}';
	$response .= '#sidebar {';
	$response .= 'float: left;';
	$response .= 'width: 340px;';
	$response .= 'background-color: #3d80df;';
	$response .= 'padding-bottom: 20px;';
	$response .= '}';
	$response .= '#footer {';
	$response .= 'clear:both;';
	$response .= 'height: 40px;';
	$response .= 'color: #fff;';
	$response .= 'background-color: #3d80df;';
	$response .= 'text-align: center;';
	$response .= 'line-height: 3em;';
	$response .= '}';
	$response .= 'h3 {';
	$response .= 'font-size: 12pt;';
	$response .= 'text-align: center;';
	$response .= '}';
	$response .= 'a {';
	$response .= 'color: #fff;';
	$response .= '}';
	$response .= 'table{';
	$response .= 'width: 600px;';
	$response .= 'border: 1px solid #7DAAEA;';
	$response .= 'margin-left: auto;';
	$response .= 'margin-right: auto;';
	$response .= '}';
	$response .= 'tr td{';
	$response .= 'padding: 3px 8px;';
	$response .= 'background: #fff;';
	$response .= '}';
	$response .= 'thead td{';
	$response .= 'color: #fff;';
	$response .= 'background-color: #3d80df;';
	$response .= 'font-weight: bold;';
	$response .= 'border-bottom: 0px solid #999;';
	$response .= 'text-align: center;';
	$response .= '}';
	$response .= 'tbody td{';
	$response .= 'border-left: 0px solid #3d80df;';
	$response .= '}';
	$response .= 'tbody tr.even td{';
	$response .= 'background: #eee;';
	$response .= '}';
	$response .= '</style>';

	$response .= '</head>';
	$response .= '<body>';
	$response .= '<div id="container">';

	$response .= '<div id="header">';
	$response .= '<h3>'.$CONFIG{'FRIENDLY_NAME'}.'</h3>';
	$response .= '</div>';

	$response .= '<div id="sidebar">';
	$response .= build_directory_tree($content, 0, $params);
	$response .= '</div>';

	$response .= '<div id="content">';
	$response .= '<table>';
	$response .= '<thead>';
	$response .= '<tr><td>Preview</td><td>Filename</td><td>Size</td><td>Date</td></tr>';
	$response .= '</thead>';
	$response .= '<tbody>';
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
		$response .= '<td>'.PDLNA::Utils::convert_bytes(${$object->items()}{$id}->size()).'</td>';
		$response .= '<td>'.time2str($CONFIG{'DATE_FORMAT'}, ${$object->items()}{$id}->date()).'</td>';
	}
	$response .= '</tbody>';
	$response .= '</table>';
	$response .= '</div>';

	$response .= '<div id="footer">';
	$response .= '<p>provided by <a href="'.$CONFIG{'PROGRAM_WEBSITE'}.'" target="_blank">'.$CONFIG{'PROGRAM_NAME'}.'</a> v'.PDLNA::Config::print_version().' | licensed under <a href="http://www.gnu.org/licenses/gpl.txt" target="_blank">GPL v3.0</a></p>';
	$response .= '</div>';

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
