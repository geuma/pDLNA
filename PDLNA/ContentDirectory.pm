package PDLNA::ContentDirectory;
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

use Date::Format;
use Fcntl;
use File::Basename;
use File::Glob qw(bsd_glob);
use File::MimeInfo;
use Movie::Info;

use PDLNA::Config;
use PDLNA::ContentItem;
use PDLNA::Log;
use PDLNA::Utils;

sub new
{
	my $class = shift;
	my $params = shift;

	my $self = ();
	$self->{ID} = $$params{'parent_id'}.$$params{'id'};
	$self->{PATH} = $$params{'path'} || '';
	$self->{NAME} = $$params{'name'} || basename($self->{PATH});
	$self->{TYPE} = $$params{'type'};
	$self->{SUBTYPE} = $$params{'subtype'} || 'directory';
	$self->{RECURSION} = $$params{'recursion'};
	$self->{EXCLUDE_DIRS} = $$params{'exclude_dirs'};
	$self->{EXCLUDE_ITEMS} = $$params{'exclude_items'};
	$self->{ALLOW_PLAYLISTS} = $$params{'allow_playlists'} || 0;
	$self->{PARENT_ID} = $$params{'parent_id'};
	$self->{ITEMS} = {};
	$self->{DIRECTORIES} = {};
	$self->{AMOUNT} = 0;

	bless($self, $class);

	unless ($self->{TYPE} eq 'meta')
	{
		$self->initialize();
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
	return $self->{PARENT_ID} if length($self->{PARENT_ID}) > 0;
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
	$string .= $input."\tType (Subtype):".$self->{TYPE}." (".$self->{SUBTYPE}.")\n";
	$string .= $input."\tDirectories: \n";
	foreach my $id (sort keys %{$self->{DIRECTORIES}})
	{
		$string .= $self->{DIRECTORIES}->{$id}->print_object($input."\t");
	}
	$string .= $input."\tItems:       \n";
	foreach my $id (sort keys %{$self->{ITEMS}})
	{
		$string .= $self->{ITEMS}->{$id}->print_object($input."\t");
	}
	$string .= $input."\tAmount:        ".$self->{AMOUNT}."\n";
	$string .= $input."Object PDLNA::ContentDirectory END\n";

	return $string;
}

sub add_item
{
	my $self = shift;
	my $params = shift;

	foreach my $elem (@{$$params{'exclude_items'}})
	{
		PDLNA::Log::log('Checking: '.$elem.' - '.$$params{'filename'}, 3, 'library');
		if ($elem eq basename($$params{'filename'}))
		{
			PDLNA::Log::log('Excluding '.$elem.' from being processed in the ContentLibrary.', 3, 'library');
			return;
		}
	}

	my $id = $$params{'parent_id'}.$$params{'id'};
	$self->{ITEMS}->{$id} = PDLNA::ContentItem->new($params);
	$self->{AMOUNT}++;
}

sub add_directory
{
	my $self = shift;
	my $params = shift;

	foreach my $elem (@{$$params{'exclude_dirs'}})
	{
		PDLNA::Log::log('Checking: '.$elem.' - '.$$params{'path'}, 3, 'library');
		if ($elem eq basename($$params{'path'}))
		{
			PDLNA::Log::log('Excluding '.$elem.' from being processed in the ContentLibrary.', 3, 'library');
			return;
		}
	}

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

	if ($self->{SUBTYPE} eq 'playlist' && -f $self->{PATH}) # if we are a playlist and a file
	{
		# reading the playlist file
		sysopen(PLAYLIST, $self->{PATH}, O_RDONLY);
		my @content = <PLAYLIST>;
		close(PLAYLIST);

		my @items = (); # array which will hold the possible media items

		# parsing the playlist file
		my $mimetype = mimetype($self->{PATH});
		foreach my $line (@content)
		{
			$line =~ s/\r\n//g;
			$line =~ s/\n//g;

			PDLNA::Log::log('Processing playlist line: '.$line.'.', 3, 'library');
			if ($mimetype eq 'audio/x-scpls' && $line =~ /^File\d+\=(.+)$/)
			{
				push(@items, $1);
			}
			elsif (($mimetype eq 'application/vnd.apple.mpegurl' || $mimetype eq 'audio/x-mpegurl') && $line !~ /^#/)
			{
				push(@items, $line);
			}
		}

		# adding items to ContentDirectory
		my $id = 100;
		foreach my $element (@items)
		{
			if ($element =~ /^(http|mms):\/\//)
			{
				my $movie_info = Movie::Info->new();
				unless (defined($movie_info))
				{
					PDLNA::Log::fatal('Unable to find MPlayer.');
				}
				my %info = $movie_info->info($element);
#				foreach (keys %info) { print STDERR "$_ -> $info{$_}\n"; }

				my ($media_type, $mimetype, $file_extension) = '';
				if (defined($info{'audio_codec'}) && !defined($info{'codec'}))
				{
					if ($info{'audio_codec'} eq 'mp3')
					{
						$mimetype = 'audio/mpeg';
						$file_extension = 'MP3';
					}
					$media_type = 'audio';
				}
				elsif (defined($info{'audio_codec'}) && defined($info{'codec'}))
				{
					if ($info{'audio_codec'} eq 'ffwmav2' && $info{'codec'} eq 'ffwmv3')
					{
						$mimetype = 'video/x-ms-wmv';
						$file_extension = 'WMV';
					}
					$media_type = 'video';
				}

				$self->add_item({
					'name' => $element,
					'filename' => $element,
					'streamurl' => $element,
					'type' => $media_type,
					'file' => 0,
					'mimetype' => $mimetype,
					'id' => $id,
					'parent_id' => $self->{ID},
				});
				$id++;
			}
			else # local items
			{
				$element = dirname($self->{PATH}).'/'.$element if $element !~ /^\//;
				if (-f "$element")
				{
					$id = $self->add_content_item($element, undef, $id);
				}
			}
		}
	}

	PDLNA::Log::log("Processing directory '".$self->{PATH}."'.", 2, 'library');

	$self->{PATH} =~ s/\/$//;
	my $id = 100;
	my @elements = bsd_glob($self->{PATH}."/*");
	foreach my $element (sort @elements)
	{
		if ($id > 999)
		{
			PDLNA::Log::log('More than 900 elements in '.$self->{PATH}.'. Skipping further elements.', 1, 'library');
			return;
		}

		if (-d "$element" && $element =~ /lost\+found$/)
		{
			PDLNA::Log::log('Skipping '.$element.' directory.', 1, 'library');
			next;
		}
		elsif (-d "$element" && $self->{RECURSION} eq 'yes')
		{
			$element =~ s/\[/\\[/g;
			$element =~ s/\]/\\]/g;
			$self->add_directory({
				'path' => $element,
				'type' => $self->{TYPE},
				'recursion' => $self->{RECURSION},
				'exclude_dirs' => $self->{EXCLUDE_DIRS},
				'allow_playlists' => $self->{ALLOW_PLAYLISTS},
				'id' => $id,
				'parent_id' => $self->{ID},
			});
			$id++;
		}
		elsif (-f "$element")
		{
			my $mimetype = mimetype($element);
			PDLNA::Log::log("Processing $element with MimeType $mimetype.", 3, 'library');

			if (
					$self->{ALLOW_PLAYLISTS} &&
					(
						$mimetype eq 'audio/x-scpls' || # PLS files
						$mimetype eq 'application/vnd.apple.mpegurl' || $mimetype eq 'audio/x-mpegurl' # M3U files
						# TODO Advanced Stream Redirector (video/x-ms-asf), XML Shareable Playlist Format (application/xspf+xml)
					)
				)
			{
				# we are adding playlist files as directories to the library
				# and so their elements as items in the directory
				PDLNA::Log::log("Adding Playlist element '$element' to database.", 2, 'library');
				$self->add_directory({
					'path' => $element,
					'name' => 'PLAYLIST:'.basename($element),
					'type' => $self->{TYPE},
					'subtype' => 'playlist',
					'id' => $id,
					'parent_id' => $self->{ID},
				});
				$id++;
			}

			$id = $self->add_content_item($element, $mimetype, $id); # this is for normal items
		}
	}
}

sub add_content_item
{
	my $self = shift;
	my $element = shift;
	my $mimetype = shift || mimetype($element);
	my $id = shift;
	my $stream = shift || 0;

	if (
			$mimetype eq 'image/jpeg' || $mimetype eq 'image/gif' ||
			# TODO image/png image/tiff
			$mimetype eq 'audio/mpeg' || $mimetype eq 'audio/mp4' || $mimetype eq 'audio/x-ms-wma' || $mimetype eq 'audio/x-flac' || $mimetype eq 'audio/x-wav' || $mimetype eq 'video/x-theora+ogg' ||
			$mimetype eq 'video/x-msvideo' || $mimetype eq 'video/x-matroska' || $mimetype eq 'video/mp4' || $mimetype eq 'video/mpeg'
		)
	{
		my ($media_type) = split('/', $mimetype, 0);
		$media_type = 'audio' if $mimetype eq 'video/x-theora+ogg';
		if ($media_type && ($media_type eq $self->{TYPE} || $self->{TYPE} eq "all"))
		{
			PDLNA::Log::log("Adding $media_type element '$element' to '".$self->{NAME}."'.", 2, 'library');

			my @fileinfo = stat($element);
			my $year = time2str("%Y-%m", $fileinfo[9]);
			$self->add_item({
				'filename' => $element,
				'date' => $fileinfo[9],
				'size' => $fileinfo[7],
				'type' => $media_type,
				'exclude_items' => $self->{EXCLUDE_ITEMS},
				'id' => $id,
				'parent_id' => $self->{ID},
				'mimetype' => $mimetype,
				'file' => 1,
			});
			$id++;
		}
	}
	return $id;
}

sub get_object_by_id
{
	my $self = shift;
	my $id = shift;

	PDLNA::Log::log('Looking for Element with ID '.$id.' in ContentDirectory with ID '.$self->id().'.', 3, 'library');
	if ($self->id() eq $id)
	{
		return $self;
	}

	my %directories = %{$self->directories()};
	my $subid = '';
	foreach my $key (keys %directories)
	{
		$subid = substr($id, 0, length($key));
		last;
	}
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
