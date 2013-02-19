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
use PDLNA::Database;
use PDLNA::Devices;
use PDLNA::Log;

sub new
{
	my $class = shift;

	my $self = ();
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
	my $destination_port = shift; # client original source port, which gets the destination port for the response of the discover
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
		PDLNA::Devices::delete_expired_devices();
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

sub parse_ssdp_message
{
	my $input_data = shift;
	my $output_data = shift;

	my @lines = split('\n', $input_data);
	for (my $i = 0; $i < @lines; $i++)
	{
		chomp($lines[$i]);
		$lines[$i] =~ s/\r//g;
		splice(@lines, $i, 1) if length($lines[$i]) == 0;
	}

	PDLNA::Log::log('Parsed SSDP message data: '.join(', ', @lines), 3, 'discovery');

	if ($lines[0] =~ /(NOTIFY|M-SEARCH)/i)
	{
		$$output_data{'TYPE'} = uc($1);
		splice(@lines, 0, 1);
	}
	else
	{
		return 0;
	}

	foreach my $line (@lines)
	{
		if ($line =~ /^([\w\-]+):\s*(.*)$/i)
		{
			$$output_data{uc($1)} = $2;
		}
		else
		{
			return 0;
		}
	}

	# some final sanitations
	if (defined($$output_data{'USN'}))
	{
		my ($a, undef) = split('::', $$output_data{'USN'});
		$$output_data{'USN'} = $a;
#		$$output_data{'USN'} =~ s/^uuid://;
	}

	if (defined($$output_data{'CACHE-CONTROL'}))
	{
		$$output_data{'CACHE-CONTROL'} = $1 if $$output_data{'CACHE-CONTROL'} =~ /^max-age\s*=\s*(\d+)/i;
		my $time = time();
		$$output_data{'CACHE-CONTROL'} += $time;
	}

	$$output_data{'MX'} = 3 if !defined($$output_data{'MX'});
	# end of final sanitations

	return 1;
}

sub receive_messages
{
	my $self = shift;

	my $dbh = PDLNA::Database::connect();
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
			PDLNA::Log::log('Ignoring SSDP message from NOT allowed client IP '.$peer_ip_addr.'.', 2, 'discovery');
			next;
		}

		my %message = ();
		unless(parse_ssdp_message($data, \%message))
		{
			PDLNA::Log::log('Error while parsing SSDP message from client IP '.$peer_ip_addr.'. Ignoring message.', 1, 'discovery');
			next;
		}

		if ($message{'TYPE'} eq 'NOTIFY')
		{
			# we will not add the running pDLNA installation to our SSDP database
			if ($peer_ip_addr eq $CONFIG{'LOCAL_IPADDR'} && $message{'USN'} eq $CONFIG{'UUID'})
			{
				PDLNA::Log::log('Ignore SSDP message from allowed client IP '.$peer_ip_addr.', because the message came from this running '.$CONFIG{'PROGRAM_NAME'}.' installation.', 2, 'discovery');
				next;
			}

			if ($message{'NTS'} eq 'ssdp:alive' && defined($message{'NT'}))
			{
				PDLNA::Log::log('Adding UPnP device '.$message{'USN'}.' ('.$peer_ip_addr.') for '.$message{'NT'}.' to database.', 2, 'discovery');
				PDLNA::Devices::add_device(
					$dbh,
					{
						'ip' => $peer_ip_addr,
						'udn' => $message{'USN'},
						'ssdp_banner' => $message{'SERVER'},
						'device_description_location' => $message{'LOCATION'},
						'nt' => $message{'NT'},
						'nt_time_of_expire' => $message{'CACHE-CONTROL'},
					},
				);
			}
			elsif ($message{'NTS'} eq 'ssdp:byebye' && defined($message{'NT'}))
			{
				PDLNA::Log::log('Deleting UPnP device '.$message{'USN'}.' ('.$peer_ip_addr.') for '.$message{'NT'}.' from database.', 2, 'discovery');
				PDLNA::Devices::delete_device(
					$dbh,
					{
						'ip' => $peer_ip_addr,
						'udn' => $message{'USN'},
						'nt' => $message{'NT'},
					},
				);
			}
		}
		elsif ($message{'TYPE'} eq 'M-SEARCH')
		{
			if (defined($message{'MAN'}) && $message{'MAN'} eq '"ssdp:discover"')
			{
				PDLNA::Log::log('Received a SSDP M-SEARCH message by '.$peer_ip_addr.':'.$peer_src_port.' for a '.$message{'ST'}.' with an mx of '.$message{'MX'}.'.', 1, 'discovery');
				# TODO start function in a thread - currently this is a blocking implementation
				$self->send_announce($peer_ip_addr, $peer_src_port, $message{'ST'}, $message{'MX'});
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
