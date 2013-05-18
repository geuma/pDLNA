package PDLNA::ContentLibrary;
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2013 Stefan Heumader <stefan@heumader.at>
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
		

		my $timestamp_start = time();
		foreach my $directory (@{$CONFIG{'DIRECTORIES'}}) # we are not able to run this part in threads - since glob seems to be NOT thread safe
		{
			process_directory(
				
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

		my $i = 0;
		foreach my $external (@{$CONFIG{'EXTERNALS'}})
		{
			add_file_to_db(
				
				{
					'element' => $external->{'command'} || $external->{'streamurl'},
					'media_type' => $external->{'type'},
					'mime_type' => undef, # need to determine
					'element_basename' => $external->{'name'},
					'element_dirname' => undef, # set the directory to nothing - no parent
					'external' => 1,
					'sequence' => $i,
					'root' => 1,
				},
			);
			$i++;
		}
		my $timestamp_end = time();

		# add our timestamp when finished
                PDLNA::Database::metadata_update_value($timestamp_end,'TIMESTAMP');

		my $duration = $timestamp_end - $timestamp_start;
		PDLNA::Log::log('Indexing configured media directories took '.$duration.' seconds.', 1, 'library');

		my ($amount, $size) = PDLNA::Database::files_get_all_size();
		PDLNA::Log::log('Configured media directories include '.$amount.' with '.PDLNA::Utils::convert_bytes($size).' of size.', 1, 'library');

		remove_nonexistant_files();
		get_fileinfo();


		sleep $CONFIG{'RESCAN_MEDIA'};
	}
}

sub process_directory
{

	my $params = shift;
	$$params{'path'} =~ s/\/$//;

	add_directory_to_db( $$params{'path'}, $$params{'rootdir'}, 0);

	$$params{'path'} = PDLNA::Utils::escape_brackets($$params{'path'});
	PDLNA::Log::log('Globbing directory: '.PDLNA::Utils::create_filesystem_path([ $$params{'path'}, '*', ]).'.', 2, 'library');
	my @elements = bsd_glob(PDLNA::Utils::create_filesystem_path([ $$params{'path'}, '*', ]));
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

					my $fileid = add_file_to_db(
						
						{
							'element' => $element,
							'media_type' => $media_type,
							'mime_type' => $mime_type,
							'element_basename' => $element_basename,
							'element_dirname' => dirname($element),
							'external' => 0,
							'root' => 0,
						},
					);

					if ($media_type eq 'video')
					{
						my $tmp = $1 if $element =~ /^(.+)\.\w{3,4}$/;
						foreach my $extension ('srt')
						{
							if (-f $tmp.'.'.$extension)
							{
								my $subtitle_mimetype = mimetype($tmp.'.'.$extension);
								if (PDLNA::Media::is_supported_subtitle($subtitle_mimetype))
								{
									add_subtitle_to_db(
										
										{
											'file_id' => $fileid,
											'path' => $tmp.'.'.$extension,
											'mimetype' => $subtitle_mimetype,
											'type' => $extension,
										},
									);
								}
							}
						}
					}
				}
			}
			elsif (PDLNA::Media::is_supported_playlist($mime_type))
			{
				PDLNA::Log::log('Adding playlist '.$element.' as directory.', 2, 'library');
				add_directory_to_db( $element, $$params{'rootdir'}, 1);
				my @items = PDLNA::Media::parse_playlist($element, $mime_type);
				for (my $i = 0; $i < @items; $i++)
				{
					if (PDLNA::Media::is_supported_stream($items[$i]) && $CONFIG{'LOW_RESOURCE_MODE'} == 0)
					{
						add_file_to_db(
							
							{
								'element' => $items[$i],
								'media_type' => '', # need to determine
								'mime_type' => '', # need to determine
								'element_basename' => $items[$i],
								'element_dirname' => $element, # set the directory to the playlist file itself
								'external' => 1,
								'sequence' => $i,
								'root' => 0,
							},
						);
					}
					else
					{
						unless (PDLNA::Utils::is_path_absolute($items[$i]))
						{
							$items[$i] = PDLNA::Utils::create_filesystem_path([ dirname($element), $items[$i], ]);
						}

						if (-f $items[$i])
						{
							my $mime_type = mimetype($items[$i]);
							my $media_type = PDLNA::Media::return_type_by_mimetype($mime_type);
							add_file_to_db(
								
								{
									'element' => $items[$i],
									'media_type' => $media_type,
									'mime_type' => $mime_type,
									'element_basename' => basename($items[$i]),
									'element_dirname' => $element, # set the directory to the playlist file itself
									'external' => 0,
									'sequence' => $i,
									'root' => 0,
								},
							);
						}
					}
				}

				# delete not (any more) configured - media files from playlists
				my @results = PDLNA::Database::files_get_records_by({PATH => $element});
				foreach my $result (@results)
				{
					unless (grep(/^$result->{NAME}$/, @items) || grep(/^$result->{FULLNAME}$/, @items))
					{
						delete_all_by_itemid( $result->{ID});
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

	my $path = shift;
	my $rootdir = shift;
	my $type = shift;

	# check if directoriy is in db
	my $results = PDLNA::Database::directories_get_record_by_path($path);
	unless (defined($results->{ID}))
	{
		# add directory to database
		PDLNA::Database::directories_insert(basename($path),$path,dirname($path),$rootdir,$type);
		PDLNA::Log::log('Added directory '.$path.' to ContentLibrary.', 2, 'library');
	}
}

sub add_subtitle_to_db
{
	my $params = shift;

	# check if file is in db
	my @records = PDLNA::Database::subtitles_get_records({ FULLNAME => $$params{'path'}, FILEID_REF => $$params{'file_id'}, MIME_TYPE => $$params{'mimetype'}});
    my $results = $records[0];
	my @fileinfo = stat($$params{'path'});

	if (defined($results->{ID}))
	{
		if ($results->{SIZE} != $fileinfo[7] || $results->{DATE} != $fileinfo[9])
		{
			# update the database entry (something changed)
			PDLNA::Database::subtitles_update($fileinfo[9], $fileinfo[7], $results->{ID});
		}
	}
	else # element not in database
	{
		PDLNA::Database::subtitles_insert($$params{'file_id'}, $$params{'path'}, basename($$params{'path'}), $$params{'type'}, $$params{'mimetype'}, $fileinfo[9], $fileinfo[7]);
	}
}

sub add_file_to_db
{
	my $params = shift;

	my @fileinfo = ();
	$fileinfo[9] = 0;
	$fileinfo[7] = 0;
	my $file_extension = '';
	if ($$params{'external'} == 0)
	{
		@fileinfo = stat($$params{'element'});
		$file_extension = $1 if $$params{'element'} =~ /(\w{3,4})$/;
	}

	$$params{'sequence'} = 0 if !defined($$params{'sequence'});

	# check if file is in db
	my @records = PDLNA::Database::files_get_records_by( {FULLNAME => $$params{'element'}, PATH => $$params{'element_dirname'}} );
        my $results = $records[0];
	if (defined($results->{ID}))
	{
		if (
				$results->{SIZE} != $fileinfo[7] ||
				$results->{DATE} != $fileinfo[9] ||
#				$results->{MIME_TYPE} ne $$params{'mime_type'} ||
				$results->{SEQUENCE} != $$params{'sequence'}
			)
		{
			# update the datbase entry (something changed)
			PDLNA::Database::files_update($fileinfo[9], $fileinfo[7], $$params{'mime_type'}, $$params{'media_type'}, $$params{'sequence'}, $results->{ID});

			# set FILEINFO entry to INVALID data
			PDLNA::Database::files_set_invalid($results->{ID});
		}
	}
	else
	{
	        # insert file to db returning ID
		$$params{'size'} = $fileinfo[7];
		$$params{'date'} = $fileinfo[9];
		$$params{'file_extension'} = $file_extension;
		$results = PDLNA::Database::files_insert_returning_record( $params );
		
	}

	return $results->{ID};
}

sub remove_nonexistant_files
{

	PDLNA::Log::log('Started to remove non existant files.', 1, 'library');
	my @files = PDLNA::Database::files_get_non_external_files();

	foreach my $file (@files)
	{
		unless (-f "$file->{FULLNAME}")
		{
			delete_all_by_itemid( $file->{ID} );
		}
	}

	my @directories = PDLNA::Database::directories_get_all();
	foreach my $directory (@directories)
	{
		if (
			($directory->{TYPE} == 0 && !-d "$directory->{PATH}") ||
			($directory->{TYPE} == 1 && !-f "$directory->{PATH}")
		)
		{
			PDLNA::Database::directories_delete( $directory->{ID} );
		}
	}

	my @subtitles = PDLNA::Database::subtitles_get_records();
	foreach my $subtitle (@subtitles)
	{
		unless (-f $subtitle->{FULLNAME})
		{
			PDLNA::Database::subtitles_delete( $subtitle->{ID} );
		}
	}

	# delete not (any more) configured - directories from database
	my @rootdirs = ();
	PDLNA::Database::get_subdirectories_by_id( 0, undef, undef, \@rootdirs);

	my @conf_directories = ();
	foreach my $directory (@{$CONFIG{'DIRECTORIES'}})
	{
	   push(@conf_directories, $directory->{'path'});
	}

	foreach my $rootdir (@rootdirs)
	{
		unless (grep(/^$rootdir->{PATH}\/*$/, @conf_directories))
		{
			delete_subitems_recursively( $rootdir->{ID});
		}
	}

	# delete not (any more) configured - external from database
	my @externals = ();
	PDLNA::Database::get_subfiles_by_id( 0, undef, undef, \@externals);

	my @conf_externals = ();
	foreach my $external (@{$CONFIG{'EXTERNALS'}})
	{
		push(@conf_externals, $external->{'name'});
	}

	foreach my $external (@externals)
	{
		unless (grep(/^$external->{NAME}$/, @conf_externals))
		{
			delete_all_by_itemid( $external->{ID});
		}
	}

	# delete external media items from database, if LOW_RESOURCE_MODE has been enabled
	if ($CONFIG{'LOW_RESOURCE_MODE'} == 1)
	{
		my @externalfiles = PDLNA::Database::files_get_external_files();
		foreach my $externalfile (@externalfiles)
		{
			delete_all_by_itemid( $externalfile->{ID});
		}
	}

	foreach my $directory (@{$CONFIG{'DIRECTORIES'}})
	{
		# delete excluded directories and their items
		foreach my $excl_directory (@{$$directory{'exclude_dirs'}})
		{
			my @directories = PDLNA::Database::sub directories_get_records_by_name_path($excl_directory, $directory->{'path'}.'%');
			foreach my $dir (@directories)
			{
				delete_subitems_recursively( $dir->{ID});
			}
		}

		# delete excluded items
		foreach my $excl_items (@{$$directory{'exclude_items'}})
		{
			my @items = PDLNA::Database::files_get_records_by({NAME => $excl_items, PATH => $directory->{'path'}.'%'});
			foreach my $item (@items)
			{
				delete_all_by_itemid( $item->{ID});
			}
		}
	}
}

sub delete_all_by_itemid
{
	my $object_id = shift;

	PDLNA::Database::files_delete($object_id);
	PDLNA::Database::subtitles_delete_by_fileid($object_id);
}

sub delete_subitems_recursively
{
	my $object_id = shift;

	my @subfiles = ();
	PDLNA::Database::get_subfiles_by_id( $object_id, undef, undef, \@subfiles);
	foreach my $file (@subfiles)
	{
		delete_all_by_itemid( $file->{ID});
	}

	my @subdirs = ();
	PDLNA::Database::get_subdirectories_by_id( $object_id, undef, undef, \@subdirs);
	foreach my $directory (@subdirs)
	{
		delete_subitems_recursively( $directory->{ID});
		PDLNA::Database::directories_delete( $directory->{ID});
	}

	PDLNA::Database::directories_delete( $object_id );
}

sub get_fileinfo
{

	PDLNA::Log::log('Started to fetch metadata for media items.', 1, 'library');
	my @results = PDLNA::Database::files_get_all_valid_records();
	foreach my $id (@results)
	{
		if ($id->{EXTERNAL})
		{
			my %info = ();
			PDLNA::Media::get_mplayer_info($id->{FULLNAME}, \%info);
			if (defined($info{MIME_TYPE}))
			{
				PDLNA::Database::files_update ( $id->{ID}, { FILE_EXTENSION => $info{FILE_EXTENSION}, MIME_TYPE => $info{MIME_TYPE}, TYPE => $info{TYPE} });
				$id->{TYPE} = $info{TYPE};
				$id->{MIME_TYPE} = $info{MIME_TYPE};
			}
			else
			{
				PDLNA::Database::files_update( $id->{ID}, { MIME_TYPE => 'unkn' });
			}
		}

		unless (defined($id->{MIME_TYPE}))
		{
			next;
		}

		#
		# FILL METADATA OF IMAGES
		#
		if ($id->{TYPE} eq 'image')
		{
			my ($width, $height) = PDLNA::Media::get_image_fileinfo($id->{FULLNAME});
			PDLNA::Database::files_update( $id->{ID}, { WIDTH => $width, HEIGHT => $height} );
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
		if ($id->{TYPE} eq 'video' || $id->{TYPE} eq 'audio')
		{
			PDLNA::Media::get_mplayer_info($id->{FULLNAME}, \%info);
			PDLNA::Database::files_update( $id->{ID}, { WIDTH => $info{WIDTH}, HEIGHT => $info{HEIGHT}, DURATION => $info{DURATION}, BITRATE => $info{BITRATE}, CONTAINER => $info{CONTAINER}, AUDIO_CODEC => $info{AUDIO_CODEC}, VIDEO_CODEC => $info{VIDEO_CODEC} } );
			if (defined($info{TYPE}) && defined($info{MIME_TYPE}) && defined($info{FILE_EXTENSION}))
			{
				PDLNA::Database::files_update( $id->{ID}, { FILE_EXTENSION => $info{FILE_EXTENSION}, MIME_TYPE => $info{MIME_TYPE}, TYPE => $info{TYPE} });
			}

			if ($id->{TYPE} eq 'video')
			{
				PDLNA::Database::files_set_valid( $id->{ID});
			}
		}

		#
		# FILL METADATA OF AUDIO FILES
		#
		if ($id->{TYPE} eq 'audio' && defined($info{AUDIO_CODEC}))
		{
			my %audioinfo = (
				'ARTIST' => undef,
				'ALBUM' => undef,
				'TRACKNUM' => undef,
				'TITLE' => undef,
				'GENRE' => undef,
				'YEAR' => undef,
			);
			PDLNA::Media::get_audio_fileinfo($id->{FULLNAME}, $info{AUDIO_CODEC}, \%audioinfo);
			PDLNA::Database::files_update( $id->{ID} , \%audioinfo );
			PDLNA::Database::files_set_valid( $id->{ID});
		}
	}
}

#
# various function for getting information about the ContentLibrary from the DB
#

sub get_amount_elements_by_id
{
 my $object_id = shift;
                
             my $directory_amount = 0;
             $directory_amount += PDLNA::Database::get_amount_subdirectories_by_id( $object_id);
             $directory_amount += PDLNA::Database::get_amount_subfiles_by_id( $object_id);
                                       
         return $directory_amount;
}


sub is_in_same_directory_tree
{
	my $parent_id = shift;
	my $child_id = shift;

	while ($child_id != 0)
	{
		return 1 if $parent_id eq $child_id;
		$child_id = PDLNA::Database::get_parent_of_directory_by_id( $child_id);
	}

	return 0;
}


#
# helper functions
#

# TODO make it more beautiful
sub duration
{
	my $duration_seconds = shift || 0;

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
