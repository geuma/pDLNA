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

		my $i = 0;
		foreach my $external (@{$CONFIG{'EXTERNALS'}})
		{
			add_file_to_db(
				$dbh,
				{
					'element' => $external->{'command'} || $external->{'streamurl'},
					'media_type' => $external->{'type'},
					'mime_type' => '', # need to determine
					'element_basename' => $external->{'name'},
					'element_dirname' => '', # set the directory to nothing - no parent
					'external' => 1,
					'sequence' => $i,
					'root' => 1,
				},
			);
			$i++;
		}
		$dbh->commit();
		my $timestamp_end = time();

		# add our timestamp when finished
		PDLNA::Database::update_db(
			$dbh,
			{
				'query' => "UPDATE METADATA SET VALUE = ? WHERE PARAM = 'TIMESTAMP'",
				'parameters' => [ $timestamp_end, ],
			},
		);
		$dbh->commit();

		my $duration = $timestamp_end - $timestamp_start;
		PDLNA::Log::log('Indexing configured media directories took '.$duration.' seconds.', 1, 'library');

		my ($amount, $size) = get_amount_size_of_items($dbh);
		PDLNA::Log::log('Configured media directories include '.$amount.' with '.PDLNA::Utils::convert_bytes($size).' of size.', 1, 'library');

		cleanup_contentlibrary($dbh);
		$dbh->commit();

		$timestamp_start = time();
		get_fileinfo($dbh);
		$dbh->commit();
		$timestamp_end = time();
		$duration = $timestamp_end - $timestamp_start;
		PDLNA::Log::log('Getting FFmpeg information for indexed media files '.$duration.' seconds.', 1, 'library');

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
					unless (grep(/^$result->{NAME}$/, @items) || grep(/^$result->{FULLNAME}$/, @items))
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
			'query' => 'SELECT ID, DATE, SIZE FROM SUBTITLES WHERE FULLNAME = ? AND FILEID_REF = ? AND MIME_TYPE = ?',
			'parameters' => [ $$params{'path'}, $$params{'file_id'}, $$params{'mimetype'}, ],
		},
		\@results,
	);

	my @fileinfo = stat($$params{'path'});

	if (defined($results[0]->{ID}))
	{
		if ($results[0]->{SIZE} != $fileinfo[7] || $results[0]->{DATE} != $fileinfo[9])
		{
			# update the datbase entry (something changed)
			PDLNA::Database::update_db(
				$dbh,
				{
					'query' => 'UPDATE SUBTITLES SET DATE = ?, SIZE = ? WHERE ID = ?;',
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
				'query' => 'INSERT INTO SUBTITLES (FILEID_REF, FULLNAME, NAME, TYPE, MIME_TYPE, DATE, SIZE) VALUES (?,?,?,?,?,?,?)',
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
			'query' => 'SELECT ID, FULLNAME FROM SUBTITLES',
			'parameters' => [ ],
		},
		\@subtitles,
	);
	foreach my $subtitle (@subtitles)
	{
		unless (-f $subtitle->{FULLNAME})
		{
			PDLNA::Database::delete_db(
				$dbh,
				{
					'query' => 'DELETE FROM SUBTITLES WHERE ID = ?',
					'parameters' => [ $subtitle->{ID}, ],
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
			'query' => 'DELETE FROM SUBTITLES WHERE FILEID_REF = ?',
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

sub is_in_same_directory_tree
{
	my $dbh = shift;
	my $parent_id = shift;
	my $child_id = shift;

	while ($child_id != 0)
	{
		return 1 if $parent_id eq $child_id;
		$child_id = get_parent_of_directory_by_id($dbh, $child_id);
	}

	return 0;
}

sub get_amount_size_of_items
{
	my $dbh = shift;
	my $type = shift || undef;

	my $sql_query = 'SELECT COUNT(ID) AS AMOUNT, SUM(SIZE) AS SIZE FROM FILES';
	my @sql_param = ();
	if (defined($type))
	{
		$sql_query .= ' WHERE TYPE = ? GROUP BY TYPE';
		push(@sql_param, $type);
	}

	my @result = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => $sql_query,
			'parameters' => \@sql_param,
		},
		\@result,
	);
	return ($result[0]->{AMOUNT}, $result[0]->{SIZE});
}

sub get_amount_directories
{
	my $dbh = shift;

	my @result = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT COUNT(ID) AS AMOUNT FROM DIRECTORIES',
			'parameters' => [ ],
		},
		\@result,
	);
	return $result[0]->{AMOUNT};
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
