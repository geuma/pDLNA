package PDLNA::Content;
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

use File::Glob qw(bsd_glob);
use Data::Dumper;

use PDLNA::Config;
use PDLNA::Log;
use PDLNA::ContentType;

sub new
{
	my $class = shift;
	my $params = shift;

	my $self = ();
	$self->{V} = {
		'F' => PDLNA::ContentType->new(
			{
				'media_type' => 'V',
				'sort_type' => 'F',
			},
		),
		'T' => PDLNA::ContentType->new(
			{
				'media_type' => 'V',
				'sort_type' => 'T',
			},
		),
	};
	bless($self, $class);

	foreach my $directory (@{$CONFIG{'DIRECTORIES'}})
	{
		$self->initialize($directory->{'path'});
	}

	foreach my $type (keys %{$self})
	{
		my $tmp = $self->{$type};
		foreach my $sort (keys %{$tmp})
		{
			$tmp->{$sort}->set_ids_for_groups();
		}
	}

	return $self;
}

sub get_content_type
{
	my $self = shift;
	my $media_type = shift;
	my $sort_type = shift;

	return $self->{$media_type}->{$sort_type};
}

sub print_object
{
	my $self = shift;

	print "Object PDLNA::Content\n";
	foreach my $type (keys %{$self})
	{
		my $tmp = $self->{$type};
		foreach my $sort (keys %{$tmp})
		{
			$tmp->{$sort}->print_object();
		}
	}
}

sub initialize
{
	my $self = shift;
	my $path = shift;

	PDLNA::Log::log("Processing path $path", 1);

	return 0 if $path =~ /lost\+found/;
	my $group_object = PDLNA::ContentGroup->new(
		{
			'path' => $path,
		},
	);
	foreach my $type (keys %{$self})
	{
		my $tmp = $self->{$type};
		foreach my $sort (keys %{$tmp})
		{
			$tmp->{$sort}->add_group($group_object);
		}
	}





	$path =~ s/\/$//;
	foreach my $element (bsd_glob("$path/*"))
	{
#		next if $element =~ /^\.\/\_/;
		if (-d "$element")
		{
			$element =~ s/\[/\\[/g;
			$element =~ s/\]/\\]/g;
			$self->initialize($element);
		}
		elsif (-f "$element")
		{
			PDLNA::Log::log("Adding element $element to database.", 1);
#			foreach my $type (keys %{$self})
#			{
#				my $tmp = $self->{$type};
#				foreach my $sort (keys %{$tmp})
#				{
#					$tmp->{$sort}->print_object();
#				}
#			}


			# old
			print "We found a file: $element\n";
			my @fileinfo = stat($element);
			$group_object->add_item(
				{
					'filename' => $element,
					'date' => $fileinfo[9],
					'size' => $fileinfo[7],
				},
			);
		}
	}
	$group_object->set_ids_for_items();
}

1;
