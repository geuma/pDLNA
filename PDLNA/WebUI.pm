package PDLNA::WebUI;
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

use Date::Format;
use Devel::Size qw(size total_size);
use Proc::ProcessTable;

use PDLNA::Config;
use PDLNA::ContentLibrary;
use PDLNA::Database;
use PDLNA::Daemon;
use PDLNA::Utils;

sub show
{
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
	if ($nav[0] eq 'content')
	{
		$response .= build_directory_tree($dbh, 0, $nav[1]);
	}
	else
	{
		$response .= build_directory_tree($dbh, 0, 0);
	}

	$response .= '<h5>Connected devices</h5>';
	my @devices_ip = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT ID, IP FROM DEVICE_IP',
			'parameters' => [ ],
		},
		\@devices_ip,
	);
	$response .= '<ul>';
	foreach my $device_ip (@devices_ip)
	{
		$response .= '<li><a href="/webui/device/'.$device_ip->{ID}.'">'.$device_ip->{IP}.'</a></li>';
		my @devices_udn = ();
		PDLNA::Database::select_db(
			$dbh,
			{
				'query' => 'SELECT ID, UDN FROM DEVICE_UDN WHERE DEVICE_IP_REF = ?',
				'parameters' => [ $device_ip->{ID}, ],
			},
			\@devices_udn,
		);
		$response .= '<ul>';
		foreach my $device_udn (@devices_udn)
		{
			$response .= '<li><a href="/webui/device/'.$device_ip->{ID}.'/'.$device_udn->{ID}.'">'.$device_udn->{UDN}.'</a></li>';
		}
		$response .= '</ul>';
	}
	$response .= '</ul>';

	$response .= '<h5>Statistics</h5>';
	$response .= '<ul>';
	$response .= '<li><a href="/webui/perf/pi">Process Information</a></li>';
	$response .= '<li><a href="/webui/perf/cl">Media Library Information</a></li>';
	$response .= '</ul>';
	$response .= '</div>';

	$response .= '<div id="content">';
	if ($nav[0] eq 'content')
	{
		$response .= '<table>';
		$response .= '<thead>';
		$response .= '<tr><td>Filename</td><td width="110px">Size</td><td width="160px">Date</td></tr>';
		$response .= '</thead>';

		$response .= '<tfoot>';
		$response .= '<tr><td>&nbsp;</td><td>'.PDLNA::Utils::convert_bytes(PDLNA::ContentLibrary::get_subfiles_size_by_id($dbh, $nav[1])).'</td><td>&nbsp;</td></tr>';
		$response .= '</tfoot>';

		$response .= '<tbody>';
		my @files = ();
		PDLNA::ContentLibrary::get_subfiles_by_id($dbh, $nav[1], undef, undef, \@files);
		foreach my $id (@files)
		{
			$response .= '<tr>';
			$response .= '<td title="'.$id->{NAME}.'">'.PDLNA::Utils::string_shortener($id->{NAME}, 30).'</td>';
			$response .= '<td>'.PDLNA::Utils::convert_bytes($id->{SIZE}).'</td>';
			$response .= '<td>'.time2str($CONFIG{'DATE_FORMAT'}, $id->{DATE}).'</td>';
			$response .= '</tr>';
		}
		$response .= '</tbody>';

		$response .= '</table>';
	}
	elsif ($nav[0] eq 'device')
	{
		if (defined($nav[1]) && !defined($nav[2]))
		{
			my @device_ip = ();
			PDLNA::Database::select_db(
				$dbh,
				{
					'query' => 'SELECT IP, USER_AGENT, LAST_SEEN FROM DEVICE_IP WHERE ID = ?',
					'parameters' => [ $nav[1], ],
				},
				\@device_ip,
			);

			if (defined($device_ip[0]->{IP}))
			{
				$response .= '<table>';
				$response .= '<thead>';
				$response .= '<tr><td>&nbsp;</td><td>Information</td></tr>';
				$response .= '</thead>';
				$response .= '<tbody>';
				$response .= '<tr><td>IP</td><td>'.$device_ip[0]->{IP}.'</td></tr>';
				$response .= '<tr><td>HTTP UserAgent</td><td>'.$device_ip[0]->{USER_AGENT}.'</td></tr>' if defined($device_ip[0]->{USER_AGENT});
				$response .= '<tr><td>Last seen at</td><td>'.time2str($CONFIG{'DATE_FORMAT'}, $device_ip[0]->{LAST_SEEN}).'</td></tr>';
				$response .= '</tbody>';
				$response .= '</table>';
			}
			else
			{
				$response .= '<p>No information available.</p>';
			}
		}
		elsif (defined($nav[1]) && defined($nav[2]))
		{
			my @device_udn = ();
			PDLNA::Database::select_db(
				$dbh,
				{
					'query' => 'SELECT UDN, SSDP_BANNER, FRIENDLY_NAME, MODEL_NAME, TYPE, DESC_URL FROM DEVICE_UDN WHERE ID = ?',
					'parameters' => [ $nav[2], ],
				},
				\@device_udn,
			);

			if (defined($device_udn[0]->{UDN}))
			{
				$response .= '<table>';
				$response .= '<thead>';
				$response .= '<tr><td>&nbsp;</td><td>Information</td></tr>';
				$response .= '</thead>';
				$response .= '<tbody>';
				$response .= '<tr><td>UDN</td><td>'.$device_udn[0]->{UDN}.'</td></tr>';
				$response .= '<tr><td>SSDP Banner</td><td>'.$device_udn[0]->{SSDP_BANNER}.'</td></tr>' if defined($device_udn[0]->{SSDP_BANNER});
				$response .= '<tr><td>Friendly Name</td><td>'.$device_udn[0]->{FRIENDLY_NAME}.'</td></tr>' if defined($device_udn[0]->{FRIENDLY_NAME});
				$response .= '<tr><td>Model Name</td><td>'.$device_udn[0]->{MODEL_NAME}.'</td></tr>' if defined($device_udn[0]->{MODEL_NAME});
				$response .= '<tr><td>Device Type</td><td>'.$device_udn[0]->{TYPE}.'</td></tr>' if defined($device_udn[0]->{TYPE});
				$response .= '<tr><td>Device Description URL</td><td><a href="'.$device_udn[0]->{DESC_URL}.'" target="_blank">'.$device_udn[0]->{DESC_URL}.'</a></td></tr>' if defined($device_udn[0]->{DESC_URL});
				$response .= '</tbody>';
				$response .= '</table>';

				$response .= '<p>&nbsp;</p>';

				$response .= '<table>';
				$response .= '<thead>';
				$response .= '<tr><td>NTS</td><td width="160px">expires at</td></tr>';
				$response .= '</thead>';
				$response .= '<tbody>';
				my @device_nts = ();
				PDLNA::Database::select_db(
					$dbh,
					{
						'query' => 'SELECT TYPE, EXPIRE FROM DEVICE_NTS WHERE DEVICE_UDN_REF = ?',
						'parameters' => [ $nav[2], ],
					},
					\@device_nts,
				);
				foreach my $nts (@device_nts)
				{
					$response .= '<tr><td>'.$nts->{TYPE}.'</td><td>'.time2str($CONFIG{'DATE_FORMAT'}, $nts->{EXPIRE}).'</td></tr>';
				}
				$response .= '</tbody>';
				$response .= '</table>';
			}
			else
			{
				$response .= '<p>No information available.</p>';
			}
		}
	}
	elsif ($nav[0] eq 'perf' && $nav[1] eq 'pi')
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
				$response .= '</tbody>';
				$response .= '</table>';
			}
		}
	}
	elsif ($nav[0] eq 'perf' && $nav[1] eq 'cl')
	{
		my @results = ();
		PDLNA::Database::select_db(
			$dbh,
			{
				'query' => 'SELECT COUNT(*) AS AMOUNT, SUM(SIZE) AS SIZE FROM FILES',
				'parameters' => [ ],
			},
			\@results,
		);

		my @results2 = ();
		PDLNA::Database::select_db(
			$dbh,
			{
				'query' => 'SELECT TYPE, COUNT(*) AS AMOUNT, SUM(SIZE) AS SIZE FROM FILES GROUP BY TYPE',
				'parameters' => [ ],
			},
			\@results2,
		);

		$response .= '<table>';
		$response .= '<thead>';
		$response .= '<tr><td>&nbsp;</td><td>Information</td></tr>';
		$response .= '</thead>';
		$response .= '<tbody>';
		$response .= '<tr><td>Media Items</td><td>'.$results[0]->{AMOUNT}.' ('.PDLNA::Utils::convert_bytes($results[0]->{SIZE}).')</td></tr>';
		$response .= '<tr><td colspan="2">&nbsp;</td></tr>';
		foreach my $result (@results2)
		{
			$response .= '<tr><td>'.ucfirst($result->{TYPE}).' Items</td><td>'.$result->{AMOUNT}.' ('.PDLNA::Utils::convert_bytes($result->{SIZE}).')</td></tr>';
		}
		$response .= '</tbody>';
		$response .= '</table>';
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
	$end_id = 0 if $end_id !~ /^(\d+)$/;

	my $response = '';

	my @results = ();
	PDLNA::ContentLibrary::get_subdirectories_by_id($dbh, $start_id, undef, undef, \@results);

	$response .= '<ul>';
	foreach my $result (@results)
	{
		$response .= '<li><a href="/webui/content/'.$result->{ID}.'">'.$result->{NAME}.' ('.PDLNA::ContentLibrary::get_amount_elements_by_id($dbh, $result->{ID}).')</a></li>';
		if (PDLNA::ContentLibrary::is_in_same_directory_tree($dbh, $result->{ID}, $end_id))
		{
			$response .= build_directory_tree($dbh, $result->{ID}, $end_id);
		}
	}
	$response .= '</ul>';

	return $response;
}

1;
