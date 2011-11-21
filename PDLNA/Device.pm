package PDLNA::Device;
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

use threads;
use threads::shared;

use Date::Format;
use LWP::UserAgent;
use XML::Simple;

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
		MODEL_NAME => undef,
	);
	my %nts : shared = ();
	$nts{$$params{'nt'}} = $$params{'time_of_expire'} if defined($$params{'nt'});
	$self{NTS} = \%nts;

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
}

# delete a nt type of an object
#
# RETURNS:
# amount of nt elements in the NTS hash
sub del
{
	my $self = shift;
	my $nt = shift;

	delete($self->{NTS}->{$nt}) if defined($self->{NTS}->{$nt});

	return scalar(keys %{$self->{NTS}});
}

sub model_name
{
	my $self = shift;

	my $model_name = '';
	if (defined($self->{SSDP_DESC}))
	{
		my $ua = LWP::UserAgent->new();
		my $request = HTTP::Request->new(GET => $self->{SSDP_DESC});
		my $response = $ua->request($request);
		if ($response->is_success())
		{
			my $xs = XML::Simple->new();
			my $xml = $xs->XMLin($response->content());
			$model_name = $xml->{'device'}->{'modelName'};
		}
	}

	return $model_name;
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
	return $self->{HTTP_USERAGENT};
}

sub ssdp_banner
{
	my $self = shift;
	my $ssdp_banner = shift;

	$self->{SSDP_BANNER} = $ssdp_banner if defined($ssdp_banner);
	return $self->{SSDP_BANNER};
}

sub ssdp_desc
{
	my $self = shift;
	my $ssdp_desc = shift;

	$self->{SSDP_DESC} = $ssdp_desc if defined($ssdp_desc);
	return $self->{SSDP_DESC};
}

sub uuid
{
	my $self = shift;
	my $uuid = shift;

	$self->{UUID} = $uuid if defined($uuid);
	return $self->{UUID};
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
		$string .= "\t\t\t\t".$nt." (expires at ".time2str("%Y-%m-%d %H:%M:%S", $self->{NTS}->{$nt}).")\n"
	}
	$string .= "\t\t\tSSDP Banner:     ".$self->{SSDP_BANNER}."\n" if defined($self->{SSDP_BANNER});
	$string .= "\t\t\tDescription URL: ".$self->{SSDP_DESC}."\n" if defined($self->{SSDP_DESC});
	$string .= "\t\t\tHTTP User-Agent: ".$self->{HTTP_USERAGENT}."\n" if defined($self->{HTTP_USERAGENT});
	$string .= "\t\tObject PDLNA::Device END\n";

	return $string;
}

1;
