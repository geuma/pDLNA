package PDLNA::Device;
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

use threads;
use threads::shared;

use Date::Format;
use LWP::UserAgent;
use XML::Simple;

use PDLNA::Config;
use PDLNA::DeviceUDN;

# constructor
sub new
{
	my $class = shift;
	my $params = shift;

	my %self : shared = (
		IP => $$params{'ip'},
		HTTP_USERAGENT => $$params{'http_useragent'},
		LAST_SEEN_TIMESTAMP => time(),
	);

	my %udn : shared = ();
	$self{UDN} = \%udn;

	my @history : shared = ();
	$self{DIRLIST_HISTORY} = \@history; # array stores a history of the directory listing IDs

	bless(\%self, $class);
	return \%self;
}

# sets/gets the HTTP_USERAGENT
# PARAMS:
# HTTP_USERAGENT
#
# RETURNS:
# HTTP_USERAGENT
sub http_useragent
{
	my $self = shift;
	my $user_agent = shift;

	$self->{HTTP_USERAGENT} = $user_agent if defined($user_agent);
	return $self->{HTTP_USERAGENT} || '';
}

# sets/gets the LAST_SEEN_TIMESTAMP
# PARAMS:
# LAST_SEEN_TIMESTAMP
#
# RETURNS:
# LAST_SEEN_TIMESTAMP
sub last_seen_timestamp
{
	my $self = shift;
	my $time = shift;

	$self->{LAST_SEEN_TIMESTAMP} = $time if defined($time);
	return $self->{LAST_SEEN_TIMESTAMP} || '';
}

# return reference to UDN hash
sub udn
{
	my $self = shift;

	return $self->{UDN};
}

sub udn_amount
{
	my $self = shift;

    my $amount = 0;
	foreach my $udn (keys %{$self->{UDN}})
	{
		$amount++;
	}
	return $amount;
}

# add or updates a new PDLNA::DeviceUDN object to UDN hash
sub add_udn
{
	my $self = shift;
	my $params = shift;

	return 0 if !defined($$params{'udn'}) || length($$params{'udn'}) == 0;

	if (defined($self->{UDN}->{$$params{'udn'}})) # check if UDN is already existing for PDLNA::Device object
	{
		# update/add the expiration time of NT
		$self->{UDN}->{$$params{'udn'}}->add_nt(
			{
				'nt' => $$params{'nt'},
				'nt_time_of_expire' => $$params{'nt_time_of_expire'},
			},
		);
	}
	else
	{
		# add a new DeviceUDN object to UDN hash
		$self->{UDN}->{$$params{'udn'}} = PDLNA::DeviceUDN->new(
			{
				'udn' => $$params{'udn'},
				'ssdp_banner' => $$params{'ssdp_banner'},
				'device_description_location' => $$params{'device_description_location'},
				'nt' => $$params{'nt'},
				'nt_time_of_expire' => $$params{'nt_time_of_expire'},
			},
		);
	}
	return 1;
}

# deletes a single NT or the whole PDLNA::DeviceUDN object from the UDN hash
sub del_udn
{
	my $self = shift;
	my $params = shift;

	return 0 if !defined($$params{'udn'}) || length($$params{'udn'}) == 0;

	if (defined($self->{UDN}->{$$params{'udn'}})) # check if UDN is existing for PDLNA::Device object
	{
		my $nt_amount = $self->{UDN}->{$$params{'udn'}}->del_nt(
			{
				'nt' => $$params{'nt'},
			},
		);

		if ($nt_amount == 0) # delete the object if no NT is available any more
		{
			delete($self->{UDN}->{$$params{'udn'}});
		}
	}
	return 1;
}

# adds a directory listing request to the history
# PARAMS:
# directory listing request
#
# RETURNS:
# -
sub add_dirlist_request
{
	my $self = shift;
	my $request = shift;

	if (defined($self->{DIRLIST_HISTORY}->[-1]))
	{
		push(@{$self->{DIRLIST_HISTORY}}, $request) unless $self->{DIRLIST_HISTORY}->[-1] eq $request; # we are NOT storing double requests
	}
	else
	{
		push(@{$self->{DIRLIST_HISTORY}}, $request);
	}
	$self->{LAST_SEEN_TIMESTAMP} = time();

	# we should limit the amount of entries in the history
	# splice(@{$self->{DIRLIST_HISTORY}}, 0, 1) if scalar(@{$self->{DIRLIST_HISTORY}}) == 2;
	# Doing this with splice is not going to work:
	# Splice not implemented for shared arrays at /PDLNA/Device.pm line 83 thread 11
# working with lock and delete isn't working as well
#	if (scalar(@{$self->{DIRLIST_HISTORY}}) == 2)
#	{
#		#lock($self->{DIRLIST_HISTORY}->[0]); # lock can only be used on shared values at /PDLNA/Device.pm line 88
#		lock(@{$self->{DIRLIST_HISTORY}}); # lock can only be used on shared values at /PDLNA/Device.pm line 88
#		delete($self->{DIRLIST_HISTORY}->[0]);
#	}
}

# returns the latest directory listing request
#
# RETURNS:
# latest directory listing request
sub get_last_dirlist_request
{
	my $self = shift;

	return $self->{DIRLIST_HISTORY}->[-1] if defined($self->{DIRLIST_HISTORY}->[-1]);
}

sub model_name_by_device_type
{
	my $self = shift;
	my $device_type = shift;

	foreach my $udn (keys %{$self->{UDN}})
	{
		if ($self->{UDN}{$udn}->device_type() eq $device_type)
		{
			return $self->{UDN}{$udn}->model_name();
		}
	}
	return '';
}

# prints the object information
sub print_object
{
	my $self = shift;

	my $string = '';
	$string .= "\t\tObject PDLNA::Device\n";
	$string .= "\t\t\tIP:              ".$self->{IP}."\n";
	foreach my $udn (keys %{$self->{UDN}})
	{
		$string .= $self->{UDN}{$udn}->print_object();
	}
	$string .= "\t\t\tHTTP User-Agent: ".$self->{HTTP_USERAGENT}."\n" if defined($self->{HTTP_USERAGENT});
	$string .= "\t\t\tDirectoryListing:".join(', ', @{$self->{DIRLIST_HISTORY}})."\n" if scalar(@{$self->{DIRLIST_HISTORY}}) > 0;
	$string .= "\t\t\tLast seen at:    ".time2str($CONFIG{'DATE_FORMAT'}, $self->{LAST_SEEN_TIMESTAMP})."\n";
	$string .= "\t\tObject PDLNA::Device END\n";

	return $string;
}

1;
