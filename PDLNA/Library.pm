package PDLNA::Library;
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

use PDLNA::Config;
use PDLNA::Content;

sub show_library
{
	my $content = shift;

	my $response ="HTTP/1.0 200 OK\r\n";
	$response .= "Server: $CONFIG{'PROGRAM_NAME'} v$CONFIG{'PROGRAM_VERSION'} Webserver\r\n";
	$response .= "\r\n";

	$response .= '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">';
	$response .= '<html>';
	$response .= '<head>';
	$response .= '<title>'.$CONFIG{'FRIENDLY_NAME'}.'&nbsp;&raquo;&nbsp;Content Library</title>';
	$response .= '</head>';
	$response .= '<body>';
	$response .= '<h3>'.$CONFIG{'FRIENDLY_NAME'}.'&nbsp;&raquo;&nbsp;Content Library</h3>';

	foreach my $type ('A','I','V')
	{
		$response .= '<ul>'.$type.'</ul>';
		foreach my $sort (keys %{$$content->{$type}})
		{
			$response .= '<ul>'.$sort.'</ul>';
			foreach my $group (@{$$content->{$type}->{$sort}->content_groups})
			{
				$response .= '<ul>'.$group->name().'</ul>';
				foreach my $element (@{$group->content_items})
				{
					$response .= '<li>'.$element->name().'</li>';
				}
			}
		}
	}

	$response .= '</body>';
	$response .= '</html>';

	$response .= "\r\n";
	return $response;
}

1;
