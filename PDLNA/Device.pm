package PDLNA::Device;
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

use threads;
use threads::shared;

use Date::Format;
use LWP::UserAgent;
use XML::Simple;

use PDLNA::Config;

# constructor
sub new
{
	my $class = shift;
	my $params = shift;

	my %self : shared = (
		IP => $$params{'ip'},
		UUID => $$params{'uuid'},
		SSDP_BANNER => $$params{'ssdp_banner'},
		SSDP_DESC => $$params{'desc_location'},
		HTTP_USERAGENT => $$params{'http_useragent'},
		XML_MODEL_NAME => '',
		LAST_SEEN_TIMESTAMP => time(),
	);

	my %nts : shared = ();
	$nts{$$params{'nt'}} = $$params{'time_of_expire'} if defined($$params{'nt'});
	$self{NTS} = \%nts;

	my @history : shared = ();
	$self{DIRLIST_HISTORY} = \@history; # array stores a history of the directory listing IDs

	bless(\%self, $class);
	return \%self;
}

# add a nt type to the object with its expire time
sub add_nt
{
	my $self = shift;
	my $nt = shift;
	my $expire = shift;

	$self->{NTS}->{$nt} = $expire;
	$self->{LAST_SEEN_TIMESTAMP} = time();
}

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

sub get_last_dirlist_request
{
	my $self = shift;

	return $self->{DIRLIST_HISTORY}->[-1] if defined($self->{DIRLIST_HISTORY}->[-1]);
}

# delete a nt type of an object
#
# RETURNS:
# amount of nt elements in the NTS hash
sub del
{
	my $self = shift;
	my $nt = shift || undef;

	if (defined($nt) && defined($self->{NTS}->{$nt}))
	{
		delete($self->{NTS}->{$nt});
	}

	return $self->nts_amount();
}

sub nts
{
	my $self = shift;
	return $self->{NTS};
}

sub nts_amount
{
	my $self = shift;
	my $amount = 0;
	foreach my $nt (keys %{$self->{NTS}})
	{
		$amount++;
	}
	return $amount;
}

sub model_name
{
	my $self = shift;
	return $self->{XML_MODEL_NAME} || '';
}

sub fetch_xml_info
{
	my $self = shift;

	if (defined($self->{SSDP_DESC}) && length($self->{XML_MODEL_NAME}) == 0)
	{
		my $ua = LWP::UserAgent->new();
		$ua->agent($CONFIG{'PROGRAM_NAME'}."/".PDLNA::Config::print_version());
		my $request = HTTP::Request->new(GET => $self->{SSDP_DESC});
		my $response = $ua->request($request);
		if ($response->is_success())
		{
			my $res = $response->content();
			if (defined($res) && length($res) > 0)
			{
				my $xs = XML::Simple->new();
				my $xml = $xs->XMLin($res);
				$self->{XML_MODEL_NAME} = $xml->{'device'}->{'modelName'};
			}
		}
	}
}

# sets the HTTP_USERAGENT
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

sub ssdp_banner
{
	my $self = shift;
	my $ssdp_banner = shift;

	$self->{SSDP_BANNER} = $ssdp_banner if defined($ssdp_banner);
	return $self->{SSDP_BANNER} || '';
}

sub ssdp_desc
{
	my $self = shift;
	my $ssdp_desc = shift;

	$self->{SSDP_DESC} = $ssdp_desc if defined($ssdp_desc);
	return $self->{SSDP_DESC} || '';
}

sub uuid
{
	my $self = shift;
	my $uuid = shift;

	$self->{UUID} = $uuid if defined($uuid);
	return $self->{UUID} || '';
}

sub last_seen_timestamp
{
	my $self = shift;
	my $time = shift;

	$self->{LAST_SEEN_TIMESTAMP} = $time if defined($time);
	return $self->{LAST_SEEN_TIMESTAMP} || '';
}

# prints the object information
sub print_object
{
	my $self = shift;

	my $string = '';
	$string .= "\t\tObject PDLNA::Device\n";
	$string .= "\t\t\tIP:              ".$self->{IP}."\n";
	$string .= "\t\t\tUUID:            ".$self->{UUID}."\n" if defined($self->{UUID});
	$string .= "\t\t\tNTS:\n";
	foreach my $nt (keys %{$self->{NTS}})
	{
		$string .= "\t\t\t\t".$nt." (expires at ".time2str($CONFIG{'DATE_FORMAT'}, $self->{NTS}->{$nt}).")\n"
	}
	$string .= "\t\t\tSSDP Banner:     ".$self->{SSDP_BANNER}."\n" if defined($self->{SSDP_BANNER});
	$string .= "\t\t\tDescription URL: ".$self->{SSDP_DESC}."\n" if defined($self->{SSDP_DESC});
	$string .= "\t\t\tHTTP User-Agent: ".$self->{HTTP_USERAGENT}."\n" if defined($self->{HTTP_USERAGENT});
	$string .= "\t\t\tXML ModelName:   ".$self->{XML_MODEL_NAME}."\n" if defined($self->{XML_MODEL_NAME});
	$string .= "\t\t\tLast seen at:    ".time2str($CONFIG{'DATE_FORMAT'}, $self->{LAST_SEEN_TIMESTAMP})."\n";
	$string .= "\t\t\tDirectoryListing:".join(', ', @{$self->{DIRLIST_HISTORY}})."\n" if scalar(@{$self->{DIRLIST_HISTORY}}) > 0;
	$string .= "\t\tObject PDLNA::Device END\n";

	return $string;
}

1;
