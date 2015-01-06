package PDLNA::DeviceService;
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2015 Stefan Heumader <stefan@heumader.at>
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

use XML::Simple;

use PDLNA::DeviceServiceAction;
use PDLNA::Utils;

# constructor
sub new
{
	my $class = shift;
	my $params = shift;

	my %self : shared = (
		ID => $$params{'service_id'},
		TYPE => $$params{'service_type'},
		CONTROL_URL => $$params{'controlURL'},
		EVENTSUB_URL => $$params{'eventSubURL'},
		SCPD_URL => $$params{'SCPDURL'},
	);

	my %actions : shared = ();
	my $response = PDLNA::Utils::fetch_http($self{SCPD_URL});
	if ($response)
	{
		my $xs = XML::Simple->new();
		my $xml = eval { $xs->XMLin($response) };
		if ($@)
		{
			PDLNA::Log::log('ERROR: Unable to parse XML Service Description in PDLNA::DeviceService: '.$@, 0, 'discovery');
		}
		else
		{
			if (ref($xml->{'actionList'}->{'action'}) eq 'HASH') # we need to check if it is a hash
			{
				foreach my $action (keys %{$xml->{'actionList'}->{'action'}})
				{
					my %action_definition = ();
					$action_definition{'action'} = $action;
					$action_definition{'parameters'} = {};
					$action_definition{'variables'} = {};

					if (ref($xml->{'actionList'}->{'action'}->{$action}->{'argumentList'}->{'argument'}) eq 'HASH') # we need to check if it is a hash
					{
						foreach my $argument (keys %{$xml->{'actionList'}->{'action'}->{$action}->{'argumentList'}->{'argument'}})
						{
							if (ref($xml->{'actionList'}->{'action'}->{$action}->{'argumentList'}->{'argument'}->{$argument}) eq 'HASH')
							{
								foreach my $variable (keys %{$xml->{'actionList'}->{'action'}->{$action}->{'argumentList'}->{'argument'}->{$argument}})
								{
									my %variable_definition = ();
									foreach my $param ('direction', 'relatedStateVariable', 'retval')
									{
										$variable_definition{$param} = $xml->{'actionList'}->{'action'}->{$action}->{'argumentList'}->{'argument'}->{$argument}->{$param};
									}

									$action_definition{'parameters'}->{$argument} = \%variable_definition;
									$action_definition{'variables'}->{$argument} = $xml->{'serviceStateTable'}->{'stateVariable'}->{$variable_definition{'relatedStateVariable'}};
								}
							}
							else
							{
								# TODO different structure when only one parameter is available
							}
						}
					}
					$actions{$action} = PDLNA::DeviceServiceAction->new(\%action_definition);
				}
			}
		}
	}
	$self{ACTIONS} = \%actions;

	bless(\%self, $class);
	return \%self;
}

# prints the object information
sub print_object
{
	my $self = shift;

	my $string = '';
	$string .= "\t\t\t\tObject PDLNA::DeviceService\n";
	$string .= "\t\t\t\t\tID:            ".$self->{ID}."\n" if defined($self->{ID});
	$string .= "\t\t\t\t\tType:          ".$self->{TYPE}."\n" if defined($self->{ID});
	$string .= "\t\t\t\t\tControlURL:    ".$self->{CONTROL_URL}."\n" if defined($self->{ID});
	$string .= "\t\t\t\t\tEventSubURL:   ".$self->{EVENTSUB_URL}."\n" if defined($self->{ID});
	$string .= "\t\t\t\t\tSCPDURL:       ".$self->{SCPD_URL}."\n" if defined($self->{ID});
	foreach my $action (keys %{$self->{ACTIONS}})
	{
		$string .= $self->{ACTIONS}{$action}->print_object();;
	}
	$string .= "\t\t\t\tObject PDLNA::DeviceService END\n";

	return $string;
}

1;
