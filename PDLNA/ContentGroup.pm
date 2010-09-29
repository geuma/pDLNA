package PDLNA::ContentGroup;
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

use File::Basename;

use PDLNA::ContentItem;
use PDLNA::Utils;

sub new
{
	my $class = shift;
	my $params = shift;

	my $self = ();
	$self->{ID} = $$params{'id'};
	$self->{PATH} = $$params{'path'};
	$self->{NAME} = $$params{'name'};
	$self->{CONTENT_ITEMS} = [];
	$self->{CONTENT_ITEMS_AMOUNT} = 0;

	bless($self, $class);
	return $self;
}

sub id
{
	my $self = shift;
	my $id = shift;

	$self->{ID} = $id if defined($id);
	return $self->{ID};
}

sub beautiful_id
{
	my $self = shift;
	return PDLNA::Utils::add_leading_char($self->{ID}, 4, '0');
}

sub name
{
	my $self = shift;
	return $self->{NAME};
}

sub path
{
	my $self = shift;
	return $self->{PATH};
}

sub content_items
{
	my $self = shift;
	return $self->{CONTENT_ITEMS};
}

sub content_items_amount
{
	my $self = shift;
	return $self->{CONTENT_ITEMS_AMOUNT};
}

sub print_object
{
	my $self = shift;

    my $string = '';
	$string .= "\t\tObject PDLNA::ContentGroup\n";
	$string .= "\t\t\tID:            ".PDLNA::Utils::add_leading_char($self->{ID}, 4, '0')."\n";
	$string .= "\t\t\tPath:          ".$self->{PATH}."\n";
	$string .= "\t\t\tName:          ".$self->{NAME}."\n";
	$string .= "\t\t\tItems:         \n";
	foreach my $item (@{$self->{CONTENT_ITEMS}})
	{
		$string .= $item->print_object();
	}
	$string .= "\t\t\tItems Amount:  ".$self->{CONTENT_ITEMS_AMOUNT}."\n";
	$string .= "\t\tObject PDLNA::ContentGroup END\n";

	return $string;
}

sub add_item
{
	my $self = shift;
	my $params = shift;

	push(@{$self->{CONTENT_ITEMS}}, PDLNA::ContentItem->new($params));
	$self->{CONTENT_ITEMS_AMOUNT}++;
}

sub set_ids_for_items
{
	my $self = shift;

	my $id = 0;
	foreach my $item (@{$self->{CONTENT_ITEMS}})
	{
		$item->id($id);
		$id++;
	}
}

1;
