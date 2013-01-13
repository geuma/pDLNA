package PDLNA::SSDP;
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

#use threads;

use IO::Socket::INET;
use IO::Socket::Multicast;
use Net::Netmask;

use PDLNA::Config;
use PDLNA::Log;
use PDLNA::DeviceList;

sub new
{
	my $class = shift;

	my $self = ();
	$self->{DEVICE_LIST} = shift;
	$self->{NTS} = [
		$CONFIG{'UUID'},
		'upnp:rootdevice',
		'urn:schemas-upnp-org:device:MediaServer:1',
		'urn:schemas-upnp-org:service:ContentDirectory:1',
		'urn:schemas-upnp-org:service:ConnectionManager:1',
	];
	$self->{MULTICAST_SEND_SOCKET} = undef;
	$self->{MULTICAST_LISTEN_SOCKET} = undef;

	$self->{PORT} = 1900;
	$self->{PROTO} = 'udp';
	$self->{MULTICAST_GROUP} = '239.255.255.250';

	bless($self, $class);
	return $self;
}

sub add_send_socket
{
	my $self = shift;

	PDLNA::Log::log('Creating SSDP sending socket.', 1, 'discovery');
	$self->{MULTICAST_SEND_SOCKET} = IO::Socket::INET->new(
		LocalAddr => $CONFIG{'LOCAL_IPADDR'},
		PeerAddr => $self->{MULTICAST_GROUP},
		PeerPort => $self->{PORT},
		Proto => $self->{PROTO},
		Blocking => 0,
		#ReuseAddr => 1,
	) || PDLNA::Log::fatal('Cannot bind to SSDP sending socket: '.$!);
}

sub add_receive_socket
{
	my $self = shift;

	PDLNA::Log::log('Creating SSDP listening socket (bind '.$self->{PROTO}.' '.$self->{MULTICAST_GROUP}.':'.$self->{PORT}.').', 1, 'discovery');
	# socket for listening to M-SEARCH messages
	$self->{MULTICAST_LISTEN_SOCKET} = IO::Socket::Multicast->new(
		Proto => $self->{PROTO},
		LocalPort => $self->{PORT},
		#ReuseAddr => 1,
	) || PDLNA::Log::fatal('Cannot bind to Multicast socket: '.$!);
	$self->{MULTICAST_LISTEN_SOCKET}->mcast_if($CONFIG{'LISTEN_INTERFACE'});
	$self->{MULTICAST_LISTEN_SOCKET}->mcast_loopback(0);
	$self->{MULTICAST_LISTEN_SOCKET}->mcast_add(
		$self->{MULTICAST_GROUP},
		$CONFIG{'LISTEN_INTERFACE'}
	) || PDLNA::Log::fatal('Cannot bind to SSDP listening socket: '.$!);
}

sub send_byebye
{
	my $self = shift;
	my $amount = shift || 2;

    PDLNA::Log::log('Sending SSDP byebye NOTIFY messages.', 1, 'discovery');
	for (1..$amount)
	{
		foreach my $nt (@{$self->{NTS}})
		{
			$self->{MULTICAST_SEND_SOCKET}->send(
				$self->ssdp_message({
					'notify' => 1,
					'nt' => $nt,
					'nts' => 'byebye',
					'usn' => generate_usn($nt),
				})
			);
		}
		sleeper(3);
	}
}

sub send_alive
{
	my $self = shift;
	my $amount = shift || 2;

	PDLNA::Log::log('Sending SSDP alive NOTIFY messages.', 1, 'discovery');

	for (1..$amount)
	{
		foreach my $nt (@{$self->{NTS}})
		{
			$self->{MULTICAST_SEND_SOCKET}->send(
				$self->ssdp_message({
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
	my $self = shift;

	my $destination_ip = shift; # client ip address
	my $destination_port = shift; # client original source port, which gets the destination port for the response so the discover
	my $stparam = shift; # type of service
	my $mx = shift; # sleep timer

	# well, some devices seem to send M-SEARCH messages with a really large MX
	# let us work around that the following way
	$mx = 10 if $mx > 10;

	my @STS = ();
	foreach my $nts (@{$self->{NTS}})
	{
		push(@STS, $stparam) if $stparam eq $nts;
	}
	@STS = @{$self->{NTS}} if $stparam eq "ssdp:all";

	foreach my $st (@STS)
	{
		PDLNA::Log::log('Sending SSDP M-SEARCH response messages for '.$st.'.', 1, 'discovery');
		my $data = $self->ssdp_message({
			'response' => 1,
			'nts' => 'alive',
			'usn' => generate_usn($st),
			'st' => $st,
		});

		for (1..2)
		{
			sleeper($mx);
			$self->{MULTICAST_LISTEN_SOCKET}->mcast_if($CONFIG{'LISTEN_INTERFACE'});
			$self->{MULTICAST_LISTEN_SOCKET}->mcast_loopback(0);
			$self->{MULTICAST_LISTEN_SOCKET}->mcast_send($data, $destination_ip.":".$destination_port);
		}
	}
}

sub start_sending_periodic_alive_messages_thread
{
	my $self = shift;

	PDLNA::Log::log('Starting thread for sending periodic SSDP alive messages.', 1, 'discovery');
	my $thread = threads->create(
		sub
		{
			$self->send_periodic_alive_messages();
		}
	);
	$thread->detach();
}

sub send_periodic_alive_messages
{
	my $self = shift;

	while(1)
	{
		$self->send_alive(2);
		${$self->{DEVICE_LIST}}->delete_expired();
		sleeper($CONFIG{'CACHE_CONTROL'});
	}
}

sub start_listening_thread
{
	my $self = shift;

	PDLNA::Log::log('Starting SSDP messages receiver thread.', 1, 'discovery');
	my $thread = threads->create(
		sub
		{
			$self->receive_messages();
		}
	);
	$thread->detach();
}

sub receive_messages
{
	my $self = shift;

	while(1)
	{
		my $data = undef;

		my $peeraddr = $self->{MULTICAST_LISTEN_SOCKET}->recv($data,1024);

		return unless defined($peeraddr); # received multicast packets without content??

		my ($peer_src_port, $peer_addr) = sockaddr_in($peeraddr) if defined($peeraddr);
		my $peer_ip_addr = inet_ntoa($peer_addr) if defined($peer_addr);

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
			next;
		}

		if ($data =~ /NOTIFY/)
		{
			my $time = time();
			my $uuid = undef;
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
				# we will not add the running pDLNA installation to our SSDP database
				if ($peer_ip_addr ne $CONFIG{'LOCAL_IPADDR'} && $uuid ne $CONFIG{'UUID'})
				{
					PDLNA::Log::log('Adding UPnP device '.$uuid.' ('.$peer_ip_addr.') for '.$nt_type.' to database.', 2, 'discovery');

					${$self->{DEVICE_LIST}}->add({
						'ip' => $peer_ip_addr,
						'udn' => $uuid,
						'ssdp_banner' => $server_banner,
						'device_description_location' => $desc_location,
						'nt' => $nt_type,
						'nt_time_of_expire' => $time,
					});
				}
				else
				{
					PDLNA::Log::log('Ignored SSDP message from allowed client IP '.$peer_ip_addr.', because the message came from this running '.$CONFIG{'PROGRAM_NAME'}.' installation.', 2, 'discovery');
				}
			}
			elsif ($nts_type eq 'byebye')
			{
				PDLNA::Log::log('Deleting UPnP device '.$uuid.' ('.$peer_ip_addr.') for '.$nt_type.' from database.', 2, 'discovery');
				${$self->{DEVICE_LIST}}->del(
					{
						'ip' => $peer_ip_addr,
						'udn' => $uuid,
						'nt' => $nt_type,
					},
				);
			}
			PDLNA::Log::log(${$self->{DEVICE_LIST}}->print_object(), 3, 'discovery');
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
				# TODO start function in a thread - currently this is a blocking implementation
				$self->send_announce($peer_ip_addr, $peer_src_port, $st, $mx);
			}
		}
	}
}

sub ssdp_message
{
	my $self = shift;
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
		$msg .= "HOST: ".$self->{MULTICAST_GROUP}.":".$self->{PORT}."\r\n";
		$msg .= "NT: $$params{'nt'}\r\n";
		$msg .= "NTS: ssdp:$$params{'nts'}\r\n";
	}
	if ($$params{'nts'} eq 'alive' || $$params{'response'})
	{
		$msg .= "SERVER: ".$CONFIG{'OS'}."/".$CONFIG{'OS_VERSION'}.", UPnP/1.0, ".$CONFIG{'PROGRAM_NAME'}."/".PDLNA::Config::print_version()."\r\n";
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

sub generate_usn
{
	my $nt = shift;

	my $usn = $CONFIG{'UUID'};
	$usn .= '::'.$nt if $nt ne $CONFIG{'UUID'};

	return $usn;
}

sub sleeper
{
	my $interval = shift;
	$interval = 3 unless defined($interval);
	sleep(int(rand($interval)));
}

1;
