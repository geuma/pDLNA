package PDLNA::ContentType;
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

use PDLNA::ContentGroup;

sub new
{
	my $class = shift;
	my $params = shift;

	my $self = ();
	$self->{MEDIA_TYPE} = $$params{'media_type'};
	$self->{SORT_TYPE} = $$params{'sort_type'};
	$self->{CONTENT_GROUPS} = [];
	$self->{CONTENT_GROUPS_AMOUNT} = 0;

	bless($self, $class);
	return $self;
}

sub print_object
{
	my $self = shift;

	my %media_type = (
		'V' => 'video',
		'I' => 'image',
		'A' => 'audio',
	);

	my %sort_type = (
		'F' => 'folders',
		'T' => 'time of creation',
	);

    my $string = '';
	$string .= "\tObject PDLNA::ContentType\n";
	$string .= "\t\tMedia Type:    ".$media_type{$self->{MEDIA_TYPE}}."\n";
	$string .= "\t\tSort Type:     ".$sort_type{$self->{SORT_TYPE}}."\n";
	$string .= "\t\tGroups:        \n";
	foreach my $group (@{$self->{CONTENT_GROUPS}})
	{
		$string .= $group->print_object() if defined($group);
	}
	$string .= "\t\tGroups Amount: ".$self->{CONTENT_GROUPS_AMOUNT}."\n";

	return $string;
}

sub add_group
{
	my $self = shift;
	my $params = shift;

	if (ref($params) eq "HASH")
	{
		push(@{$self->{CONTENT_GROUPS}}, PDLNA::ContentGroup->new($params));
	}
	else
	{
		push(@{$self->{CONTENT_GROUPS}}, $params);
	}
	$self->{CONTENT_GROUPS_AMOUNT}++;
}

sub get_group_by_path
{
	my $self = shift;
	my $name = shift;

	foreach my $group (@{$self->{CONTENT_GROUPS}})
	{
		return $group if ($group->path() eq $name);
	}

	return undef;
}

sub get_group_by_name
{
	my $self = shift;
	my $name = shift;

	foreach my $group (@{$self->{CONTENT_GROUPS}})
	{
		return $group if ($group->name() eq $name);
	}

	return undef;
}

sub set_ids_for_groups
{
	my $self = shift;

	my $id = 0;
	foreach my $group (@{$self->{CONTENT_GROUPS}})
	{
		$group->id($id);
		$id++;
	}
}

sub content_groups
{
	my $self = shift;
	return $self->{CONTENT_GROUPS};
}

sub content_groups_amount
{
	my $self = shift;
	return $self->{CONTENT_GROUPS_AMOUNT};
}

1;
