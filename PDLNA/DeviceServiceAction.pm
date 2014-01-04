package PDLNA::DeviceServiceAction;
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2014 Stefan Heumader <stefan@heumader.at>
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

# constructor
sub new
{
	my $class = shift;
	my $params = shift;

	my %self : shared = (
		ACTION => $$params{'action'},
	);

	my %parameters : shared = ();
	foreach my $parameter (keys %{$$params{'parameters'}})
	{
		my %parameter_definition : shared = ();
		foreach my $param ('direction', 'retval', 'relatedStateVariable')
		{
			$parameter_definition{$param} = $$params{'parameters'}{$parameter}{$param} if defined($$params{'parameters'}{$parameter}{$param});
		}
		$parameters{$parameter} = \%parameter_definition;
	}
	$self{PARAMETERS} = \%parameters;

	my %variables : shared = ();
	foreach my $variable (keys %{$$params{'variables'}})
	{
		my %variable_definition : shared = ();
		foreach my $param ('dataType', 'sendEvents')
		{
			$variable_definition{$param} = $$params{'variables'}{$variable}{$param} if defined($$params{'variables'}{$variable}{$param});
		}

		unless (ref($$params{'variables'}{$variable}{'defaultValue'}) eq 'HASH')
		{
			$variable_definition{'defaultValue'} = $$params{'variables'}{$variable}{'defaultValue'} if defined($$params{'variables'}{$variable}{'defaultValue'});
		}

		if (ref($$params{'variables'}{$variable}{'allowedValueList'}->{'allowedValue'}) eq 'ARRAY')
		{
			my @allowed_values : shared = ();
			foreach my $value (@{$$params{'variables'}{$variable}{'allowedValueList'}->{'allowedValue'}})
			{
				push(@allowed_values, $value);
			}
			$variable_definition{'allowedValueList'} = \@allowed_values;
		}

		if (ref($$params{'variables'}{$variable}{'allowedValueRange'}) eq 'HASH')
		{
			my %allowed_value_range : shared = ();
			foreach my $key (keys %{$$params{'variables'}{$variable}{'allowedValueRange'}})
			{
				$allowed_value_range{$key} = $$params{'variables'}{$variable}{'allowedValueRange'}{$key};
			}
			$variable_definition{'allowedValueRange'} = \%allowed_value_range;
		}

		$variables{$variable} = \%variable_definition;
	}
	$self{VARIABLES} = \%variables;

	bless(\%self, $class);
	return \%self;
}

# prints the object information
sub print_object
{
	my $self = shift;

	my $string = '';
	$string .= "\t\t\t\t\tObject PDLNA::DeviceServiceAction\n";
	$string .= "\t\t\t\t\t\tAction:      ".$self->{ACTION}."\n" if defined($self->{ACTION});
	$string .= "\t\t\t\t\t\tParameters:  \n";
	foreach my $parameter (keys %{$self->{PARAMETERS}})
	{
		$string .= "\t\t\t\t\t\t\tParameterName:      ".$parameter."\n";
		foreach my $def (keys %{$self->{PARAMETERS}{$parameter}})
		{
			$string .= "\t\t\t\t\t\t\t\t".$def."      ".$self->{PARAMETERS}{$parameter}{$def}."\n";
		}
		$string .= "\t\t\t\t\t\t\t\tVariableDefinition:\n";
		foreach my $def (keys %{$self->{VARIABLES}{$parameter}})
		{
			if ($def eq 'allowedValueList')
			{
				$string .= "\t\t\t\t\t\t\t\t\t".$def."      ".join(', ', @{$self->{VARIABLES}{$parameter}{$def}})."\n";
			}
			elsif ($def eq 'allowedValueRange')
			{
				foreach my $key (keys %{$self->{VARIABLES}{$parameter}{$def}})
				{
					$string .= "\t\t\t\t\t\t\t\t\tallowedValueRange_".$key."      ".$self->{VARIABLES}{$parameter}{$def}{$key}."\n";
				}
			}
			else
			{
				$string .= "\t\t\t\t\t\t\t\t\t".$def."      ".$self->{VARIABLES}{$parameter}{$def}."\n";
			}
		}
	}
	$string .= "\t\t\t\t\tObject PDLNA::DeviceServiceAction END\n";

	return $string;
}

1;
