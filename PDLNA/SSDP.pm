package PDLNA::SSDP;
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010 Stefan Heumader <stefan@heumader.at>
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

use IO::Socket::INET;
use IO::Socket::Multicast;

use PDLNA::Config;
use PDLNA::Log;

our $multicast_socket = undef;
our $multicast_listen_socket = undef;
our @NTS = (
	$CONFIG{'UUID'},
	'upnp:rootdevice',
	'urn:schemas-upnp-org:device:MediaServer:1',
	'urn:schemas-upnp-org:service:ContentDirectory:1',
	'urn:schemas-upnp-org:service:ConnectionManager:1',
#	'urn:microsoft.com:service:X_MS_MediaReceiverRegistrar:1',
);

sub add_sockets
{
	PDLNA::Log::log("Creating SSDP sending socket.", 1);
	# socket for sending NOTIFY messages
	$multicast_socket = IO::Socket::INET->new(
		LocalAddr => $CONFIG{'LOCAL_IPADDR'},
		PeerAddr => '239.255.255.250',
		PeerPort => 1900,
		Proto => 'udp',
		Blocking => 0,
	) || die "Can't bind to SSDP sending socket: $!\n";;

	PDLNA::Log::log("Creating SSDP listening socket (bind UDP 239.255.255.250:1900).", 1);
	# socket for listening to M-SEARCH messages
	$multicast_listen_socket = IO::Socket::Multicast->new(
		Proto => 'udp',
		LocalPort => 1900,
	);
	$multicast_listen_socket->mcast_if($CONFIG{'LISTEN_INTERFACE'});
	$multicast_listen_socket->mcast_loopback(0);
	$multicast_listen_socket->mcast_add('239.255.255.250', $CONFIG{'LISTEN_INTERFACE'}) || die "Can't bind to SSDP listening socket: $!\n";
}

sub act_on_ssdp_message
{
	PDLNA::Log::log("Starting SSDP messages receiver thread.", 1);
	while(1)
	{
	    my $data = undef;
		my $peeraddr = $multicast_listen_socket->recv($data,1024);
		my ($peer_src_port, $peer_addr) = sockaddr_in($peeraddr);
	    my $peer_ip_addr = inet_ntoa($peer_addr);

		if ($data =~ /NOTIFY/)
		{
			# we are ignoring those NOTIFY messages
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

				if ($line =~ /^MAN:\s+(.+)$/i)
				{
					$man = $1;
				}
				if ($line =~ /^ST:\s+(.+)$/i)
				{
					$st = $1;
				}
				if ($line =~ /^MX:\s+(\d+)$/i)
				{
					$mx = $1;
				}
			}

			if (defined($man) && $man eq '"ssdp:discover"')
			{
				PDLNA::Log::log("Received a SSDP M-SEARCH message by ".$peer_ip_addr.":".$peer_src_port." for a $st with an mx of $mx.", 1);
				send_announce($peer_ip_addr, $peer_src_port, $st, $mx);
			}

		}
	}
}

sub byebye
{
	PDLNA::Log::log("Sending SSDP byebye NOTIFY messages.", 1);
	for (1..2)
	{
		foreach my $nt (@NTS)
		{
			my $usn = $CONFIG{'UUID'};
			$usn .= '::'.$nt if $nt ne $usn;
			$multicast_socket->send("NOTIFY * HTTP/1.1\r\n".
									"HOST: 239.255.255.250:1900\r\n".
									"NT: $nt\r\n".
									"NTS: ssdp:byebye\r\n".
									"USN: ".$usn."\r\n".
									"\r\n"
			);
		}
		sleeper(3);
	}
}

sub send_alive_periodic
{
	PDLNA::Log::log("Starting thread for sending peridic SSDP alive messages.", 1);
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
}

sub alive
{
	PDLNA::Log::log("Sending SSDP alive NOTIFY messages.", 1);

	for (1..2)
	{
		foreach my $nt (@NTS)
		{
			$multicast_socket->send("NOTIFY * HTTP/1.1\r\n".
									"HOST: 239.255.255.250:1900\r\n".
									"CACHE-CONTROL: max-age = ".$CONFIG{'CACHE_CONTROL'}."\r\n".
									"LOCATION: http://".$CONFIG{'LOCAL_IPADDR'}.":".$CONFIG{'HTTP_PORT'}."/ServerDesc.xml\r\n".
									"NT: $nt\r\n".
									"NTS: ssdp:alive\r\n".
									"SERVER: ".$CONFIG{'OS'}."/".$CONFIG{'OS_VERSION'}." UPnP/1.0 ".$CONFIG{'PROGRAM_NAME'}."/".$CONFIG{'PROGRAM_VERSION'}."\r\n".
									"USN: ".generate_usn($nt)."\r\n".
									"\r\n"
			);
		}
		sleeper(3);
	}
}

sub send_announce
{
	my $destination_ip = shift; # client ip address
	my $destination_port = shift; # client original source port, which gets the destination port for the response so the discover
	my $st = shift; # type of service
	my $mx = shift; # sleep timer

	my $send_announce = 0;
	foreach my $nts (@NTS)
	{
		$send_announce = 1 if $st eq $nts;
	}
	$send_announce = 1 if $st eq "ssdp::all";

	if ($send_announce)
	{
		PDLNA::Log::log("Sending SSDP M-SEARCH response messages.", 1);

		my $data = "HTTP/1.1 200 OK\r\n".
					"CACHE-CONTROL: max-age = ".$CONFIG{'CACHE_CONTROL'}."\r\n".
					"EXT:\r\n".
					"LOCATION: http://".$CONFIG{'LOCAL_IPADDR'}.":".$CONFIG{'HTTP_PORT'}."/ServerDesc.xml\r\n".
					"SERVER: ".$CONFIG{'OS'}."/".$CONFIG{'OS_VERSION'}." UPnP/1.0 ".$CONFIG{'PROGRAM_NAME'}."/".$CONFIG{'PROGRAM_VERSION'}."\r\n".
					"ST: "."$st"."\r\n".
					"USN: ".generate_usn($st)."\r\n".
#					"Date: ".."\r\n". # "%a, %d %b %Y %H:%M:%S GMT"
					"CONTENT-LENGTH: 0\r\n".
					"\r\n";

		my $tmp = new IO::Socket::INET(
			'PeerAddr' => $destination_ip,
			'PeerPort' => $destination_port,
			'Proto' => 'udp',
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
