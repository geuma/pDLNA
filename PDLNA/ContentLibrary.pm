package PDLNA::ContentLibrary;
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

use DBI;
use Date::Format;
use File::Basename;
use File::Glob qw(bsd_glob);
use File::MimeInfo;

use PDLNA::Config;
use PDLNA::Database;
use PDLNA::Log;
use PDLNA::Media;
use PDLNA::Utils;

sub index_directories_thread
{
	PDLNA::Log::log('Starting PDLNA::ContentLibrary::index_directories_thread().', 1, 'library');
	while(1)
	{
		my $dbh = PDLNA::Database::connect();

		my $timestamp_start = time();
		foreach my $directory (@{$CONFIG{'DIRECTORIES'}}) # we are not able to run this part in threads - since glob seems to be NOT thread safe
		{
			process_directory(
				$dbh,
				{
					'path' => $directory->{'path'},
					'type' => $directory->{'type'},
					'recursion' => $directory->{'recursion'},
					'exclude_dirs' => $directory->{'exclude_dirs'},
					'exclude_items' => $directory->{'exclude_items'},
					'allow_playlists' => $directory->{'allow_playlists'},
					'rootdir' => 1,
				},
			);
		}
		my $timestamp_end = time();

		# add our timestamp when finished
		PDLNA::Database::update_db(
			$dbh,
			{
				'query' => "UPDATE METADATA SET VALUE = ? WHERE KEY = 'TIMESTAMP'",
				'parameters' => [ $timestamp_end, ],
			},
		);

		my $duration = $timestamp_end - $timestamp_start;
		PDLNA::Log::log('Indexing configured media directories took '.$duration.' seconds.', 1, 'library');

		my @results = ();
		PDLNA::Database::select_db(
			$dbh,
			{
				'query' => 'SELECT COUNT(*) AS AMOUNT, SUM(SIZE) AS SIZE FROM FILES;',
				'parameters' => [ ],
			},
			\@results,
		);
		PDLNA::Log::log('Configured media directories include '.$results[0]->{AMOUNT}.' with '.PDLNA::Utils::convert_bytes($results[0]->{SIZE}).' of size.', 1, 'library');

		remove_nonexistant_files();
		get_fileinfo();

		sleep $CONFIG{'RESCAN_MEDIA'};
	}
}

sub process_directory
{
	my $dbh = shift;
	my $params = shift;
	$$params{'path'} =~ s/\/$//;

	add_directory_to_db($dbh, $$params{'path'}, $$params{'rootdir'}, 0);

	my @elements = bsd_glob($$params{'path'}.'/*'); # TODO fix for Windows
	foreach my $element (sort @elements)
	{
		my $element_basename = basename($element);

		if (-d "$element" && $element =~ /lost\+found$/)
		{
			PDLNA::Log::log('Skipping '.$element.' directory.', 2, 'library');
			next;
		}
		elsif (-d "$element" && $$params{'recursion'} eq 'yes' && !grep(/^$element_basename$/, @{$$params{'exclude_dirs'}}))
		{
			PDLNA::Log::log('Processing directory '.$element.'.', 2, 'library');

			process_directory(
				$dbh,
				{
					'path' => $element,
					'type' => $$params{'type'},
					'recursion' => $$params{'recursion'},
					'exclude_dirs' => $$params{'exclude_dirs'},
					'exclude_items' => $$params{'exclude_items'},
					'allow_playlists' => $$params{'allow_playlists'},
					'rootdir' => 0,
				}
			);
		}
		elsif (-f "$element" && !grep(/^$element_basename$/, @{$$params{'exclude_items'}}))
		{
			my $mime_type = mimetype($element);
			PDLNA::Log::log('Processing '.$element.' with MimeType '.$mime_type.'.', 2, 'library');

			if (PDLNA::Media::is_supported_mimetype($mime_type))
			{
				my $media_type = PDLNA::Media::return_type_by_mimetype($mime_type);
				if ($media_type && ($media_type eq $$params{'type'} || $$params{'type'} eq "all"))
				{
					PDLNA::Log::log('Adding '.$media_type.' element '.$element.'.', 2, 'library');

					add_file_to_db(
						$dbh,
						{
							'element' => $element,
							'media_type' => $media_type,
							'mime_type' => $mime_type,
							'element_basename' => $element_basename,
							'element_dirname' => dirname($element),
							'external' => 0,
						},
					);
				}
			}
			elsif (PDLNA::Media::is_supported_playlist($mime_type))
			{
				PDLNA::Log::log('Adding playlist '.$element.' as directory.', 2, 'library');

				add_directory_to_db($dbh, $element, $$params{'rootdir'}, 1);

				my @items = PDLNA::Media::parse_playlist($element, $mime_type);
				foreach my $item (@items)
				{
					if ($item =~ /^(http|mms):\/\// && $CONFIG{'LOW_RESOURCE_MODE'} == 0)
					{
						# TODO streaming urls
#						add_file_to_db(
#							$dbh,
#							{
#								'element' => $item, # this is the command which should be executed
#								'media_type' => $media_type, # need to determine
#								'mime_type' => $mime_type, # need to determine
#								'element_basename' => $item,
#								'element_dirname' => $element, # set the directory to the playlist file itself
#								'external' => 1,
#							},
#						);
					}
					# TODO support for relative paths
					# works currently only for absolute paths
					elsif (-f "$item")
					{
						my $mime_type = mimetype($item);
						my $media_type = PDLNA::Media::return_type_by_mimetype($mime_type);
						add_file_to_db(
							$dbh,
							{
								'element' => $item,
								'media_type' => $media_type,
								'mime_type' => $mime_type,
								'element_basename' => basename($item),
								'element_dirname' => $element, # set the directory to the playlist file itself
								'external' => 0,
							},
						);
					}
				}
			}
			else
			{
				PDLNA::Log::log('Element '.$element.' skipped. Unsupported MimeType '.$mime_type.'.', 2, 'library');
			}
		}
		else
		{
			PDLNA::Log::log('Element '.$element.' skipped. Inlcuded in ExcludeList.', 2, 'library');
		}
	}
}

sub add_directory_to_db
{
	my $dbh = shift;
	my $path = shift;
	my $rootdir = shift;
	my $type = shift;

	# check if directoriy is in db
	my @results = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT ID FROM DIRECTORIES WHERE PATH = ?',
			'parameters' => [ $path, ],
		},
		\@results,
	);

	unless (defined($results[0]->{ID}))
	{
		# add directory to database
		PDLNA::Database::insert_db(
			$dbh,
			{
				'query' => 'INSERT INTO DIRECTORIES (NAME, PATH, DIRNAME, ROOT, TYPE) VALUES (?,?,?,?,?)',
				'parameters' => [ basename($path), $path, dirname($path), $rootdir, $type ],
			},
		);
	}
}

sub add_file_to_db
{
	my $dbh = shift;
	my $params = shift;

	my @fileinfo = stat($$params{'element'});
	my $file_extension = $1 if $$params{'element'} =~ /(\w{3,4})$/;

	# check if file is in db
	my @results = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT ID, DATE, SIZE, MIME_TYPE FROM FILES WHERE FULLNAME = ?',
			'parameters' => [ $$params{'element'}, ],
		},
		\@results,
	);

	if (defined($results[0]->{ID}))
	{
		if ($results[0]->{SIZE} != $fileinfo[7] || $results[0]->{DATE} != $fileinfo[9] || $results[0]->{MIME_TYPE} ne $$params{'mime_type'})
		{
			# update the datbase entry (something changed)
			PDLNA::Database::update_db(
				$dbh,
				{
					'query' => 'UPDATE FILES SET DATE = ?, SIZE = ?, MIME_TYPE = ?, TYPE = ?, EXTERNAL = ? WHERE ID = ?;',
					'parameters' => [ $fileinfo[9], $fileinfo[7], $$params{'mime_type'}, $$params{'media_type'}, $results[0]->{ID}, $$params{'external'}, ],
				},
			);

			# set FILEINFO entry to INVALID data
			PDLNA::Database::update_db(
				$dbh,
				{
					'query' => 'UPDATE FILEINFO SET VALID = ? WHERE ID = ?;',
					'parameters' => [ 0, $results[0]->{ID}, ],
				},
			);
		}
	}
	else # element not in database
	{
		# insert file to db
		PDLNA::Database::insert_db(
			$dbh,
			{
				'query' => 'INSERT INTO FILES (NAME, PATH, FULLNAME, FILE_EXTENSION, DATE, SIZE, MIME_TYPE, TYPE, EXTERNAL) VALUES (?, ?, ?, ?, ?, ?, ?, ?,?)',
				'parameters' => [ $$params{'element_basename'}, $$params{'element_dirname'}, $$params{'element'}, $file_extension, $fileinfo[9], $fileinfo[7], $$params{'mime_type'}, $$params{'media_type'}, $$params{'external'}, ],
			},
		);

		# select ID of newly added element
		my @results = ();
		PDLNA::Database::select_db(
			$dbh,
			{
				'query' => 'SELECT ID FROM FILES WHERE FULLNAME = ?',
				'parameters' => [ $$params{'element'}, ],
			},
			\@results,
		);

		# insert entry to FILEINFO table
		PDLNA::Database::insert_db(
			$dbh,
			{
				'query' => 'INSERT INTO FILEINFO (ID_REF, VALID, WIDTH, HEIGHT, DURATION, BITRATE, VBR, ARTIST, ALBUM, TITLE, GENRE, YEAR, TRACKNUM) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
				'parameters' => [ $results[0]->{ID}, 0, 0, 0, 0, 0, 0, 'n/A', 'n/A', 'n/A', 'n/A', '0000', 0, ],
			},
		);
	}
}

sub remove_nonexistant_files
{
	PDLNA::Log::log('Started to remove non existant files.', 1, 'library');
	my $dbh = PDLNA::Database::connect();
	my @files = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT ID, FULLNAME FROM FILES',
			'parameters' => [ ],
		},
		\@files,
	);

	foreach my $file (@files)
	{
		unless (-f "$file->{FULLNAME}")
		{
			PDLNA::Database::delete_db(
				$dbh,
				{
					'query' => 'DELETE FROM FILES WHERE ID = ?',
					'parameters' => [ $file->{ID}, ],
				},
			);
			PDLNA::Database::delete_db(
				$dbh,
				{
					'query' => 'DELETE FROM FILEINFO WHERE ID_REF = ?',
					'parameters' => [ $file->{ID}, ],
				},
			);
		}
	}

	my @directories = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT ID, PATH, TYPE FROM DIRECTORIES',
			'parameters' => [ ],
		},
		\@directories,
	);
	foreach my $directory (@directories)
	{
		if (
			($directory->{TYPE} == 0 && !-d "$directory->{PATH}") ||
			($directory->{TYPE} == 1 && !-f "$directory->{PATH}")
		)
		{
			PDLNA::Database::delete_db(
				$dbh,
				{
					'query' => 'DELETE FROM DIRECTORIES WHERE ID = ?',
					'parameters' => [ $directory->{ID}, ],
				},
			);
		}
	}
}

sub get_fileinfo
{
	PDLNA::Log::log('Started to fetch metadata for media items.', 1, 'library');

	my $dbh = PDLNA::Database::connect();

	my @results = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT ID_REF FROM FILEINFO WHERE VALID = ?',
			'parameters' => [ 0, ],
		},
		\@results,
	);

	foreach my $id (@results)
	{
		my @file = ();
		PDLNA::Database::select_db(
			$dbh,
			{
				'query' => 'SELECT FULLNAME, TYPE FROM FILES WHERE ID = ?',
				'parameters' => [ $id->{ID_REF}, ],
			},
			\@file,
		);

		#
		# FILL METADATA OF IMAGES
		#
		if ($file[0]->{TYPE} eq 'image')
		{
			my ($width, $height) = PDLNA::Media::get_image_fileinfo($file[0]->{FULLNAME});
			PDLNA::Database::update_db(
				$dbh,
				{
					'query' => 'UPDATE FILEINFO SET WIDTH = ?, HEIGHT = ?, VALID = ? WHERE ID_REF = ?',
					'parameters' => [ $width, $height, 1, $id->{ID_REF}, ],
				},
			);
			next;
		}

		if ($CONFIG{'LOW_RESOURCE_MODE'} == 1)
		{
			next;
		}

		#
		# FILL MPLAYER DATA OF VIDEO OR AUDIO FILES
		#
		my %info = ();
		if ($file[0]->{TYPE} eq 'video' || $file[0]->{TYPE} eq 'audio')
		{
			PDLNA::Media::get_mplayer_info($file[0]->{FULLNAME}, \%info);
			PDLNA::Database::update_db(
				$dbh,
				{
					'query' => 'UPDATE FILEINFO SET WIDTH = ?, HEIGHT = ?, DURATION = ?, BITRATE = ?, CONTAINER = ?, AUDIO_CODEC = ?, VIDEO_CODEC = ? WHERE ID_REF = ?',
					'parameters' => [ $info{WIDTH}, $info{HEIGHT}, $info{DURATION}, $info{BITRATE}, $info{CONTAINER}, $info{AUDIO_CODEC}, $info{VIDEO_CODEC}, $id->{ID_REF}, ],
				},
			);

			if ($file[0]->{TYPE} eq 'video')
			{
				PDLNA::Database::update_db(
					$dbh,
					{
						'query' => 'UPDATE FILEINFO SET VALID = ? WHERE ID_REF = ?',
						'parameters' => [ 1, $id->{ID_REF}, ],
					},
				);
			}
		}

		#
		# FILL METADATA OF AUDIO FILES
		#
		if ($file[0]->{TYPE} eq 'audio' && defined($info{AUDIO_CODEC}))
		{
			my %audioinfo = ();
			PDLNA::Media::get_audio_fileinfo($file[0]->{FULLNAME}, $info{AUDIO_CODEC}, \%audioinfo);

			PDLNA::Database::update_db(
				$dbh,
				{
					'query' => 'UPDATE FILEINFO SET ARTIST = ?, ALBUM = ?, TITLE = ?, GENRE = ?, YEAR = ?, TRACKNUM = ?, VALID = ? WHERE ID_REF = ?',
					'parameters' => [ $audioinfo{ARTIST}, $audioinfo{ALBUM}, $audioinfo{TITLE}, $audioinfo{GENRE}, $audioinfo{YEAR}, $audioinfo{TRACKNUM}, 1, $id->{ID_REF}, ],
				},
			);
		}
	}
}

#
# various function for getting information about the ContentLibrary from the DB
#

sub get_subdirectories_by_id
{
	my $dbh = shift;
	my $object_id = shift;
	my $starting_index = shift;
	my $requested_count = shift;
	my $directory_elements = shift;

	my $sql_query = 'SELECT ID, NAME FROM DIRECTORIES WHERE ';
	my @sql_param = ();

	if ($object_id == 0)
	{
		$sql_query .= 'ROOT = 1';
	}
	else
	{
		$sql_query .= 'DIRNAME IN ( SELECT PATH FROM DIRECTORIES WHERE ID = ? )';
		push(@sql_param, $object_id);
	}

	if (defined($starting_index) && defined($requested_count))
	{
		$sql_query .= ' LIMIT '.$starting_index.', '.$requested_count;
	}

	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => $sql_query,
			'parameters' => \@sql_param,
		},
		$directory_elements,
	);
}

sub get_subfiles_by_id
{
	my $dbh = shift;
	my $object_id = shift;
	my $starting_index = shift;
	my $requested_count = shift;
	my $file_elements = shift;

	my $sql_query = 'SELECT ID, NAME, SIZE, DATE FROM FILES WHERE PATH IN ( SELECT PATH FROM DIRECTORIES WHERE ID = ? )';
	my @sql_param = ( $object_id, );

	if (defined($starting_index) && defined($requested_count))
	{
		$sql_query .= ' LIMIT '.$starting_index.', '.$requested_count;
	}

	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => $sql_query,
			'parameters' => \@sql_param,
		},
		$file_elements,
	);
}

sub get_subfiles_size_by_id
{
	my $dbh = shift;
	my $object_id = shift;

	my @result = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT SUM(SIZE) AS FULLSIZE FROM FILES WHERE PATH IN ( SELECT PATH FROM DIRECTORIES WHERE ID = ? )',
			'parameters' => [ $object_id, ],
		},
		\@result,
	);
	return $result[0]->{FULLSIZE};
}

sub get_amount_subdirectories_by_id
{
	my $dbh = shift;
	my $object_id = shift;

	my @directory_amount = ();

	my $sql_query = 'SELECT COUNT(ID) AS AMOUNT FROM DIRECTORIES WHERE ';
	my @sql_param = ();
	if ($object_id == 0)
	{
		$sql_query .= 'ROOT = 1';
	}
	else
	{
		$sql_query .= 'DIRNAME IN ( SELECT PATH FROM DIRECTORIES WHERE ID = ? )';
		push(@sql_param, $object_id);
	}

	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => $sql_query,
			'parameters' => \@sql_param,
		},
		\@directory_amount,
	);

	return $directory_amount[0]->{AMOUNT};
}

sub get_amount_subfiles_by_id
{
	my $dbh = shift;
	my $object_id = shift;

	my @files_amount = ();

	my $sql_query = 'SELECT COUNT(ID) AS AMOUNT FROM FILES WHERE PATH IN ( SELECT PATH FROM DIRECTORIES WHERE ID = ?)';
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => $sql_query,
			'parameters' => [ $object_id, ],
		},
		\@files_amount,
	);

	return $files_amount[0]->{AMOUNT};
}

sub get_amount_elements_by_id
{
	my $dbh = shift;
	my $object_id = shift;

	my $directory_amount = 0;
	$directory_amount += get_amount_subdirectories_by_id($dbh, $object_id);
	$directory_amount += get_amount_subfiles_by_id($dbh, $object_id);

	return $directory_amount;
}

sub get_parent_of_directory_by_id
{
	my $dbh = shift;
	my $object_id = shift;

	my @directory_parent = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT ID FROM DIRECTORIES WHERE PATH IN ( SELECT DIRNAME FROM DIRECTORIES WHERE ID = ? )',
			'parameters' => [ $object_id, ],
		},
		\@directory_parent,
	);
	$directory_parent[0]->{ID} = 0 if !defined($directory_parent[0]->{ID});

	return $directory_parent[0]->{ID};
}

sub get_parent_of_item_by_id
{
	my $dbh = shift;
	my $object_id = shift;

	my @item_parent = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT ID FROM DIRECTORIES WHERE PATH IN ( SELECT PATH FROM FILES WHERE ID = ? )',
			'parameters' => [ $object_id, ],
		},
		\@item_parent,
	);

	return $item_parent[0]->{ID};
}

#
# helper functions
#

# TODO make it more beautiful
sub duration
{
	my $duration_seconds = shift;

	my $seconds = $duration_seconds;
	my $minutes = 0;
	$minutes = int($seconds / 60) if $seconds > 59;
	$seconds -= $minutes * 60 if $seconds;
	my $hours = 0;
	$hours = int($minutes / 60) if $minutes > 59;
	$minutes -= $hours * 60 if $hours;

	my $string = '';
	$string .= PDLNA::Utils::add_leading_char($hours,2,'0').':';
	$string .= PDLNA::Utils::add_leading_char($minutes,2,'0').':';
	$string .= PDLNA::Utils::add_leading_char($seconds,2,'0');

	return $string;
}


1;

#	my $params = shift;

#	my %self : shared = ();
#	$self{TIMESTAMP} = time();
#	my %directories : shared = ();

#	$self->{DIRECTORIES}->{0} = PDLNA::ContentDirectory->new({
#		'type' => 'meta',
#		'name' => 'BaseView',
#		'id' => 0,
#		'parent_id' => '',
#	});
#
#	if ($CONFIG{'SPECIFIC_VIEWS'})
#	{
#		$self->{DIRECTORIES}->{'A_A'} = PDLNA::ContentDirectory->new({
#			'type' => 'meta',
#			'name' => 'Audio sorted by Artist',
#			'id' => 'A_A',
#			'parent_id' => '',
#		});
#		$self->{DIRECTORIES}->{'A_F'} = PDLNA::ContentDirectory->new({
#			'type' => 'meta',
#			'name' => 'Audio sorted by Folder',
#			'id' => 'A_F',
#			'parent_id' => '',
#		});
#		$self->{DIRECTORIES}->{'A_G'} = PDLNA::ContentDirectory->new({
#			'type' => 'meta',
#			'name' => 'Audio sorted by Genre',
#			'id' => 'A_G',
#			'parent_id' => '',
#		});
#		$self->{DIRECTORIES}->{'A_M'} = PDLNA::ContentDirectory->new({ # moods: WTF (dynamic)
#			'type' => 'meta',
#			'name' => 'Audio sorted by Mood',
#			'id' => 'A_M',
#			'parent_id' => '',
#		});
#		$self->{DIRECTORIES}->{'A_T'} = PDLNA::ContentDirectory->new({
#			'type' => 'meta',
#			'name' => 'Audio sorted by Title (Alphabet)',
#			'id' => 'A_M',
#			'parent_id' => '',
#		});
#
#		$self->{DIRECTORIES}->{'I_F'} = PDLNA::ContentDirectory->new({
#			'type' => 'meta',
#			'name' => 'Images sorted by Folder',
#			'id' => 'I_F',
#			'parent_id' => '',
#		});
#		$self->{DIRECTORIES}->{'I_T'} = PDLNA::ContentDirectory->new({
#			'type' => 'meta',
#			'name' => 'Images sorted by Date',
#			'id' => 'I_T',
#			'parent_id' => '',
#		});
#
#		$self->{DIRECTORIES}->{'V_D'} = PDLNA::ContentDirectory->new({
#			'type' => 'meta',
#			'name' => 'Videos sorted by Date',
#			'id' => 'V_D',
#			'parent_id' => '',
#		});
#		$self->{DIRECTORIES}->{'V_F'} = PDLNA::ContentDirectory->new({
#			'type' => 'meta',
#			'name' => 'Videos sorted by Folder',
#			'id' => 'V_F',
#			'parent_id' => '',
#		});
#		$self->{DIRECTORIES}->{'V_T'} = PDLNA::ContentDirectory->new({
#			'type' => 'meta',
#			'name' => 'Videos sorted by Title (Alphabet)',
#			'id' => 'V_T',
#			'parent_id' => '',
#		});
#	}
#
#	my $i = 100;
#	foreach my $directory (@{$CONFIG{'DIRECTORIES'}})
#	{
#		if ($i > 999)
#		{
#			PDLNA::Log::log('More than 900 configured directories. Skip to load directory: '.$directory, 1, 'library');
#			next;
#		}
#
#		# BaseView
#		$self->{DIRECTORIES}->{0}->add_directory({
#			'path' => $directory->{'path'},
#			'type' => $directory->{'type'},
#			'recursion' => $directory->{'recursion'},
#			'exclude_dirs' => $directory->{'exclude_dirs'},
#			'exclude_items' => $directory->{'exclude_items'},
#			'allow_playlists' => $directory->{'allow_playlists'},
#			'id' => $i,
#			'parent_id' => '',
#		});
#		$i++;
#	}
#
#	foreach my $external (@{$CONFIG{'EXTERNALS'}})
#	{
#		if ($i > 999)
#		{
#			PDLNA::Log::log('More than 900 configured main entries. Skip to load external: '.$external, 1, 'library');
#			next;
#		}
#
#		# BaseView
#		$self->{DIRECTORIES}->{0}->add_item({
#			'name' => $external->{'name'},
#			'filename' => $external->{'command'},
#			'command' => $external->{'command'},
#			'streamurl' => $external->{'streamurl'},
#			'id' => $i,
#			'parent_id' => '',
#		});
#		$i++;
#	}
#
#	$self{TIMESTAMP_FINISHED} = time();
#	$self{DIRECTORIES} = \%directories;
#
#	bless(\%self, $class);
#	return \%self;
#}
