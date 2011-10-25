package PDLNA::ContentLibrary;
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

use PDLNA::Config;
use PDLNA::ContentDirectory;
use PDLNA::Log;

sub new
{
	my $class = shift;
	my $params = shift;

	my $self = ();
	$self->{TIMESTAMP} = '';
	$self->{DIRECTORIES} = {};
	$self->{AMOUNT} = 0;

	bless($self, $class);

	my $i = 100;
	foreach my $directory (@{$CONFIG{'DIRECTORIES'}})
	{
		if ($i > 999)
		{
			PDLNA::Log::log('More than 900 configured directories. Skip to load directory: '.$directory, 1, 'library');
			next;
		}
		$self->{DIRECTORIES}->{$i} = PDLNA::ContentDirectory->new({
			'path' => $directory->{'path'},
			'type' => $directory->{'type'},
			'recursion' => $directory->{'recursion'},
			'id' => $i,
			'parent_id' => '',
		});
		$i++;
		$self->{AMOUNT}++;
	}

	return $self;
}

sub is_directory
{
	return 1;
}

sub is_item
{
	return 0;
}

sub directories
{
	my $self = shift;
	return $self->{DIRECTORIES};
}

sub items
{
	my $self = shift;
	return {};
}

sub amount
{
	my $self = shift;
	return $self->{AMOUNT};
}

sub id
{
	my $self = shift;
	return 0;
}

sub print_object
{
	my $self = shift;

	my $string = "\n\tObject PDLNA::ContentLibrary\n";
	foreach my $id (keys %{$self->{DIRECTORIES}})
	{
		$string .= $self->{DIRECTORIES}->{$id}->print_object("\t\t");
	}
	$string .= "\t\tAmount:    $self->{AMOUNT}\n";
	$string .= "\t\tTimestamp: $self->{TIMESTAMP}\n";
	$string .= "\tObject PDLNA::ContentLibrary END\n";

	return $string;
}

sub get_object_by_id
{
	my $self = shift;
	my $id = shift;

	if ($id == 0)
	{
		return $self;
	}
	else
	{
		my $subid = substr($id, 0, 3);
		return $self->{DIRECTORIES}->{$subid}->get_object_by_id($id);
	}

	return undef;
}

1;
