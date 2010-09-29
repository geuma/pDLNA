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
use File::Basename;
use Date::Format;

use PDLNA::Config;
use PDLNA::Log;
use PDLNA::ContentType;

sub new
{
	my $class = shift;
	my $params = shift;

	my $self = ();
	$self->{FILELIST} = {
		'image' => [],
		'video' => [],
		'audio' => [],
	};
	$self->{V} = {
		'F' => PDLNA::ContentType->new(
			{
				'media_type' => 'V',
				'sort_type' => 'F',
			},
		),
	};
	$self->{I} = {
		'F' => PDLNA::ContentType->new(
			{
				'media_type' => 'I',
				'sort_type' => 'F',
			},
		),
	};
	$self->{A} = {
		'F' => PDLNA::ContentType->new(
			{
				'media_type' => 'A',
				'sort_type' => 'F',
			},
		),
	};

	bless($self, $class);

	foreach my $directory (@{$CONFIG{'DIRECTORIES'}})
	{
		$self->initialize($directory->{'path'}, $directory->{'type'});
	}

	return $self;
}

sub get_content_type
{
	my $self = shift;
	my $media_type = shift;
	my $sort_type = shift;

	return $self->{$media_type}->{$sort_type} if defined($self->{$media_type}->{$sort_type});
}

sub print_object
{
	my $self = shift;

	my $string = "\n\tObject PDLNA::Content\n";
	foreach my $type ('A','I','V')
	{
		foreach my $sort (keys %{$self->{$type}})
		{
			$string .= $self->{$type}->{$sort}->print_object() if defined($self->{$type}->{$sort});
		}
	}
	$string .= "\tObject PDLNA::Content END\n";

	return $string;
}

sub return_media_type
{
	my $extension = shift;
	$extension = lc($extension);

	my %file_types = (
		'image' => [ 'jpg', 'jpeg', ],
		'video' => [ 'avi', ],
		'audio' => [ 'mp3', ],
	);

	foreach my $type (keys %file_types)
	{
		foreach (@{$file_types{$type}})
		{
			return $type if $extension eq $_;
		}
	}
	return 0;
}

sub initialize
{
	my $self = shift;
	my $path = shift;
	my $type = shift;

	return 0 if $path =~ /lost\+found/;
	PDLNA::Log::log("Processing directory '$path'.", 2);

	$path =~ s/\/$//;
	foreach my $element (bsd_glob("$path/*"))
	{
		if (-d "$element")
		{
			$element =~ s/\[/\\[/g;
			$element =~ s/\]/\\]/g;
			$self->initialize($element, $type);
		}
		elsif (-f "$element")
		{
			my $filetype = undef;
			if ($element =~ /\.(\w{3,4})$/)
			{
				$filetype = $1;
			}
			my $media_type = return_media_type($filetype);
			if ($media_type && ($media_type eq $type || $type eq "all"))
			{
				PDLNA::Log::log("Adding $media_type element '$element' to database.", 2);
				push(@{$self->{FILELIST}->{$media_type}}, $element);
			}
		}
	}
}

sub build_database
{
	my $self = shift;

	my %ABR = (
		'image' => 'I',
		'video' => 'V',
		'audio' => 'A',
	);

	foreach my $type (keys %{$self->{FILELIST}})
	{
		foreach my $element (@{$self->{FILELIST}->{$type}})
		{
			# SORTING: folders
			if (defined($self->{$ABR{$type}}->{F}))
			{
				my $group_object = $self->{$ABR{$type}}->{F}->get_group_by_path(dirname($element));
				if (!defined($group_object))
				{
					$group_object = PDLNA::ContentGroup->new(
						{
							'path' => dirname($element),
							'name' => dirname($element),
						},
					);
					$self->{$ABR{$type}}->{F}->add_group($group_object);
				}
				my @fileinfo = stat($element);
				$group_object->add_item(
					{
						'filename' => $element,
						'date' => $fileinfo[9],
						'size' => $fileinfo[7],
						'type' => $type,
					},
				);
			}

			# SORTING: creation date
			if (defined($self->{$ABR{$type}}->{T}))
			{
				my @fileinfo = stat($element);
				my $year = time2str("%Y-%m", $fileinfo[9]);

				my $group_object = $self->{$ABR{$type}}->{T}->get_group_by_name($year);
				if (!defined($group_object))
				{
					$group_object = PDLNA::ContentGroup->new(
						{
							'path' => dirname($element),
							'name' => $year,
						},
					);
					$self->{$ABR{$type}}->{T}->add_group($group_object);
				}
				$group_object->add_item(
					{
						'filename' => $element,
						'date' => $fileinfo[9],
						'size' => $fileinfo[7],
						'type' => $type,
					},
				);
			}

		}
	}


	foreach my $type ('A','I','V')
	{
		foreach my $sort (keys %{$self->{$type}})
		{
			$self->{$type}->{$sort}->set_ids_for_groups();
			foreach my $group (@{$self->{$type}->{$sort}->content_groups})
			{
				$group->set_ids_for_items();
			}
		}
	}
}

1;
