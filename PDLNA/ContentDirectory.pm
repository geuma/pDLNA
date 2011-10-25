package PDLNA::ContentDirectory;
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

use Date::Format;
use File::Basename;
use File::Glob qw(bsd_glob);

use PDLNA::ContentItem;
use PDLNA::Log;
use PDLNA::Utils;

sub new
{
	my $class = shift;
	my $params = shift;

	my $self = ();
	$self->{ID} = $$params{'parent_id'}.$$params{'id'};
	$self->{PATH} = $$params{'path'};
	$self->{NAME} = basename($$params{'path'});
	$self->{TYPE} = $$params{'type'};
	$self->{RECURSION} = $$params{'recursion'};
	$self->{PARENT_ID} = $$params{'parent_id'};
	$self->{ITEMS} = {};
	$self->{DIRECTORIES} = {};
	$self->{AMOUNT} = 0;

	bless($self, $class);

	$self->initialize();

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

sub items
{
	my $self = shift;
	return $self->{ITEMS};
}

sub directories
{
	my $self = shift;
	return $self->{DIRECTORIES};
}

sub amount
{
	my $self = shift;
	return $self->{AMOUNT};
}

sub parent_id
{
	my $self = shift;
	return $self->{PARENT_ID} if length($self->{PARENT_ID}) == 0;
	return 0;
}

sub print_object
{
	my $self = shift;
	my $input = shift;

    my $string = '';
	$string .= $input."Object PDLNA::ContentDirectory\n";
	$string .= $input."\tID:            ".$self->{ID}."\n";
	if (length($self->{PARENT_ID}) == 0)
	{
		$string .= $input."\tParentID:      0\n";
	}
	else
	{
		$string .= $input."\tParentID:      ".$self->{PARENT_ID}."\n";
	}
	$string .= $input."\tPath:          ".$self->{PATH}."\n";
	$string .= $input."\tName:          ".$self->{NAME}."\n";
	$string .= $input."\tItems:       \n";
	foreach my $id (keys %{$self->{ITEMS}})
	{
		$string .= $self->{ITEMS}->{$id}->print_object($input."\t");
	}
	$string .= $input."\tDirectories: \n";
	foreach my $id (keys %{$self->{DIRECTORIES}})
	{
		$string .= $self->{DIRECTORIES}->{$id}->print_object($input."\t");
	}
	$string .= $input."\tAmount:        ".$self->{AMOUNT}."\n";
	$string .= $input."Object PDLNA::ContentDirectory END\n";

	return $string;
}

sub add_item
{
	my $self = shift;
	my $params = shift;

	my $id = $$params{'parent_id'}.$$params{'id'};
	$self->{ITEMS}->{$id} = PDLNA::ContentItem->new($params);
	$self->{AMOUNT}++;
}

sub add_directory
{
	my $self = shift;
	my $params = shift;

	my $id = $$params{'parent_id'}.$$params{'id'};
	$self->{DIRECTORIES}->{$id} = PDLNA::ContentDirectory->new($params);
	$self->{AMOUNT}++;
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

sub initialize
{
	my $self = shift;

	return 0 if $self->{PATH} =~ /lost\+found/;
	PDLNA::Log::log("Processing directory '".$self->{PATH}."'.", 2, 'library');

	$self->{PATH} =~ s/\/$//;
	my $id = 100;
	foreach my $element (bsd_glob($self->{PATH}."/*"))
	{
		if ($id > 999)
		{
			PDLNA::Log::log('More than 900 elements in '.$self->{PATH}.'. Skipping further elements.', 1, 'library');
			return;
		}
		if (-d "$element" && $self->{RECURSION} eq 'yes')
		{
			$element =~ s/\[/\\[/g;
			$element =~ s/\]/\\]/g;
			$self->add_directory({
				'path' => $element,
				'type' => $self->{TYPE},
				'recursion' => $self->{RECURSION},
				'id' => $id,
				'parent_id' => $self->{ID},
			});
			$id++;
		}
		elsif (-f "$element")
		{
			my $filetype = undef;
			if ($element =~ /\.(\w{3,4})$/)
			{
				$filetype = $1;
			}
			my $media_type = return_media_type($filetype);
			if ($media_type && ($media_type eq $self->{TYPE} || $self->{TYPE} eq "all"))
			{
				PDLNA::Log::log("Adding $media_type element '$element' to database.", 2, 'library');

				my @fileinfo = stat($element);
				my $year = time2str("%Y-%m", $fileinfo[9]);
				$self->add_item({
					'filename' => $element,
					'date' => $fileinfo[9],
					'size' => $fileinfo[7],
					'type' => $media_type,
					'id' => $id,
					'parent_id' => $self->{ID},
				});
				$id++;
			}
		}
	}
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

sub get_object_by_id
{
	my $self = shift;
	my $id = shift;

	if ($self->id() == $id)
	{
		return $self;
	}

	my %directories = %{$self->directories()};
	my $subid = substr($id, 0, length($self->id())+3);
	if (defined($directories{$subid}))
	{
		return $directories{$subid}->get_object_by_id($id);
	}

	PDLNA::Log::log('No Directory with ID '.$id.' found. Start looking for Item.', 3, 'library');
	my %items = %{$self->items()};
	if (defined($items{$id}))
	{
		PDLNA::Log::log('Found the Item with ID '.$id, 3, 'library');
		return $items{$id};
	}
}

1;
