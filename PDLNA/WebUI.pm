package PDLNA::WebUI;
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
use Devel::Size qw(size total_size);
use Proc::ProcessTable;

use PDLNA::Config;
use PDLNA::Database;
use PDLNA::Daemon;
use PDLNA::Utils;

sub show
{
	my $content = shift;
	my $device_list = shift;
	my $params = shift;

	my $dbh = PDLNA::Database::connect();

	my @nav = split('/', $params);
	if (!defined($nav[0]) || $nav[0] !~ /^(content|device|perf)$/)
	{
		$nav[0] = 'content';
		$nav[1] = 0;
	}
	if ($nav[0] eq 'content' && (!defined($nav[1]) || $nav[1] !~ /^\d+$/))
	{
		$nav[1] = 0;
	}

	my $response ="HTTP/1.0 200 OK\r\n";
	$response .= "Server: $CONFIG{'PROGRAM_NAME'} v".PDLNA::Config::print_version()." Webserver\r\n";
	$response .= "Content-Type: text/html\r\n";
	$response .= "\r\n";

	my @javascript = (
		'stripe = function() {',
		'var tables = document.getElementsByTagName("table");',
		'for(var x=0;x!=tables.length;x++){',
		'var table = tables[x];',
		'if (! table) { return; }',
		'var tbodies = table.getElementsByTagName("tbody");',
		'for (var h = 0; h < tbodies.length; h++) {',
		'var even = true;',
		'var trs = tbodies[h].getElementsByTagName("tr");',
		'for (var i = 0; i < trs.length; i++) {',
		'trs[i].onmouseover=function(){',
		'this.className += " ruled"; return false',
		'}',
		'trs[i].onmouseout=function(){',
		'this.className = this.className.replace("ruled", ""); return false',
		'}',
		'if(even)',
		'trs[i].className += " even";',
		'even = !even;',
		'}',
		'}',
		'}',
		'}',
		'window.onload = stripe;',
	);

	$response .= '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">'."\n";
	$response .= '<html>';
	$response .= '<head>';
	$response .= '<title>'.$CONFIG{'FRIENDLY_NAME'}.'</title>';
	$response .= '<script type="text/javascript">';
	$response .= join("\n", @javascript);
	$response .= '</script>';

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
	$response .= 'h5 {';
	$response .= 'color: #fff;';
	$response .= 'font-size: 12pt;';
	$response .= 'text-align: center;';
	$response .= 'margin-bottom: -10px;';
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
	$response .= 'tfoot td{';
	$response .= 'color: #fff;';
	$response .= 'background-color: #3d80df;';
	$response .= 'font-weight: bold;';
	$response .= 'border-bottom: 0px solid #999;';
	$response .= 'text-align: center;';
	$response .= '}';
	$response .= 'tbody td{';
	$response .= 'border-left: 0px solid #3d80df;';
	$response .= '}';
	$response .= 'tbody td a{';
	$response .= 'color: #3d80df;';
	$response .= '}';
	$response .= 'tbody tr.even td{';
	$response .= 'background: #eee;';
	$response .= '}';
	$response .= 'tbody tr.ruled td{';
	$response .= 'color: #000;';
	$response .= 'background-color: #C6E3FF;';
	$response .= '}';
	$response .= 'li{';
	$response .= 'display: block;';
	$response .= 'margin-left: -15px;';
	$response .= '}';
	$response .= '</style>';

	$response .= '</head>';
	$response .= '<body>';
	$response .= '<div id="container">';

	$response .= '<div id="header">';
	$response .= '<h3>'.$CONFIG{'FRIENDLY_NAME'}.'</h3>';
	$response .= '</div>';

	$response .= '<div id="sidebar">';
	$response .= '<h5>Configured media</h5>';

	$response .= build_directory_tree($dbh, 0, $nav[1]);
	$response .= '<h5>Connected devices</h5>';
	my %ssdp_devices = $$device_list->devices();
	$response .= '<ul>';
	foreach my $device (sort keys %ssdp_devices)
	{
		$response .= '<li><a href="/webui/device/'.$device.'">'.$device.'</a></li>';
		$response .= '<ul>';
		foreach my $udn (keys %{$ssdp_devices{$device}->udn()})
		{
			$response .= '<li><a href="/webui/device/'.$device.'/'.$udn.'">'.$udn.'</a></li>';
		}
		$response .= '</ul>';
	}
	$response .= '</ul>';
	$response .= '<h5>Statistics</h5>';
	$response .= '<ul>';
	$response .= '<li><a href="/webui/perf/pi">Process Info</a></li>';
	$response .= '</ul>';
	$response .= '</div>';

	$response .= '<div id="content">';
	if ($nav[0] eq 'content')
	{
		$response .= '<table>';
		$response .= '<thead>';
		$response .= '<tr><td>Filename</td><td width="110px">Size</td><td width="160px">Date</td></tr>';
		$response .= '</thead>';








#		my $object = $content->get_object_by_id($nav[1]);
#		$response .= '<tfoot>';
#		$response .= '<tr><td>&nbsp;</td><td>'.PDLNA::Utils::convert_bytes($object->{'SIZE'}).'</td><td>&nbsp;</td></tr>';
#		$response .= '</tfoot>';
#		$response .= '<tbody>';
#		foreach my $id (sort keys %{$object->items()})
#		{
#			$response .= '<tr>';
#			$response .= '<td title="'.${$object->items()}{$id}->name().'">'.PDLNA::Utils::string_shortener(${$object->items()}{$id}->name(), 30).'</td>';
#			$response .= '<td>'.PDLNA::Utils::convert_bytes(${$object->items()}{$id}->size()).'</td>';
#			$response .= '<td>'.time2str($CONFIG{'DATE_FORMAT'}, ${$object->items()}{$id}->date()).'</td>';
#			$response .= '</tr>';
#		}
#		$response .= '</tbody>';
		$response .= '</table>';
	}
	elsif ($nav[0] eq 'device')
	{
		if (defined($ssdp_devices{$nav[1]}))
		{
			if (defined($nav[2]) && defined($ssdp_devices{$nav[1]}{UDN}{$nav[2]}))
			{
				$response .= '<table>';
				$response .= '<thead>';
				$response .= '<tr><td>&nbsp;</td><td>Information</td></tr>';
				$response .= '</thead>';
				$response .= '<tbody>';
				$response .= '<tr><td>UDN</td><td>'.$nav[2].'</td></tr>';
				$response .= '<tr><td>SSDP Banner</td><td>'.$ssdp_devices{$nav[1]}{UDN}{$nav[2]}->ssdp_banner().'</td></tr>';
				$response .= '<tr><td>Friendly Name</td><td>'.$ssdp_devices{$nav[1]}{UDN}{$nav[2]}->friendly_name.'</td></tr>';
				$response .= '<tr><td>Model Name</td><td>'.$ssdp_devices{$nav[1]}{UDN}{$nav[2]}->model_name().'</td></tr>';
				$response .= '<tr><td>Device Type</td><td>'.$ssdp_devices{$nav[1]}{UDN}{$nav[2]}->device_type().'</td></tr>';
				$response .= '<tr><td>Device Description URL</td><td><a href="'.$ssdp_devices{$nav[1]}{UDN}{$nav[2]}->device_description_url().'" target="_blank">'.$ssdp_devices{$nav[1]}{UDN}{$nav[2]}->device_description_url().'</a></td></tr>';
				$response .= '</tbody>';
				$response .= '</table>';

				$response .= '<p>&nbsp;</p>';

				$response .= '<table>';
				$response .= '<thead>';
				$response .= '<tr><td>NTS</td><td width="160px">expires at</td></tr>';
				$response .= '</thead>';
				$response .= '<tbody>';
				my %nts = %{$ssdp_devices{$nav[1]}{UDN}{$nav[2]}->nts()};
				foreach my $key (keys %nts)
				{
					$response .= '<tr><td>'.$key.'</td><td>'.time2str($CONFIG{'DATE_FORMAT'}, $nts{$key}).'</td></tr>';
				}
				$response .= '</tbody>';
				$response .= '</table>';
			}
			else
			{
				$response .= '<table>';
				$response .= '<thead>';
				$response .= '<tr><td>&nbsp;</td><td>Information</td></tr>';
				$response .= '</thead>';
				$response .= '<tbody>';
				$response .= '<tr><td>IP</td><td>'.$nav[1].'</td></tr>';
				$response .= '<tr><td>HTTP UserAgent</td><td>'.$ssdp_devices{$nav[1]}->http_useragent().'</td></tr>';
				$response .= '<tr><td>Last seen at</td><td>'.time2str($CONFIG{'DATE_FORMAT'}, $ssdp_devices{$nav[1]}->last_seen_timestamp()).'</td></tr>';
				$response .= '</tbody>';
				$response .= '</table>';
			}
		}
		else
		{
			$response .= '<p>Device not found.</p>';
		}
	}
	elsif ($nav[0] eq 'perf')
	{
		my $proc = Proc::ProcessTable->new();
		my %fields = map { $_ => 1 } $proc->fields;
		return undef unless exists $fields{'pid'};
		my $pid = PDLNA::Daemon::read_pidfile($CONFIG{'PIDFILE'});
		foreach my $process (@{$proc->table()})
		{
			if ($process->pid() eq $pid)
			{
				$response .= '<table>';
				$response .= '<thead>';
				$response .= '<tr><td>&nbsp;</td><td>Information</td></tr>';
				$response .= '</thead>';
				$response .= '<tbody>';
				$response .= '<tr><td>'.$CONFIG{'PROGRAM_NAME'}.' running with PID</td><td>'.$pid.'</td></tr>';
				$response .= '<tr><td>Parent PID of '.$CONFIG{'PROGRAM_NAME'}.'</td><td>'.$process->{ppid}.'</td></tr>';
				$response .= '<tr><td>'.$CONFIG{'PROGRAM_NAME'}.' started at</td><td>'.time2str($CONFIG{'DATE_FORMAT'}, $process->{start}).'</td></tr>';
				$response .= '<tr><td>'.$CONFIG{'PROGRAM_NAME'}.' running with priority</td><td>'.$process->{priority}.'</td></tr>';
				$response .= '<tr><td>CPU Utilization Since Process Started</td><td>'.$process->{pctcpu}.' %</td></tr>';
				$response .= '<tr><td>Current Virtual Memory Size</td><td>'.PDLNA::Utils::convert_bytes($process->{size}).'</td></tr>';
				$response .= '<tr><td>Current Memory Utilization in RAM</td><td>'.PDLNA::Utils::convert_bytes($process->{rss}).'</td></tr>';
				$response .= '<tr><td>Current Memory Utilization</td><td>'.$process->{pctmem}.' %</td></tr>';
				$response .= '<tr><td>Memory Utilization of DeviceList</td><td>'.PDLNA::Utils::convert_bytes(total_size($device_list)).'</td></tr>';
				$response .= '</tbody>';
				$response .= '</table>';
			}
		}
	}
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
	my $dbh = shift;
	my $start_id = shift;
	my $end_id = shift;

	my $response = '';

#	my $object = $content->get_object_by_id($start_id);
	my @results = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT ID, NAME FROM DIRECTORIES WHERE ROOT = 1',
			'parameters' => [],
		},
		\@results,
	);

	$response .= '<ul>';
	foreach my $result (@results)
	{
		$response .= '<li><a href="/webui/content/'.$result->{ID}.'">'.$result->{NAME}.' ('.'amount'.')</a></li>';

#		my $tmpid = substr($end_id, 0, length($id));
#		$response .= build_directory_tree ($dbh, $start_id, $end_id);
	}
	$response .= '</ul>';

	return $response;
}

1;
