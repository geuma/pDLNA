package PDLNA::ContentLibrary;
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2018 Stefan Heumader-Rainer <stefan@heumader.at>
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
use PDLNA::FFmpeg;
use PDLNA::Log;
use PDLNA::Media;
use PDLNA::Utils;

sub index_directories_thread
{
	PDLNA::Log::log('Starting PDLNA::ContentLibrary::index_directories_thread().', 1, 'library');
	while(1)
	{
		my $dbh = PDLNA::Database::connect();
		$dbh->{AutoCommit} = 0;

		my $timestamp_start = time();
		foreach my $directory (@{$CONFIG{'DIRECTORIES'}}) # we are not able to run this part in threads - since glob seems to be NOT thread safe
		{
			_process_directory(
				$dbh,
				{
					'fullname' => $directory->{'path'},
					'media_type' => $directory->{'type'},
					'recursion' => $directory->{'recursion'},
					'exclude_dirs' => $directory->{'exclude_dirs'},
					'exclude_items' => $directory->{'exclude_items'},
					'allow_playlists' => $directory->{'allow_playlists'},
					'parent_id' => 0,
				},
			);
		}

#		my $i = 0;
#		foreach my $external (@{$CONFIG{'EXTERNALS'}})
#		{
#			add_file_to_db(
#				$dbh,
#				{
#					'element' => $external->{'command'} || $external->{'streamurl'},
#					'media_type' => $external->{'type'},
#					'mime_type' => '', # need to determine
#					'element_basename' => $external->{'name'},
#					'element_dirname' => '', # set the directory to nothing - no parent
#					'external' => 1,
#					'sequence' => $i,
#					'root' => 1,
#				},
#			);
#			$i++;
#		}
		$dbh->commit();
		my $timestamp_end = time();

		# update our timestamp when finished
		PDLNA::Database::update_db(
			$dbh,
			{
				'query' => 'UPDATE metadata SET value = ? WHERE param = ?',
				'parameters' => [ $timestamp_end, 'TIMESTAMP', ],
			},
		);
		$dbh->commit();

		my $duration = $timestamp_end - $timestamp_start;
		PDLNA::Log::log('Indexing configured media directories took '.$duration.' seconds.', 1, 'library');

		my ($amount, $size) = get_amount_size_items_by($dbh, 'item_type', 1);
		PDLNA::Log::log('Configured media directories include '.$amount.' items with '.PDLNA::Utils::convert_bytes($size).' of size.', 1, 'library');

		_cleanup_contentlibrary($dbh);
		$dbh->commit();

		$timestamp_start = time();
		_fetch_media_attributes($dbh);
		$dbh->commit();
		$timestamp_end = time();
		$duration = $timestamp_end - $timestamp_start;
		PDLNA::Log::log('Getting media attributes for indexed media items took '.$duration.' seconds.', 1, 'library');

		PDLNA::Database::disconnect($dbh);

		sleep $CONFIG{'RESCAN_MEDIA'};
	}
}

sub process_directory
{
	my $dbh = shift;
	my $params = shift;
	$$params{'path'} =~ s/\/$//;

	add_directory_to_db($dbh, $$params{'path'}, $$params{'rootdir'}, 0);
	$dbh->commit();

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
		elsif (-d "$element" && $$params{'recursion'} eq 'yes' && !grep(/^\Q$element_basename\E$/, @{$$params{'exclude_dirs'}}))
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
		elsif (-f "$element" && !grep(/^\Q$element_basename\E$/, @{$$params{'exclude_items'}}))
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
						$dbh,
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
										$dbh,
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

				add_directory_to_db($dbh, $element, $$params{'rootdir'}, 1);

				my @items = PDLNA::Media::parse_playlist($element, $mime_type);
				for (my $i = 0; $i < @items; $i++)
				{
					if (PDLNA::Media::is_supported_stream($items[$i]) && $CONFIG{'LOW_RESOURCE_MODE'} == 0)
					{
						add_file_to_db(
							$dbh,
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
								$dbh,
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
				my @results = ();
				PDLNA::Database::select_db(
					$dbh,
					{
						'query' => 'SELECT ID, NAME, FULLNAME FROM FILES WHERE PATH = ?',
						'parameters' => [ $element, ],
					},
					\@results,
				);

				foreach my $result (@results)
				{
					unless (grep(/^\Q$result->{NAME}\E$/, @items) || grep(/^\Q$result->{FULLNAME}\E$/, @items))
					{
						delete_all_by_itemid($dbh, $result->{ID});
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
		PDLNA::Log::log('Added directory '.$path.' to ContentLibrary.', 2, 'library');
	}
}

sub add_subtitle_to_db
{
	my $dbh = shift;
	my $params = shift;

	# check if file is in db
	my @results = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT id, date, size FROM subtitles WHERE fullname = ? AND fileid_ref = ? AND mime_type = ?',
			'parameters' => [ $$params{'path'}, $$params{'file_id'}, $$params{'mimetype'}, ],
		},
		\@results,
	);

	my @fileinfo = stat($$params{'path'});

	if (defined($results[0]->{id}))
	{
		if ($results[0]->{size} != $fileinfo[7] || $results[0]->{date} != $fileinfo[9])
		{
			# update the datbase entry (something changed)
			PDLNA::Database::update_db(
				$dbh,
				{
					'query' => 'UPDATE subtitles SET date = ?, size = ? WHERE id = ?;',
					'parameters' => [ $fileinfo[9], $fileinfo[7], $results[0]->{ID}, ],
				},
			);

		}
	}
	else # element not in database
	{
		PDLNA::Database::insert_db(
			$dbh,
			{
				'query' => 'INSERT INTO subtitles (fileid_ref, fullname, name, type, mime_type, date, size) VALUES (?,?,?,?,?,?,?)',
				'parameters' => [ $$params{'file_id'}, $$params{'path'}, basename($$params{'path'}), $$params{'type'}, $$params{'mimetype'}, $fileinfo[9], $fileinfo[7], ],
			},
		);
	}
}

sub add_file_to_db
{
	my $dbh = shift;
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
	my @results = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT ID, DATE, SIZE, MIME_TYPE, PATH, SEQUENCE FROM FILES WHERE FULLNAME = ? AND PATH = ?',
			'parameters' => [ $$params{'element'}, $$params{'element_dirname'}, ],
		},
		\@results,
	);

	if (defined($results[0]->{ID}))
	{
		if (
				$results[0]->{SIZE} != $fileinfo[7] ||
				$results[0]->{DATE} != $fileinfo[9] ||
#				$results[0]->{MIME_TYPE} ne $$params{'mime_type'} ||
				$results[0]->{SEQUENCE} != $$params{'sequence'}
			)
		{
			# update the datbase entry (something changed)
			PDLNA::Database::update_db(
				$dbh,
				{
					'query' => 'UPDATE FILES SET DATE = ?, SIZE = ?, MIME_TYPE = ?, TYPE = ?, SEQUENCE = ? WHERE ID = ?;',
					'parameters' => [ $fileinfo[9], $fileinfo[7], $$params{'mime_type'}, $$params{'media_type'}, $$params{'sequence'}, $results[0]->{ID} ],
				},
			);

			# set FILEINFO entry to INVALID data
			PDLNA::Database::update_db(
				$dbh,
				{
					'query' => 'UPDATE FILEINFO SET VALID = ? WHERE FILEID_REF = ?;',
					'parameters' => [ 0, $results[0]->{ID}, ],
				},
			);
		}
	}
	else
	{
		# insert file to db
		PDLNA::Database::insert_db(
			$dbh,
			{
				'query' => 'INSERT INTO FILES (NAME, PATH, FULLNAME, FILE_EXTENSION, DATE, SIZE, MIME_TYPE, TYPE, EXTERNAL, ROOT, SEQUENCE) VALUES (?,?,?,?,?,?,?,?,?,?,?)',
				'parameters' => [ $$params{'element_basename'}, $$params{'element_dirname'}, $$params{'element'}, $file_extension, $fileinfo[9], $fileinfo[7], $$params{'mime_type'}, $$params{'media_type'}, $$params{'external'}, $$params{'root'}, $$params{'sequence'}, ],
			},
		);

		# select ID of newly added element
		@results = ();
		PDLNA::Database::select_db(
			$dbh,
			{
				'query' => 'SELECT ID FROM FILES WHERE FULLNAME = ? AND PATH = ?',
				'parameters' => [ $$params{'element'}, $$params{'element_dirname'}, ],
			},
			\@results,
		);

		# insert entry to FILEINFO table
		PDLNA::Database::insert_db(
			$dbh,
			{
				'query' => 'INSERT INTO FILEINFO (FILEID_REF, VALID) VALUES (?,?)',
				'parameters' => [ $results[0]->{ID}, 0, ],
			},
		);
	}

	return $results[0]->{ID};
}

sub cleanup_contentlibrary
{
	my $dbh = shift;

	PDLNA::Log::log('Started to remove non existant files.', 1, 'library');
	my @files = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT ID, FULLNAME FROM FILES WHERE EXTERNAL = 0',
			'parameters' => [ ],
		},
		\@files,
	);

	foreach my $file (@files)
	{
		unless (-f "$file->{FULLNAME}")
		{
			delete_all_by_itemid($dbh, $file->{ID});
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

	my @subtitles = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT id, fullname FROM subtitles',
			'parameters' => [ ],
		},
		\@subtitles,
	);
	foreach my $subtitle (@subtitles)
	{
		unless (-f $subtitle->{fullname})
		{
			PDLNA::Database::delete_db(
				$dbh,
				{
					'query' => 'DELETE FROM subtitles WHERE id = ?',
					'parameters' => [ $subtitle->{id}, ],
				},
			);
		}
	}

	# delete not (any more) configured - directories from database
	my @rootdirs = ();
	get_subdirectories_by_id($dbh, 0, undef, undef, \@rootdirs);

	my @conf_directories = ();
	foreach my $directory (@{$CONFIG{'DIRECTORIES'}})
	{
		push(@conf_directories, $directory->{'path'});
	}

	foreach my $rootdir (@rootdirs)
	{
		unless (grep(/^$rootdir->{PATH}\/$/, @conf_directories))
		{
			delete_subitems_recursively($dbh, $rootdir->{ID});
		}
	}

	# delete not (any more) configured - external from database
	my @externals = ();
	get_subfiles_by_id($dbh, 0, undef, undef, \@externals);

	my @conf_externals = ();
	foreach my $external (@{$CONFIG{'EXTERNALS'}})
	{
		push(@conf_externals, $external->{'name'});
	}

	foreach my $external (@externals)
	{
		unless (grep(/^$external->{NAME}$/, @conf_externals))
		{
			delete_all_by_itemid($dbh, $external->{ID});
		}
	}

	# delete external media items from database, if LOW_RESOURCE_MODE has been enabled
	if ($CONFIG{'LOW_RESOURCE_MODE'} == 1)
	{
		my @externalfiles = ();
		PDLNA::Database::select_db(
			$dbh,
			{
				'query' => 'SELECT ID FROM FILES WHERE EXTERNAL = 1',
				'parameters' => [ ],
			},
			\@externalfiles,
		);

		foreach my $externalfile (@externalfiles)
		{
			delete_all_by_itemid($dbh, $externalfile->{ID});
		}
	}

	foreach my $directory (@{$CONFIG{'DIRECTORIES'}})
	{
		# delete excluded directories and their items
		foreach my $excl_directory (@{$$directory{'exclude_dirs'}})
		{
			my @directories = ();
			PDLNA::Database::select_db(
				$dbh,
				{
					'query' => 'SELECT ID FROM DIRECTORIES WHERE NAME = ? AND PATH LIKE ?',
					'parameters' => [ $excl_directory, $directory->{'path'}.'%', ],
				},
				\@directories,
			);

			foreach my $dir (@directories)
			{
				delete_subitems_recursively($dbh, $dir->{ID});
			}
		}

		# delete excluded items
		foreach my $excl_items (@{$$directory{'exclude_items'}})
		{
			my @items = ();
			PDLNA::Database::select_db(
				$dbh,
				{
					'query' => 'SELECT ID FROM FILES WHERE (NAME = ? AND PATH LIKE ?) OR (FULLNAME = ?)',
					'parameters' => [ $excl_items, $directory->{'path'}.'%', $directory->{'path'}.$excl_items, ],
				},
				\@items,
			);

			foreach my $item (@items)
			{
				delete_all_by_itemid($dbh, $item->{ID});
			}
		}
	}

	# delete directories from database with no subdirectories or subfiles
	@directories = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT ID FROM DIRECTORIES',
			'parameters' => [ ],
		},
		\@directories,
	);
	foreach my $dir (@directories)
	{
		my $amount = get_amount_elements_by_id($dbh, $dir->{ID});
		if ($amount == 0)
		{
			delete_subitems_recursively($dbh, $dir->{ID});
		}
	}
}

sub delete_all_by_itemid
{
	my $dbh = shift;
	my $object_id = shift;

	PDLNA::Database::delete_db(
		$dbh,
		{
			'query' => 'DELETE FROM FILES WHERE ID = ?',
			'parameters' => [ $object_id, ],
		},
	);
	PDLNA::Database::delete_db(
		$dbh,
		{
			'query' => 'DELETE FROM FILEINFO WHERE FILEID_REF = ?',
			'parameters' => [ $object_id, ],
		},
	);
	PDLNA::Database::delete_db(
		$dbh,
			{
			'query' => 'DELETE FROM subtitles WHERE fileid_ref = ?',
			'parameters' => [ $object_id, ],
		},
	);
}

sub delete_subitems_recursively
{
	my $dbh = shift;
	my $object_id = shift;

	my @subfiles = ();
	get_subfiles_by_id($dbh, $object_id, undef, undef, \@subfiles);
	foreach my $file (@subfiles)
	{
		delete_all_by_itemid($dbh, $file->{ID});
	}

	my @subdirs = ();
	get_subdirectories_by_id($dbh, $object_id, undef, undef, \@subdirs);
	foreach my $directory (@subdirs)
	{
		delete_subitems_recursively($dbh, $directory->{ID});
		PDLNA::Database::delete_db(
			$dbh,
			{
				'query' => 'DELETE FROM DIRECTORIES WHERE ID = ?',
				'parameters' => [ $directory->{ID}, ],
			},
		);
	}

	PDLNA::Database::delete_db(
		$dbh,
		{
			'query' => 'DELETE FROM DIRECTORIES WHERE ID = ?',
			'parameters' => [ $object_id, ],
		},
	);
}

sub get_fileinfo
{
	my $dbh = shift;

	PDLNA::Log::log('Started to fetch metadata for media items.', 1, 'library');
	my @results = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT FILEID_REF FROM FILEINFO WHERE VALID = ?',
			'parameters' => [ 0, ],
		},
		\@results,
	);

	my $counter = 0;
	foreach my $id (@results)
	{
		my @file = ();
		PDLNA::Database::select_db(
			$dbh,
			{
				'query' => 'SELECT FULLNAME, TYPE, MIME_TYPE, EXTERNAL FROM FILES WHERE ID = ?',
				'parameters' => [ $id->{FILEID_REF}, ],
			},
			\@file,
		);

		if ($file[0]->{EXTERNAL})
		{
			my %info = ();
			PDLNA::FFmpeg::get_media_info($file[0]->{FULLNAME}, \%info);
			if (defined($info{MIME_TYPE}))
			{
				PDLNA::Database::update_db(
					$dbh,
					{
						'query' => 'UPDATE FILES SET FILE_EXTENSION = ?, MIME_TYPE = ?, TYPE = ? WHERE ID = ?',
						'parameters' => [ $info{FILE_EXTENSION}, $info{MIME_TYPE}, $info{TYPE}, $id->{FILEID_REF}, ],
					},
				);
				$file[0]->{TYPE} = $info{TYPE};
				$file[0]->{MIME_TYPE} = $info{MIME_TYPE};
			}
			else
			{
				PDLNA::Database::update_db(
					$dbh,
					{
						'query' => 'UPDATE FILES SET FILE_EXTENSION = ? WHERE ID = ?',
						'parameters' => [ 'unkn', $id->{FILEID_REF}, ],
					},
				);
			}
		}

		unless (defined($file[0]->{MIME_TYPE}))
		{
			next;
		}

		#
		# FILL METADATA OF IMAGES
		#
		if ($file[0]->{TYPE} eq 'image')
		{
			my ($width, $height) = PDLNA::Media::get_image_fileinfo($file[0]->{FULLNAME});
			PDLNA::Database::update_db(
				$dbh,
				{
					'query' => 'UPDATE FILEINFO SET WIDTH = ?, HEIGHT = ?, VALID = ? WHERE FILEID_REF = ?',
					'parameters' => [ $width, $height, 1, $id->{FILEID_REF}, ],
				},
			);
			next;
		}

		if ($CONFIG{'LOW_RESOURCE_MODE'} == 1)
		{
			next;
		}

		#
		# FILL FFmpeg DATA OF VIDEO OR AUDIO FILES
		#
		my %info = ();
		if ($file[0]->{TYPE} eq 'video' || $file[0]->{TYPE} eq 'audio')
		{
			PDLNA::FFmpeg::get_media_info($file[0]->{FULLNAME}, \%info);
			PDLNA::Database::update_db(
				$dbh,
				{
					'query' => 'UPDATE FILEINFO SET WIDTH = ?, HEIGHT = ?, DURATION = ?, BITRATE = ?, CONTAINER = ?, AUDIO_CODEC = ?, VIDEO_CODEC = ? WHERE FILEID_REF = ?',
					'parameters' => [ $info{WIDTH}, $info{HEIGHT}, $info{DURATION}, $info{BITRATE}, $info{CONTAINER}, $info{AUDIO_CODEC}, $info{VIDEO_CODEC}, $id->{FILEID_REF}, ],
				},
			);

			if (defined($info{TYPE}) && defined($info{MIME_TYPE}) && defined($info{FILE_EXTENSION}))
			{
				PDLNA::Database::update_db(
					$dbh,
					{
						'query' => 'UPDATE FILES SET MIME_TYPE = ?, TYPE = ?, FILE_EXTENSION = ? WHERE ID = ?',
						'parameters' => [ $info{MIME_TYPE}, $info{TYPE}, $info{FILE_EXTENSION}, $id->{FILEID_REF}, ],
					},
				);
			}

			if ($file[0]->{TYPE} eq 'video')
			{
				PDLNA::Database::update_db(
					$dbh,
					{
						'query' => 'UPDATE FILEINFO SET VALID = ? WHERE FILEID_REF = ?',
						'parameters' => [ 1, $id->{FILEID_REF}, ],
					},
				);
			}
		}

		#
		# FILL METADATA OF AUDIO FILES
		#
		if ($file[0]->{TYPE} eq 'audio' && defined($info{AUDIO_CODEC}))
		{
			my %audioinfo = (
				'ARTIST' => '',
				'ALBUM' => '',
				'TRACKNUM' => '',
				'TITLE' => '',
				'GENRE' => '',
				'YEAR' => '',
			);
			PDLNA::Media::get_audio_fileinfo($file[0]->{FULLNAME}, $info{AUDIO_CODEC}, \%audioinfo);

			PDLNA::Database::update_db(
				$dbh,
				{
					'query' => 'UPDATE FILEINFO SET ARTIST = ?, ALBUM = ?, TITLE = ?, GENRE = ?, YEAR = ?, TRACKNUM = ?, VALID = ? WHERE FILEID_REF = ?',
					'parameters' => [ $audioinfo{ARTIST}, $audioinfo{ALBUM}, $audioinfo{TITLE}, $audioinfo{GENRE}, $audioinfo{YEAR}, $audioinfo{TRACKNUM}, 1, $id->{FILEID_REF}, ],
				},
			);
		}

		$counter++;
		unless ($counter % 50) # after 50 files, we are doing a commit
		{
			$dbh->commit();
		}
	}
}

sub get_subdirectories_by_id
{
	my $dbh = shift;
	my $object_id = shift;
	my $starting_index = shift;
	my $requested_count = shift;
	my $directory_elements = shift;

	my $sql_query = 'SELECT ID, NAME, PATH FROM DIRECTORIES WHERE ';
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

	$sql_query .= ' ORDER BY NAME';

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

sub get_directory_type_by_id
{
	my $dbh = shift;
	my $object_id = shift;

	my @results = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT TYPE FROM DIRECTORIES WHERE ID = ?',
			'parameters' => [ $object_id, ],
		},
	);

	return $results[0]->{TYPE};
}

sub get_subfiles_by_id
{
	my $dbh = shift;
	my $object_id = shift;
	my $starting_index = shift;
	my $requested_count = shift;
	my $file_elements = shift;

	my $sql_query = 'SELECT ID, NAME, SIZE, DATE FROM FILES WHERE ';
	my @sql_param = ();

	if ($object_id == 0)
	{
		$sql_query .= 'ROOT = 1';
	}
	else
	{
		$sql_query .= 'PATH IN ( SELECT PATH FROM DIRECTORIES WHERE ID = ? )';
		push(@sql_param, $object_id);
	}

	$sql_query .= ' ORDER BY SEQUENCE, NAME';

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
	my @sql_param = ( $object_id, );
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => $sql_query,
			'parameters' => \@sql_param,
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
	$item_parent[0]->{ID} = 0 if !defined($item_parent[0]->{ID});

	return $item_parent[0]->{ID};
}




























#
# HELPER FUNCTIONS
#

#
# NEW: returns array with subtitle items based on their ref_id
#
sub get_subtitles_by_refid
{
	my $dbh = shift;
	my $ref_id = shift;

	my @subtitles = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT id, media_type, fullname, file_extension FROM items WHERE item_type = ? AND ref_id = ?',
			'parameters' => [ 2, $ref_id, ],
		},
		\@subtitles,
	);
	return @subtitles;
}

#
# NEW: fills array reference with items based on their parent_id and their item_type
#
sub get_items_by_parentid
{
	my $dbh = shift;
	my $item_id = shift;
	my $starting_index = shift;
	my $requested_count = shift;
	my $item_type = shift;
	my $elements = shift;

	my $sql_query = 'SELECT id, fullname, title, size, date FROM items WHERE parent_id = ? AND item_type = ? ORDER BY title';
	if (defined($starting_index) && defined($requested_count))
	{
		$sql_query .= ' LIMIT '.$starting_index.', '.$requested_count;
	}

	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => $sql_query,
			'parameters' => [ $item_id, $item_type, ]
		},
		$elements,
	);
}

#
# NEW: returns specified DB columns of an item based on its id
#
sub get_item_by_id
{
	my $dbh = shift;
	my $item_id = shift;
	my $dbfields = shift;

	my @items = ();

	# SANITY CHECK - otherwise we are VULNERABLE to SQL Injections (if somebody is able to manipulate dbfields values)
	foreach my $dbfield (@{$dbfields})
	{
		unless ($dbfield =~ /^(parent_id|item_type|media_type|mime_type|fullname|title|file_extension|date|size|width|height|duration)$/)
		{
			PDLNA::Log::log('ERROR: Parameter '.$dbfield.' as DB column is NOT valid. Possible SQL Injection attempt.', 0, 'default');
			return @items;
		}
	}

	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT '.join(', ', @{$dbfields}).' FROM items WHERE id = ?',
			'parameters' => [ $item_id ],
		},
		\@items,
	);

	return @items;
}

#
# NEW: returns amount and total_size of items based on their (parent_id|item_type|media_type)
#
sub get_amount_size_items_by
{
	my $dbh = shift;
	my $dbfield = shift;
	my $dbvalue = shift;

	# SANITY CHECK - otherwise we are VULNERABLE to SQL Injections (if somebody is able to manipulate dbfields values)
	unless ($dbfield =~ /^(parent_id|item_type|media_type)$/)
	{
		PDLNA::Log::log('ERROR: Parameter '.$dbfield.' as DB column is NOT valid. Possible SQL Injection attempt.', 0, 'default');
		return (0,0);
	}

	my @result = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT COUNT(id) AS amount, SUM(size) as size FROM items WHERE '.$dbfield.' = ?',
			'parameters' => [ $dbvalue, ],
		},
		\@result,
	);

	my ($amount, $size) = 0;
	$amount = $result[0]->{amount} if $result[0]->{amount};
	$size = $result[0]->{size} if $result[0]->{size};
	return ($amount, $size);
}

#
# NEW: returns amount of items based on their parent_id and item_type
#
sub get_amount_items_by_parentid_n_itemtype
{
	my $dbh = shift;
	my $parent_id = shift;
	my $item_type = shift;

	my @result = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT COUNT(id) AS amount FROM items WHERE parent_id = ? AND item_type = ?',
			'parameters' => [ $parent_id, $item_type, ],
		},
		\@result,
	);

	return $result[0]->{amount} || 0;
}

#
# NEW: returns total duration of items
#
sub get_duration_items
{
	my $dbh = shift;

	my $duration = PDLNA::Database::select_db_field_int(
		$dbh,
		{
			'query' => 'SELECT SUM(duration) FROM items',
			'parameters' => [ ],
		},
	);

	return $duration;
}

#
# NEW: returns the parent_id of an item by id
#
sub get_parentid_by_id
{
	my $dbh = shift;
	my $item_id = shift;

	my $parent_id = PDLNA::Database::select_db_field_int(
		$dbh,
		{
			'query' => 'SELECT parent_id FROM items WHERE id = ?',
			'parameters' => [ $item_id, ],
		},
	);
	return $parent_id;
}

#
# NEW: return true if an item_id is under a parent_id
#
sub is_itemid_under_parentid
{
	my $dbh = shift;
	my $parent_id = shift;
	my $item_id = shift;

	while ($item_id != 0)
	{
		return 1 if $parent_id eq $item_id;
		$item_id = get_parentid_by_id($dbh, $item_id);
	}

	return 0;
}

#
# HELPER FUNCTIONS END
#

#
# INTERNAL HELPER FUNCTIONS
#

sub _process_directory
{
	my $dbh = shift;
	my $params = shift;
	$$params{'fullname'} = PDLNA::Utils::delete_trailing_slash($$params{'fullname'});

	my $directory_id = _add_directory_item($dbh, $params);
	$dbh->commit();

	$$params{'fullname'} = PDLNA::Utils::escape_brackets($$params{'fullname'});
	PDLNA::Log::log('Globbing directory: '.PDLNA::Utils::create_filesystem_path([ $$params{'fullname'}, '*', ]).'.', 2, 'library');
	my @items = bsd_glob(PDLNA::Utils::create_filesystem_path([ $$params{'fullname'}, '*', ]));
	foreach my $item (sort @items)
	{
		my $item_basename = basename($item);
		if (-d $item && $item =~ /lost\+found$/)
		{
			PDLNA::Log::log('Skipping '.$item.' directory.', 2, 'library');
		}
		elsif (-d $item && $$params{'recursion'} eq 'yes' && !grep(/^\Q$item_basename\E$/, @{$$params{'exclude_dirs'}}))
		{
			PDLNA::Log::log('Processing directory '.$item.'.', 2, 'library');

			$$params{'parent_id'} = $directory_id;
			$$params{'fullname'} = $item;
			_process_directory($dbh, $params);
		}
		elsif (-f $item && !grep(/^\Q$item_basename\E$/, @{$$params{'exclude_items'}}))
		{
			my $mime_type = mimetype($item);
			PDLNA::Log::log('Processing '.$item.' with MimeType '.$mime_type.'.', 2, 'library');

			if (PDLNA::Media::is_supported_mimetype($mime_type))
			{
				my $media_type = PDLNA::Media::return_type_by_mimetype($mime_type);
				if ($media_type && ($media_type eq $$params{'media_type'} || $$params{'media_type'} eq 'all'))
				{
					PDLNA::Log::log('Adding '.$media_type.' item '.$item.'.', 2, 'library');

					my $item_id = _add_media_item(
						$dbh,
						{
							'fullname' => $item,
							'parent_id' => $directory_id,
							'item_type' => 1,
							'mime_type' => $mime_type,
							'media_type' => $media_type,
						},
					);

					# subtitles for video files
					if ($media_type eq 'video')
					{
						my $tmp = $1 if $item =~ /^(.+)\.\w{3,4}$/;
						foreach my $extension ('srt')
						{
							if (-f $tmp.'.'.$extension)
							{
								my $subtitle_mimetype = mimetype($tmp.'.'.$extension);
								if (PDLNA::Media::is_supported_subtitle($subtitle_mimetype))
								{
									my $subtitle_id = _add_media_item(
										$dbh,
										{
											'fullname' => $tmp.'.'.$extension,
											'parent_id' => $directory_id,
											'ref_id' => $item_id,
											'item_type' => 2,
											'mime_type' => $subtitle_mimetype,
											'media_type' => $extension,
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
				PDLNA::Log::log('Adding playlist '.$item.' as directory.', 2, 'library');
				# TODO playlists
			}
			else
			{
				PDLNA::Log::log('Item '.$item.' skipped. Unsupported MimeType '.$mime_type.'.', 2, 'library');
			}
		}
		else
		{
			PDLNA::Log::log('Item '.$item.' skipped. Inlcuded in ExcludeList.', 2, 'library');
		}
	}
}

sub _add_media_item
{
	my $dbh = shift;
	my $params = shift;

	# gather size and date for item
	my @fileinfo = stat($$params{'fullname'});
	my $file_extension = $1 if $$params{'fullname'} =~ /(\w{3,4})$/;

	# select from database
	my @results = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT id, size, date FROM items WHERE fullname = ?',
			'parameters' => [ $$params{'fullname'}, ],
		},
		\@results,
	);

	if (defined($results[0]->{id})) # check if item is already in db
	{
		if ($results[0]->{size} != $fileinfo[7] || $results[0]->{date} != $fileinfo[9]) # item has changed
		{
			# TODO - CHECK IF I'M WORKING
			PDLNA::Database::update_db(
				$dbh,
				{
					'query' => 'UPDATE items SET media_attributes = ?, size = ?, date = ? WHERE id = ?',
					'parameters' => [ 0, $fileinfo[7], $fileinfo[9], $results[0]->{id}, ],
				},
			);
			PDLNA::Log::log('Updated media item '.$$params{'fullname'}.' in ContentLibrary.', 2, 'library');
		}
		else # item has not changed
		{
			PDLNA::Log::log('No need to update media item '.$$params{'fullname'}.' in ContentLibrary.', 3, 'library');
		}
	}
	else # item not in database
	{
		# add item to database
		PDLNA::Database::insert_db(
			$dbh,
			{
				'query' => 'INSERT INTO items (parent_id, ref_id, item_type, media_type, mime_type, fullname, title, size, date, file_extension) VALUES (?,?,?,?,?,?,?,?,?,?)',
				'parameters' => [ $$params{'parent_id'}, $$params{'ref_id'}, $$params{'item_type'}, $$params{'media_type'}, $$params{'mime_type'}, $$params{'fullname'}, basename($$params{'fullname'}), $fileinfo[7], $fileinfo[9], $file_extension, ],
			},
		);
		PDLNA::Log::log('Added media item '.$$params{'fullname'}.' to ContentLibrary.', 2, 'library');
	}

	return _get_itemid_by_fullname($dbh, $$params{'fullname'});
}

sub _add_directory_item
{
	my $dbh = shift;
	my $params = shift;

	unless (_get_itemid_by_fullname($dbh, $$params{'fullname'})) # check if item is already in db
	{
		# add directory to database
		PDLNA::Database::insert_db(
			$dbh,
			{
				'query' => 'INSERT INTO items (parent_id, fullname, title) VALUES (?,?,?)',
				'parameters' => [ $$params{'parent_id'}, $$params{'fullname'}, basename($$params{'fullname'}), ],
			},
		);
		PDLNA::Log::log('Added directory item '.$$params{'fullname'}.' to ContentLibrary.', 2, 'library');
	}

	return _get_itemid_by_fullname($dbh, $$params{'fullname'});
}

sub _delete_item_by_id
{
	my $dbh = shift;
	my $item_id = shift;

	PDLNA::Database::delete_db(
		$dbh,
		{
			'query' => 'DELETE FROM items WHERE id = ?',
			'parameters' => [ $item_id, ],
		},
	);
}

sub _get_itemid_by_fullname
{
	my $dbh = shift;
	my $fullname = shift;

	my @results = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT id FROM items WHERE fullname = ?',
			'parameters' => [ $fullname, ],
		},
		\@results,
	);

	return $results[0]->{id} if defined($results[0]->{id});
	return undef;
}

sub _cleanup_contentlibrary
{
	my $dbh = shift;

	PDLNA::Log::log('Started to clean up ContentLibrary.', 1, 'library');

	#
	# delete items, which aren't present any more (if any)
	#
	my @items = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT id, fullname, item_type FROM items',
			'parameters' => [ ],
		},
		\@items,
	);
	foreach my $item (@items)
	{
		if ($item->{item_type} == 0) # directory
		{
			unless (-d $item->{fullname})
			{
				_delete_item_by_id($dbh, $item->{id});
			}
		}
		elsif ($item->{item_type} == 1) # file (audio, video, image)
		{
			unless (-f $item->{fullname})
			{
				_delete_item_by_id($dbh, $item->{id});
			}
		}
		elsif ($item->{item_type} == 2) # subtitles
		{
			unless (-f $item->{fullname})
			{
				_delete_item_by_id($dbh, $item->{id});
			}
		}
	}

	#
	# delete directory items, which aren't configured any more (if any)
	#
	@items = ();
	get_items_by_parentid($dbh, 0, undef, undef, 0, \@items);

	my @conf_directories = ();
	foreach my $directory (@{$CONFIG{'DIRECTORIES'}})
	{
		push(@conf_directories, $directory->{'path'});
	}

	foreach my $item (@items)
	{
		unless (grep(/^$item->{fullname}$/, @conf_directories))
		{
			# TODO subitems
			_delete_item_by_id($dbh, $item->{id});
		}
	}

	#
	# delete external items, if LOW_RESOURCE_MODE is enabled (if any)
	#
	if ($CONFIG{'LOW_RESOURCE_MODE'} == 1)
	{
	}

	#
	# delete external items, which aren't configured any more (if any)
	#

	#
	# delete items, which are excluded (if any)
	#
	foreach my $directory (@{$CONFIG{'DIRECTORIES'}})
	{
		my $directory_id = _get_itemid_by_fullname($dbh, $directory->{'path'});
		if (defined($directory_id))
		{
			foreach my $excl_directory (@{$$directory{'exclude_dirs'}})
			{
				@items = ();
				PDLNA::Database::select_db(
					$dbh,
					{
						'query' => 'SELECT id, title FROM items WHERE title = ? AND item_type = ?',
						'parameters' => [ $excl_directory, 0, ],
					},
					\@items,
				);

				foreach my $item (@items)
				{
					if (is_itemid_under_parentid($dbh, $directory_id, $item->{id}))
					{
						# TODO subitems
						_delete_item_by_id($dbh, $item->{id});
					}
				}
			}

			# TODO media items
			foreach my $excl_item (@{$$directory{'exclude_items'}})
			{
			}
		}
	}

	#
	# delete directory items, which don't have any subitems (if any)
	#
	@items = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT id, fullname FROM items WHERE item_type = ?',
			'parameters' => [ 0, ],
		},
		\@items,
	);

	foreach my $item (@items)
	{
		my ($amount, undef) = get_amount_size_items_by($dbh, 'parent_id', $item->{id});
		if ($amount == 0)
		{
			_delete_item_by_id($dbh, $item->{id});
		}
	}
}


sub _fetch_media_attributes
{
	my $dbh = shift;

	PDLNA::Log::log('Started to fetch attributes for media items.', 1, 'library');

	my @items = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT id, media_type, fullname FROM items WHERE media_attributes = ? AND item_type = ?',
			'parameters' => [ 0, 1, ],
		},
		\@items,
	);

	my $counter = 0;
	foreach my $item (@items)
	{
		#
		# FILL METADATA OF IMAGES
		#
		if ($item->{media_type} eq 'image')
		{
			my ($width, $height) = PDLNA::Media::get_image_fileinfo($item->{fullname});
			PDLNA::Database::update_db(
				$dbh,
				{
					'query' => 'UPDATE items SET width = ?, height = ?, media_attributes = ? WHERE id = ?',
					'parameters' => [ $width, $height, 1, $item->{id}, ],
				},
			);
			next;
		}

		#
		# IN LOW_RESOURCE_MODE WE ARE NOT GOING TO OPEN EVERY SINGLE FILE
		#
		if ($CONFIG{'LOW_RESOURCE_MODE'} == 1)
		{
			next;
		}

		#
		# FILL FFmpeg DATA OF VIDEO OR AUDIO FILES
		#
		if ($item->{media_type} eq 'video' || $item->{media_type} eq 'audio')
		{
			my %info = ();
			PDLNA::FFmpeg::get_media_info($item->{fullname}, \%info);
			PDLNA::Database::update_db(
				$dbh,
				{
					'query' => 'UPDATE items SET width = ?, height = ?, duration = ?, media_attributes = ? WHERE id = ?',
					'parameters' => [ $info{WIDTH}, $info{HEIGHT}, $info{DURATION}, 1, $item->{id}, ],
				},
			);
		}

		$counter++;
		unless ($counter % 50) # after 50 files, we are doing a commit
		{
			$dbh->commit();
		}
	}
}

#
# INTERNAL HELPER FUNCTIONS END
#

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
