package PDLNA::SSDP;
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

use Date::Format;
use IO::Socket::INET;
use IO::Socket::Multicast;
use Net::Netmask;

use PDLNA::Config;
use PDLNA::Log;

our $multicast_socket = undef;
our $multicast_listen_socket = undef;
our $multicast_group = '239.255.255.250';
our $ssdp_port = 1900;
our $ssdp_proto = 'udp';
our @NTS = (
	$CONFIG{'UUID'},
	'upnp:rootdevice',
	'urn:schemas-upnp-org:device:MediaServer:1',
	'urn:schemas-upnp-org:service:ContentDirectory:1',
	'urn:schemas-upnp-org:service:ConnectionManager:1',
);

sub add_sockets
{
	PDLNA::Log::log('Creating SSDP sending socket.', 1, 'discovery');
	# socket for sending NOTIFY messages
	$multicast_socket = IO::Socket::INET->new(
		LocalAddr => $CONFIG{'LOCAL_IPADDR'},
		PeerAddr => $multicast_group,
		PeerPort => $ssdp_port,
		Proto => $ssdp_proto,
		Blocking => 0,
	) || PDLNA::Log::fatal('Cannot bind to SSDP sending socket: '.$!);

	PDLNA::Log::log('Creating SSDP listening socket (bind '.$ssdp_proto.' '.$multicast_group.':'.$ssdp_port.').', 1, 'discovery');
	# socket for listening to M-SEARCH messages
	$multicast_listen_socket = IO::Socket::Multicast->new(
		Proto => $ssdp_proto,
		LocalPort => $ssdp_port,
	) || PDLNA::Log::fatal('Cannot bind to Multicast socket: '.$!);
	$multicast_listen_socket->mcast_if($CONFIG{'LISTEN_INTERFACE'});
	$multicast_listen_socket->mcast_loopback(0);
	$multicast_listen_socket->mcast_add(
		$multicast_group,
		$CONFIG{'LISTEN_INTERFACE'}
	) || PDLNA::Log::fatal('Cannot bind to SSDP listening socket: '.$!);
}

sub act_on_ssdp_message
{
	my $device_list = shift;

	PDLNA::Log::log('Starting SSDP messages receiver thread.', 1, 'discovery');
	while(1)
	{
		my $data = undef;
		my $peeraddr = $multicast_listen_socket->recv($data,1024);
		my ($peer_src_port, $peer_addr) = sockaddr_in($peeraddr);
		my $peer_ip_addr = inet_ntoa($peer_addr);

		# Check if the peer is one of our allowed clients
		my $client_allowed = 0;
		foreach my $block (@{$CONFIG{'ALLOWED_CLIENTS'}})
		{
			$client_allowed++ if $block->match($peer_ip_addr);
		}

		if ($client_allowed)
		{
			PDLNA::Log::log('Received SSDP message from allowed client IP '.$peer_ip_addr.'.', 2, 'discovery');
		}
		else
		{
			PDLNA::Log::log('Received SSDP message from NOT allowed client IP '.$peer_ip_addr.'.', 2, 'discovery');
			return;
		}

		if ($data =~ /NOTIFY/)
		{
			my $time = time();
			my $uuid = undef;
			my $ip = $peer_ip_addr;
			my $desc_location = undef;
			my $server_banner = undef;
			my $nts_type = undef;
			my $nt_type = undef;

			my @lines = split('\n', $data);
			foreach my $line (@lines)
			{
				# chomp the lines and also eliminate those \r's
				chomp($line);
				$line =~ s/\r//g;

				if ($line =~ /^NTS:\s*ssdp:(\w+)/i)
				{
					$nts_type = $1;
				}
				elsif ($line =~ /^CACHE-CONTROL:\s*max-age\s*=\s*(\d+)/i)
				{
					$time += $1;
				}
				elsif ($line =~ /^LOCATION:\s*(.*)/i)
				{
					$desc_location = $1;
				}
				elsif ($line =~ /^SERVER:\s*(.*)/i)
				{
					$server_banner = $1;
				}
				elsif ($line =~ /^USN:\s*(.*)/i)
				{
					my ($a, $b) = split('::', $1);
					$uuid = $a;
					$uuid =~ s/^uuid://;
				}
				elsif ($line =~ /^NT:\s*(.*)/i)
				{
					$nt_type = $1;
				}
			}

			if ($nts_type eq 'alive')
			{
				$$device_list->add({
					'ip' => $peer_ip_addr,
					'uuid' => $uuid,
					'ssdp_banner' => $server_banner,
					'desc_location' => $desc_location,
					'time_of_expire' => $time,
					'nt' => $nt_type,
				});
				PDLNA::Log::log('Adding UPnP device '.$uuid.' ('.$ip.') for '.$nt_type.' to database.', 2, 'discovery');
			}
			elsif ($nts_type eq 'byebye')
			{
				$$device_list->del($ip, $nt_type);
				PDLNA::Log::log('Deleting UPnP device '.$uuid.' ('.$ip.') for '.$nt_type.' from database.', 2, 'discovery');
			}
			PDLNA::Log::log($$device_list->print_object(), 3, 'discovery');
		}
		elsif ($data =~ /M-SEARCH/i) # we are matching case insensitive, because some clients don't write it capitalized
		{
			my @lines = split('\n', $data);

			my $man = undef;
			my $st = undef;
			my $mx = 3; # default MX is 3 seconds

			foreach my $line (@lines)
			{
				# chomp the lines and also eliminate those \r's
				chomp($line);
				$line =~ s/\r//g;

				if ($line =~ /^MAN:\s*(.+)$/i)
				{
					$man = $1;
				}
				elsif ($line =~ /^ST:\s*(.+)$/i)
				{
					$st = $1;
				}
				elsif ($line =~ /^MX:\s*(\d+)$/i)
				{
					$mx = $1;
				}
			}

			if (defined($man) && $man eq '"ssdp:discover"')
			{
				PDLNA::Log::log('Received a SSDP M-SEARCH message by '.$peer_ip_addr.':'.$peer_src_port.' for a '.$st.' with an mx of '.$mx.'.', 1, 'discovery');
				send_announce($peer_ip_addr, $peer_src_port, $st, $mx);
			}
		}
	}
}

sub ssdp_message
{
	my $params = shift;

	my $msg = '';

	$msg = "NOTIFY * HTTP/1.1\r\n" if $$params{'notify'};
	$msg = "HTTP/1.1 200 OK\r\n" if $$params{'response'};

	if ($$params{'nts'} eq 'alive' || $$params{'response'})
	{
		$msg .= "CACHE-CONTROL: max-age = ".$CONFIG{'CACHE_CONTROL'}."\r\n";
		$msg .= "EXT:\r\n" if $$params{'response'};
		$msg .= "LOCATION: http://".$CONFIG{'LOCAL_IPADDR'}.":".$CONFIG{'HTTP_PORT'}."/ServerDesc.xml\r\n";
	}
	if ($$params{'notify'})
	{
		$msg .= "HOST: ".$multicast_group.":".$ssdp_port."\r\n";
		$msg .= "NT: $$params{'nt'}\r\n";
		$msg .= "NTS: ssdp:$$params{'nts'}\r\n";
	}
	if ($$params{'nts'} eq 'alive' || $$params{'response'})
	{
		$msg .= "SERVER: ".$CONFIG{'OS'}."/".$CONFIG{'OS_VERSION'}.", UPnP/1.0, ".$CONFIG{'PROGRAM_NAME'}."/".$CONFIG{'PROGRAM_VERSION'}."\r\n";
	}
	$msg .= "ST: $$params{'st'}\r\n" if $$params{'response'};
	$msg .= "USN: $$params{'usn'}\r\n";
	if ($$params{'response'})
	{
		$msg .= "DATE: ".PDLNA::Utils::http_date()."\r\n";
		#$msg .= "CONTENT-LENGTH: 0\r\n";
	}
	$msg .= "\r\n";

	return $msg;
}

sub byebye
{
	PDLNA::Log::log('Sending SSDP byebye NOTIFY messages.', 1, 'discovery');
	for (1..2)
	{
		foreach my $nt (@NTS)
		{
			my $usn = $CONFIG{'UUID'};
			$usn .= '::'.$nt if $nt ne $usn;
			$multicast_socket->send(
				ssdp_message({
					'notify' => 1,
					'nt' => $nt,
					'nts' => 'byebye',
					'usn' => $usn,
				})
			);
		}
		sleeper(3);
	}
}

sub send_alive_periodic
{
	PDLNA::Log::log('Starting thread for sending periodic SSDP alive messages.', 1, 'discovery');
	while(1)
	{
		alive();
		sleeper($CONFIG{'CACHE_CONTROL'});
	}
}

sub generate_usn
{
	my $nt = shift;

	my $usn = $CONFIG{'UUID'};
	$usn .= '::'.$nt if $nt ne $CONFIG{'UUID'};

	return $usn;
}

sub alive
{
	PDLNA::Log::log('Sending SSDP alive NOTIFY messages.', 1, 'discovery');

	for (1..2)
	{
		foreach my $nt (@NTS)
		{
			$multicast_socket->send(
				ssdp_message({
					'notify' => 1,
					'nt' => $nt,
					'nts' => 'alive',
					'usn' => generate_usn($nt),
				})
			);
		}
		sleeper(3);
	}
}

sub send_announce
{
	my $destination_ip = shift; # client ip address
	my $destination_port = shift; # client original source port, which gets the destination port for the response so the discover
	my $stparam = shift; # type of service
	my $mx = shift; # sleep timer

	my @STS = ();
	foreach my $nts (@NTS)
	{
		push(@STS, $stparam) if $stparam eq $nts;
	}
	@STS = @NTS if $stparam eq "ssdp:all";

	foreach my $st (@STS)
	{
		PDLNA::Log::log('Sending SSDP M-SEARCH response messages for '.$st.'.', 1, 'discovery');
		my $data = ssdp_message({
			'response' => 1,
			'nts' => 'alive',
			'usn' => generate_usn($st),
			'st' => $st,
		});

		my $tmp = new IO::Socket::INET(
			'PeerAddr' => $destination_ip,
			'PeerPort' => $destination_port,
			'Proto' => $ssdp_proto,
			'LocalAddr' => $CONFIG{'LOCAL_IPADDR'},
		);

		for (1..2)
		{
			sleeper($mx);
			$multicast_listen_socket->mcast_if($CONFIG{'LISTEN_INTERFACE'});
			$multicast_listen_socket->mcast_loopback(0);
			$multicast_listen_socket->mcast_send($data, $destination_ip.":".$destination_port);
		}
	}
}

sub sleeper
{
	my $interval = shift;
	$interval = 3 unless defined($interval);
	sleep(int(rand($interval)));
}

1;
