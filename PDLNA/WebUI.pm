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
use GD::Graph::area;
use LWP::UserAgent;
use XML::Simple;

use PDLNA::Config;
use PDLNA::ContentLibrary;
use PDLNA::Database;
use PDLNA::Daemon;
use PDLNA::Statistics;
use PDLNA::Status;
use PDLNA::Utils;

sub show
{
	my $get_param = shift;

	my @nav = parse_nav($get_param);

	my $response = PDLNA::HTTPServer::http_header({
		'statuscode' => 200,
		'content_type' => 'text/html',
	});

	$response .= '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">'."\n";
	$response .= '<html>';
	$response .= '<head>';
	$response .= '<title>'.$CONFIG{'FRIENDLY_NAME'}.'</title>';
	$response .= '<script type="text/javascript" src="/webui/js.js"></script>';
	$response .= '<link href="/webui/css.css" rel="stylesheet" rev="stylesheet" type="text/css">';
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
		$response .= build_directory_tree( 0, $nav[1]);
	}
	else
	{
		$response .= build_directory_tree( 0, 0);
	}

	$response .= '<h5>Connected devices</h5>';
	$response .= build_connected_devices();

	$response .= '<h5>Statistics</h5>';
	$response .= '<ul>';
	$response .= '<li><a href="/webui/perf/pi">Process Information</a></li>';
	$response .= '<li><a href="/webui/perf/cl">Media Library Information</a></li>';
	$response .= '<li><a href="/webui/perf/pdlna">pDLNA Information</a></li>';
	$response .= '</ul>';
	$response .= '</div>';

	#
	# CONTENT ITSELF
	#

	$response .= '<div id="content">';
	if ($nav[0] eq 'content')
	{
		$response .= '<table>';
		$response .= '<thead>';
		$response .= '<tr><td>Filename</td><td width="110px">Size</td><td width="160px">Date</td></tr>';
		$response .= '</thead>';

		$response .= '<tfoot>';
		$response .= '<tr><td>&nbsp;</td><td>'.PDLNA::Utils::convert_bytes(PDLNA::Database::get_subfiles_size_by_id($nav[1])).'</td><td>&nbsp;</td></tr>';
		$response .= '</tfoot>';

		$response .= '<tbody>';
		my @files = ();
		PDLNA::Database::get_subfiles_by_id( $nav[1], undef, undef, \@files);
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
			my $device_ip = PDLNA::Database::device_ip_get_id($nav[1]);
			if (defined($device_ip->{IP}))
			{
				$response .= '<table>';
				$response .= '<thead>';
				$response .= '<tr><td>&nbsp;</td><td>Information</td></tr>';
				$response .= '</thead>';
				$response .= '<tbody>';
				$response .= '<tr><td>IP</td><td>'.$device_ip->{IP}.'</td></tr>';
				$response .= '<tr><td>HTTP UserAgent</td><td>'.$device_ip->{USER_AGENT}.'</td></tr>' if defined($device_ip->{USER_AGENT});
				$response .= '<tr><td>Last seen at</td><td>'.time2str($CONFIG{'DATE_FORMAT'}, $device_ip->{LAST_SEEN}).'</td></tr>';
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
			my $device_udn = PDLNA::Database::device_udn_get_record($nav[2]);
			if (defined($device_udn->{UDN}))
			{
				$response .= '<table>';
				$response .= '<thead>';
				$response .= '<tr><td>&nbsp;</td><td>Information</td></tr>';
				$response .= '</thead>';
				$response .= '<tbody>';
				$response .= '<tr><td>UDN</td><td>'.$device_udn->{UDN}.'</td></tr>';
				$response .= '<tr><td>SSDP Banner</td><td>'.$device_udn->{SSDP_BANNER}.'</td></tr>' if defined($device_udn->{SSDP_BANNER});
				$response .= '<tr><td>Friendly Name</td><td>'.$device_udn->{FRIENDLY_NAME}.'</td></tr>' if defined($device_udn->{FRIENDLY_NAME});
				$response .= '<tr><td>Model Name</td><td>'.$device_udn->{MODEL_NAME}.'</td></tr>' if defined($device_udn->{MODEL_NAME});
				$response .= '<tr><td>Device Type</td><td>'.$device_udn->{TYPE}.'</td></tr>' if defined($device_udn->{TYPE});
				$response .= '<tr><td>Device Description URL</td><td><a href="'.$device_udn->{DESC_URL}.'" target="_blank">'.$device_udn->{DESC_URL}.'</a></td></tr>' if defined($device_udn->{DESC_URL});
				$response .= '</tbody>';
				$response .= '</table>';

				$response .= '<p>&nbsp;</p>';

				$response .= '<table>';
				$response .= '<thead>';
				$response .= '<tr><td>NTS</td><td width="160px">expires at</td></tr>';
				$response .= '</thead>';
				$response .= '<tbody>';
				my @device_nts = PDLNA::Database::device_nts_get_records($nav[2]);
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
		my $pid = PDLNA::Daemon::read_pidfile($CONFIG{'PIDFILE'});
		my %proc_info = PDLNA::Statistics::get_proc_information();
		$response .= '<table>';
		$response .= '<thead>';
		$response .= '<tr><td>&nbsp;</td><td>Information</td></tr>';
		$response .= '</thead>';
		$response .= '<tbody>';
		$response .= '<tr><td>'.$CONFIG{'PROGRAM_NAME'}.' running with PID</td><td>'.$pid.'</td></tr>';
		$response .= '<tr><td>Parent PID of '.$CONFIG{'PROGRAM_NAME'}.'</td><td>'.$proc_info{'ppid'}.'</td></tr>';
		$response .= '<tr><td>'.$CONFIG{'PROGRAM_NAME'}.' started at</td><td>'.time2str($CONFIG{'DATE_FORMAT'}, $proc_info{'start'}).'</td></tr>';
		$response .= '<tr><td>'.$CONFIG{'PROGRAM_NAME'}.' running with priority</td><td>'.$proc_info{'priority'}.'</td></tr>';
		if ($CONFIG{'OS'} ne 'freebsd')
		{
			$response .= '<tr><td>CPU Utilization Since Process Started</td><td>'.$proc_info{'pctcpu'}.' %</td></tr>';
		}
			$response .= '<tr><td>Current Virtual Memory Size (VMS)</td><td>'.PDLNA::Utils::convert_bytes($proc_info{'vmsize'}).'</td></tr>';
			$response .= '<tr><td>Current Memory Utilization in RAM (RSS)</td><td>'.PDLNA::Utils::convert_bytes($proc_info{'rssize'}).'</td></tr>';
		if ($CONFIG{'OS'} ne 'freebsd')
		{
			$response .= '<tr><td>Current Memory Utilization</td><td>'.$proc_info{'pctmem'}.' %</td></tr>';
		}
		$response .= '</tbody>';
		$response .= '</table>';

		if ($CONFIG{'ENABLE_GENERAL_STATISTICS'})
		{
			$response .= show_graph(\@nav);
		}
	}
	elsif ($nav[0] eq 'perf' && $nav[1] eq 'cl')
	{
		$response .= '<table>';
		$response .= '<thead>';
		$response .= '<tr><td>&nbsp;</td><td>Information</td></tr>';
		$response .= '</thead>';
		$response .= '<tbody>';

                my $timestamp = PDLNA::Database::metadata_get_value('TIMESTAMP');
		$response .= '<tr><td>Timestamp</td><td>'.time2str($CONFIG{'DATE_FORMAT'}, $timestamp).'</td></tr>';

		my ($files_amount, $files_size) = PDLNA::Database::get_amount_size_of_items();
		$response .= '<tr><td>Media Items</td><td>'.$files_amount.' ('.PDLNA::Utils::convert_bytes($files_size).')</td></tr>';

                my $duration = PDLNA::Database::fileinfo_get_all_sumduration();
		$response .= '<tr><td>Length of all Media Items</td><td>'.PDLNA::Utils::convert_duration($duration).' ('.$duration.' seconds)</td></tr>';

		$response .= '<tr><td colspan="2">&nbsp;</td></tr>';

		foreach my $type ('image', 'audio', 'video')
		{
			my ($type_amount, $type_size) = PDLNA::Database::get_amount_size_of_items( $type);
			$response .= '<tr><td>'.ucfirst($type).' Items</td><td>'.$type_amount.' ('.PDLNA::Utils::convert_bytes($type_size).')</td></tr>';
		}

		$response .= '</tbody>';
		$response .= '</table>';

		if ($CONFIG{'ENABLE_GENERAL_STATISTICS'})
		{
			$response .= show_graph(\@nav);
		}
	}
	elsif ($nav[0] eq 'perf' && $nav[1] eq 'pdlna')
	{
		$response .= '<table>';
		$response .= '<thead>';
		$response .= '<tr><td>&nbsp;</td><td>Information</td></tr>';
		$response .= '</thead>';
		$response .= '<tbody>';
		$response .= '<tr><td>pDLNA Version</td><td>'.PDLNA::Config::print_version().'</td></tr>';
		$response .= '<tr><td>pDLNA Release Date</td><td>'.$CONFIG{'PROGRAM_DATE'}.'</td></tr>';
		$response .= '</tbody>';
		$response .= '</table>';

		$response .= '<form action="/webui/perf/pdlna/check4update" method="post">';
		$response .= '<div class="element button">';
		$response .= '<input type="submit" class="submit" value="Check4Updates" />';
		$response .= '</div>';
		$response .= '</form>';

		if (defined($nav[2]) && $nav[2] eq 'check4update')
		{
			my $http_response = PDLNA::Status::do_http_request();
			if ($http_response->is_success)
			{
				my $xml_obj = XML::Simple->new();
				my $xml = $xml_obj->XMLin($http_response->decoded_content());

				if ($xml->{'response'}->{'resultID'} == 1 || $xml->{'response'}->{'resultID'} == 2)
				{
					$response .= '<div class="error"><p>Check4Updates was not successful: Invalid Request.</p></div>';
				}
				elsif ($xml->{'response'}->{'resultID'} == 3)
				{
					$response .= '<div class="info"><p>You are running the latest version of '.$CONFIG{'PROGRAM_NAME'}.'.</p></div>';
				}
				elsif ($xml->{'response'}->{'resultID'} == 4)
				{
					$response .= '<div class="info">';
					$response .= '<p>A new version of '.$CONFIG{'PROGRAM_NAME'}.' is available: <strong>'.$xml->{'response'}->{'NewVersion'}.'</strong>.</p>';
					$response .= '<p>Check the <a href="http://www.pdlna.com/cgi-bin/index.pl?menu=changelog&release='.$xml->{'response'}->{'NewVersion'}.'">Changelog</a> section on the project website for detailed information.</p>';
					$response .= '</div>';
				}
			}
			else
			{
				$response .= '<div class="error"><p>Check4Updates was not successful: HTTP Status Code '.$http_response->status_line().'.</p></div>';
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

	return $response;
}

sub javascript
{
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
	return join("\n", @javascript);
}

sub css
{
	my @css = (
		'body{',
		'font-family: "lucida grande", verdana, sans-serif;',
		'font-size: 10pt;',
		'color: #3d80df;',
		'}',
		'#container{',
		'width: 960px;',
		'margin-left: auto;',
		'margin-right: auto;',
		'border: 1px solid #3d80df;',
		'margin-top: 50px;',
		'}',
		'#content{',
		'float: left;',
		'width: 620px;',
		'padding-bottom: 20px;',
		'}',
		'#sidebar{',
		'float: left;',
		'width: 340px;',
		'background-color: #3d80df;',
		'padding-bottom: 20px;',
		'}',
		'#footer{',
		'clear:both;',
		'height: 40px;',
		'color: #fff;',
		'background-color: #3d80df;',
		'text-align: center;',
		'line-height: 3em;',
		'}',
		'div.graph{',
		'margin-top: 20px;',
		'margin-left: 10px;',
		'padding: 10px 10px 10px 10px;',
		'width: 580px;',
		'border: 1px solid #3d80df;',
		'}',
		'div.graphnav{',
		'margin-top: 0px;',
		'margin-left: 10px;',
		'background-color: #3d80df;',
		'padding: 0px 10px 0px 10px;',
		'width: 580px;',
		'height: 20px;',
		'border: 1px solid #3d80df;',
		'text-align: right;',
		'}',
		'div.graphnav p{',
		'color: #fff;',
		'margin-top: 1px;',
		'}',
		'h3{',
		'font-size: 12pt;',
		'text-align: center;',
		'}',
		'h5{',
		'color: #fff;',
		'font-size: 12pt;',
		'text-align: center;',
		'margin-bottom: -10px;',
		'}',
		'a{',
		'color: #fff;',
		'}',
		'div.info p a{',
		'color: #3d80df;',
		'}',
		'table{',
		'width: 600px;',
		'border: 1px solid #7DAAEA;',
		'margin-left: auto;',
		'margin-right: auto;',
		'}',
		'tr td{',
		'padding: 3px 8px;',
		'background: #fff;',
		'}',
		'thead td{',
		'color: #fff;',
		'background-color: #3d80df;',
		'font-weight: bold;',
		'border-bottom: 0px solid #999;',
		'text-align: center;',
		'}',
		'tfoot td{',
		'color: #fff;',
		'background-color: #3d80df;',
		'font-weight: bold;',
		'border-bottom: 0px solid #999;',
		'text-align: center;',
		'}',
		'tbody td{',
		'border-left: 0px solid #3d80df;',
		'}',
		'tbody td a{',
		'color: #3d80df;',
		'}',
		'tbody tr.even td{',
		'background: #eee;',
		'}',
		'tbody tr.ruled td{',
		'color: #000;',
		'background-color: #C6E3FF;',
		'}',
		'li{',
		'display: block;',
		'margin-left: -15px;',
		'}',
		'div.info, div.success, div.error{',
		'width: 600px;',
		'border: 1px solid;',
		'margin-left: auto;',
		'margin-right: auto;',
		'}',
		'div.success{',
		'color: #4F8A10;',
		'background-color: #DFF2BF;',
		'}',
		'div.info{',
		'color: #00529B;',
		'background-color: #BDE5F8;',
		'}',
		'div.error{',
		'color: #D8000C;',
		'background-color: #ffbaba;',
		'}',
		'div.info p, div.success p, div.error p{',
		'padding-left: 20px;',
		'padding-right: 20px;',
		'}',
		'div.element{',
		'}',
		'div.element.button{',
		'height: 60px;',
		'width: 600px;',
		'text-align: right;',
		'}',
		'div.element.button input{',
		'margin-top: 15px;',
		'background-color: #3d80df;',
		'color: #ffffff;',
		'font-weight: bold;',
		'height: 28px;',
		'text-align: center;',
		'width: 165px;',
		'}',
	);
	return join("\n", @css);
}

#
# NAVIGATION
#

sub parse_nav
{
	my $param = shift;

	my @nav = split('/', $param);
	if (!defined($nav[0]) || $nav[0] !~ /^(content|device|perf)$/)
	{
		$nav[0] = 'content';
		$nav[1] = 0;
	}
	if ($nav[0] eq 'content' && (!defined($nav[1]) || $nav[1] !~ /^\d+$/))
	{
		$nav[1] = 0;
	}

	if ($CONFIG{'ENABLE_GENERAL_STATISTICS'})
	{
		$nav[2] = 'memory' if $nav[1] eq 'pi';
		$nav[2] = 'media' if $nav[1] eq 'cl';

		$nav[3] = 'day' unless defined($nav[3]);
	}

	return @nav;
}

sub build_directory_tree
{
	my $start_id = shift;
	my $end_id = shift;
	$end_id = 0 if $end_id !~ /^(\d+)$/;

	my $response = '';

	my @results = ();
	PDLNA::Database::get_subdirectories_by_id( $start_id, undef, undef, \@results);

	$response .= '<ul>';
	foreach my $result (@results)
	{
		$response .= '<li><a href="/webui/content/'.$result->{ID}.'">'.$result->{NAME}.' ('.PDLNA::ContentLibrary::get_amount_elements_by_id( $result->{ID}).')</a></li>';
		if (PDLNA::ContentLibrary::is_in_same_directory_tree( $result->{ID}, $end_id))
		{
			$response .= build_directory_tree( $result->{ID}, $end_id);
		}
	}
	$response .= '</ul>';

	return $response;
}

sub build_connected_devices
{
	my $response = '';

	my @devices_ip = PDLNA::Database::device_ip_select_all();
	$response .= '<ul>';
	foreach my $device_ip (@devices_ip)
	{
		$response .= '<li><a href="/webui/device/'.$device_ip->{ID}.'">'.$device_ip->{IP}.'</a></li>';
		my @devices_udn = PDLNA::Database::device_udn_select_by_ip($device_ip->{ID});
		$response .= '<ul>';
		foreach my $device_udn (@devices_udn)
		{
			$response .= '<li><a href="/webui/device/'.$device_ip->{ID}.'/'.$device_udn->{ID}.'">'.$device_udn->{UDN}.'</a></li>';
		}
		$response .= '</ul>';
	}
	$response .= '</ul>';

	return $response;
}

sub show_graph
{
	my $nav = shift;

	my $response = '';
	$response .= '<div class="graph">';
	$response .= '<img src="/webui/graphs/'.$$nav[2].'_'.$$nav[3].'.png" />';
	$response .= '</div>';
	$response .= '<div class="graphnav">';
	$response .= '<p>|';
	foreach my $period ('day', 'month', 'year')
	{
		$response .= ' <a href="/webui/'.$$nav[0].'/'.$$nav[1].'/'.$$nav[2].'/'.$period.'">';
		if ($period eq $$nav[3])
		{
			$response .= '<strong>'.$period.'</strong></a> |';
		}
		else
		{
			$response .= $period.'</a> |';
		}
	}
	$response .= '</p>';
	$response .= '</div>';

	return $response;
}

sub graph
{
	my $param = shift;
	my ($type, $period) = split(/_/, $param);

	if ($type !~ /^(memory|media)$/)
	{
		return PDLNA::HTTPServer::http_header({
			'statuscode' => 404,
		});
	}
	if ($period !~ /^(day|month|year)$/)
	{
		return PDLNA::HTTPServer::http_header({
			'statuscode' => 404,
		});
	}

	#
	# DATA DEFINITION
	#

	my %data_options = ();

	$data_options{'dateformatstring'} = '%Y-%m-%d %H:00' if $period eq 'day';
	$data_options{'dateformatstring'} = '%Y-%m-%d' if $period eq 'month';
	$data_options{'dateformatstring'} = '%Y-%m' if $period eq 'year';

	$data_options{'title'} = 'Memory usage' if $type eq 'memory';
	$data_options{'title'} = 'Media items' if $type eq 'media';

	$data_options{'dbtable'} = 'STAT_MEM' if $type eq 'memory';
	$data_options{'dbtable'} = 'STAT_ITEMS' if $type eq 'media';

	$data_options{'title'} .= ' by current '.$period;

	$data_options{'dbfields'} = [ 'AVG(VMS)', 'AVG(RSS)', ] if $type eq 'memory';
	$data_options{'dbfields'} = [ 'AVG(AUDIO)', 'AVG(IMAGE)', 'AVG(VIDEO)', ] if $type eq 'media';

	$data_options{'y_label'} = 'Bytes' if $type eq 'memory';

	#
	# GD GRAPH DEFINITION
	#

	my %options = (
		textclr => '#3d80df',
		labelclr => '#3d80df',
		axislabelclr => '#3d80df',
		fgclr => '#3d80df',
		boxclr => '#ffffff',
		dclrs => [
#			'#8ab2eb',
#			'#77a6e8',
#			'#6399e5',
#			'#508ce2',
			'#3d80df',
#			'#3673c8',
			'#3066b2',
#			'#2a599c',
			'#244c85',
#			'#1e406f',
			'#183359',
#			'#122642',
			'#0c192c',
#			'#060c16',
		],
		long_ticks => 1,
		y_min_value => 0,
		x_labels_vertical => 1,
		title => $data_options{'title'},
		y_label => $data_options{'y_label'},
	);

	my $graph = GD::Graph::area->new(580, 300);
	$graph->set(%options);
	$graph->set_legend_font(GD::gdMediumBoldFont);
	$graph->set_title_font(GD::gdMediumBoldFont);
	$graph->set_x_axis_font(GD::gdMediumBoldFont);
	$graph->set_y_axis_font(GD::gdMediumBoldFont);
	$graph->set_legend(@{$data_options{'dbfields'}});

	#
	# DATA GATHERING
	#


	my @results = PDLNA::Database::stats_getdata($data_options{'dateformatstring'},$data_options{'dbtable'},$period,@{$data_options{'dbfields'}});

	my @data = ();
	for (my $i = 0; $i < @results; $i++)
	{
		$data[0][$i] = $results[$i]->{datetime};
		my $j = 1;
		foreach my $field (@{$data_options{'dbfields'}})
		{
			$data[$j][$i] = $results[$i]->{$field};
			$j++;
		}
	}


	#
	# deliver the graph to the browser
	#

	my $image = $graph->plot(\@data) or die $graph->error;
	my $response = PDLNA::HTTPServer::http_header({
		'statuscode' => 200,
		'content_type' => 'image/png',
	});
	$response .= $image->png();

	return $response;
}

1;
