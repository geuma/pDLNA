package PDLNA::Database;
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

use PDLNA::Config;
use PDLNA::Log;

sub connect
{
	my $dbh = undef;
	if ($CONFIG{'DB_TYPE'} eq 'SQLITE3')
	{
		$dbh = DBI->connect("dbi:SQLite:dbname=".$CONFIG{'DB_NAME'},"","") || PDLNA::Log::fatal('Cannot connect: '.$DBI::errstr);
	}
	return $dbh;
}

sub disconnect
{
	my $dbh = shift;
	$dbh->disconnect();
}

sub initialize_db
{
	my $dbh = PDLNA::Database::connect();

	if (grep(/^"METADATA"$/, $dbh->tables()))
	{
		my @results = ();
		select_db(
			$dbh,
			{
				'query' => 'SELECT VALUE FROM METADATA WHERE KEY = ?',
				'parameters' => [ 'VERSION', ],
			},
			\@results,
		);

		# check if DB was build with a different version of pDLNA
		if ($results[0]->{VALUE} ne PDLNA::Config::print_version())
		{
			$dbh->do('DELETE FROM METADATA;');

			insert_db(
				$dbh,
				{
					'query' => 'INSERT INTO METADATA (KEY, VALUE) VALUES (?,?)',
					'parameters' => [ 'VERSION', PDLNA::Config::print_version(), ],
				},
			);
			insert_db(
				$dbh,
				{
					'query' => 'INSERT INTO METADATA (KEY, VALUE) VALUES (?,?)',
					'parameters' => [ 'TIMESTAMP', time(), ],
				},
			);

			$dbh->do('DROP TABLE FILES;');
			$dbh->do('DROP TABLE FILEINFO;');
			$dbh->do('DROP TABLE DIRECTORIES;');
		}
	}
	else
	{
		$dbh->do('CREATE TABLE METADATA (
				KEY					VARCHAR(128) PRIMARY KEY,
				VALUE				VARCHAR(128)
			);'
		);

		insert_db(
			$dbh,
			{
				'query' => 'INSERT INTO METADATA (KEY, VALUE) VALUES (?,?)',
				'parameters' => [ 'VERSION', PDLNA::Config::print_version(), ],
			},
		);
		insert_db(
			$dbh,
			{
				'query' => 'INSERT INTO METADATA (KEY, VALUE) VALUES (?,?)',
				'parameters' => [ 'TIMESTAMP', time(), ],
			},
		);
	}

	unless (grep(/^"FILES"$/, $dbh->tables()))
	{
		$dbh->do("CREATE TABLE FILES (
				ID					INTEGER PRIMARY KEY AUTOINCREMENT,

				NAME				VARCHAR(2048),
				PATH				VARCHAR(2048),
				FULLNAME			VARCHAR(2048),
				FILE_EXTENSION		VARCHAR(4),

				DATE				BIGINT,
				SIZE				BIGINT,

				MIME_TYPE			VARCHAR(128),
				TYPE				VARCHAR(12),
				EXTERNAL			BOOLEAN
			);"
		);
	}

	unless (grep(/^"FILEINFO"$/, $dbh->tables()))
	{
		$dbh->do("CREATE TABLE FILEINFO (
				ID_REF				INTEGER PRIMARY KEY,
				VALID				BOOLEAN,

				WIDTH				INTEGER,
				HEIGHT				INTEGER,

				DURATION			INTEGER,
				BITRATE				INTEGER,
				VBR					BOOLEAN,

				CONTAINER			VARCHAR(128),
				AUDIO_CODEC			VARCHAR(128),
				VIDEO_CODEC			VARCHAR(128),

				ARTIST				VARCHAR(128),
				ALBUM				VARCHAR(128),
				TITLE				VARCHAR(128),
				GENRE				VARCHAR(128),
				YEAR				VARCHAR(4),
				TRACKNUM			INTEGER
			);"
		);
	}

	#
	# TABLE DESCRIPTION
	#
	# TYPE
	# 	0		directory
	# 	1		playlist
	unless (grep(/^"DIRECTORIES"$/, $dbh->tables()))
	{
		$dbh->do("CREATE TABLE DIRECTORIES (
				ID					INTEGER PRIMARY KEY AUTOINCREMENT,

				NAME				VARCHAR(2048),
				PATH				VARCHAR(2048),
				DIRNAME				VARCHAR(2048),

				ROOT				BOOLEAN,
				TYPE				INTEGER
			);"
		);
	}
	PDLNA::Database::disconnect($dbh);
}

sub select_db
{
	my $dbh = shift;
	my $params = shift;
	my $result = shift;

	#PDLNA::Log::log($$params{'query'}.' - '.join(', ', @{$$params{'parameters'}}), 1, 'database');
	my $sth = $dbh->prepare($$params{'query'});
	$sth->execute(@{$$params{'parameters'}});
	while (my $data = $sth->fetchrow_hashref)
	{
		push(@{$result}, $data);
	}
}

sub insert_db
{
	my $dbh = shift;
	my $params = shift;

	PDLNA::Log::log('INSERT:'.$$params{'query'}.' - '.join(', ', @{$$params{'parameters'}}), 1, 'database');
	my $sth = $dbh->prepare($$params{'query'});
	$sth->execute(@{$$params{'parameters'}}) or die $sth->errstr;
}

sub update_db
{
	my $dbh = shift;
	my $params = shift;

	my $sth = $dbh->prepare($$params{'query'});
	$sth->execute(@{$$params{'parameters'}});
}

sub delete_db
{
	my $dbh = shift;
	my $params = shift;

	my $sth = $dbh->prepare($$params{'query'});
	$sth->execute(@{$$params{'parameters'}});
}

1;

__END__





sub new
{
	my $class = shift;
	my $self = ();

	if ($CONFIG{'DB_TYPE'} eq 'SQLITE3')
	{
		$self->{DBH} = DBI->connect("dbi:SQLite:dbname=".$CONFIG{'DB_NAME'},"","") || PDLNA::Log::fatal('Cannot connect: '.$DBI::errstr);
	}

	if (grep(/^"METADATA"$/, $self->{DBH}->tables()))
	{
		my $sth = $self->{DBH}->prepare('SELECT VALUE FROM METADATA WHERE KEY = ?');
		$sth->execute('VERSION');
		my $data = $sth->fetchrow_hashref();

		# check if DB was build with a different version of pDLNA
		if ($data->{VALUE} ne PDLNA::Config::print_version())
		{
			$self->{DBH}->do('DELETE FROM METADATA;');
			$self->{DBH}->do("INSERT INTO METADATA (KEY, VALUE) VALUES ('VERSION', '".PDLNA::Config::print_version()."');");
			$self->{DBH}->do("INSERT INTO METADATA (KEY, VALUE) VALUES ('TIMESTAMP', '".time()."');");

			$self->{DBH}->do('DROP TABLE FILES;');
#			$self->{DBH}->do('DROP TABLE FILEINFO;');
			$self->{DBH}->do('DROP TABLE DIRECTORIES;');
		}
	}
	else
	{
		$self->{DBH}->do('CREATE TABLE METADATA (
				KEY					VARCHAR(128) PRIMARY KEY,
				VALUE				VARCHAR(128)
			);'
		);

		$self->{DBH}->do("INSERT INTO METADATA (KEY, VALUE) VALUES ('VERSION', '".PDLNA::Config::print_version()."');");
		$self->{DBH}->do("INSERT INTO METADATA (KEY, VALUE) VALUES ('TIMESTAMP', '".time()."');");
	}

	unless (grep(/^"FILES"$/, $self->{DBH}->tables()))
	{
		$self->{DBH}->do("CREATE TABLE FILES (
				ID					INTEGER PRIMARY KEY AUTOINCREMENT,

				NAME                VARCHAR(2048),
				PATH                VARCHAR(2048),
				FULLNAME			VARCHAR(2048),
				FILE_EXTENSION      VARCHAR(4),

				DATE                BIGINT,
				SIZE                BIGINT,

				MIME_TYPE           VARCHAR(128),
				TYPE                VARCHAR(12)
			);"
		);
	}

	# TODO low resource mode
	unless (grep(/^"FILEINFO"$/, $self->{DBH}->tables()))
	{
	}

	unless (grep(/^"DIRECTORIES"$/, $self->{DBH}->tables()))
	{
		$self->{DBH}->do("CREATE TABLE DIRECTORIES (
				ID					INTEGER PRIMARY KEY AUTOINCREMENT,

				NAME				VARCHAR(2048),
				PATH				VARCHAR(2048),
				DIRNAME				VARCHAR(2048),

				ROOT				BOOLEAN
			);"
		);
	}

	bless($self, $class);
	return $self;
}

sub index_directories
{
	my $self = shift;

	my $timestamp_start = time();
	foreach my $directory (@{$CONFIG{'DIRECTORIES'}}) # we are not able to run this part in threads - since glob seems to be NOT thread safe
	{
		$self->process_directory(
			{
				'path' => $directory->{'path'},
				'type' => $directory->{'type'},
				'recursion' => $directory->{'recursion'},
				'exclude_dirs' => $directory->{'exclude_dirs'},
				'exclude_items' => $directory->{'exclude_items'},
				'rootdir' => 1,
			},
		);
#		'allow_playlists' => $directory->{'allow_playlists'},
	}
	my $timestamp_end = time();

	# add our timestamp when finished
	$self->update_db(
		{
			'query' => "UPDATE METADATA SET VALUE = ? WHERE KEY = 'TIMESTAMP'",
			'parameters' => [ $timestamp_end, ],
		},
	);

	my $duration = $timestamp_end - $timestamp_start;
	PDLNA::Log::log('Indexing configured media directories took '.$duration.' seconds.', 1, 'library');

	my @results = ();
	$self->select_db(
		{
			'query' => 'SELECT COUNT(*) AS AMOUNT, SUM(SIZE) AS SIZE FROM FILES;',
			'parameters' => [ ],
		},
		\@results,
	);
	PDLNA::Log::log('Configured media directories include '.$results[0]->{AMOUNT}.' with '.PDLNA::Utils::convert_bytes($results[0]->{SIZE}).' of size.', 1, 'library');
}

sub process_directory
{
	my $self = shift;
	my $params = shift;
	$$params{'path'} =~ s/\/$//;

	# check if directoriy is in db
	my @results = ();
	$self->select_db(
		{
			'query' => 'SELECT ID FROM DIRECTORIES WHERE PATH = ?',
			'parameters' => [ $$params{'path'}, ],
		},
		\@results,
	);

	unless (defined($results[0]->{ID}))
	{
		# add directory to database
		$self->insert_db(
			{
				'query' => 'INSERT INTO DIRECTORIES (NAME, PATH, DIRNAME, ROOT) VALUES (?,?,?,?)',
				'parameters' => [ basename($$params{'path'}), $$params{'path'}, dirname($$params{'path'}), $$params{'rootdir'} ],
			},
		);
	}

	my @elements = bsd_glob($$params{'path'}.'/*');
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

			$self->process_directory(
				{
					'path' => $element,
					'type' => $$params{'type'},
					'recursion' => $$params{'recursion'},
					'exclude_dirs' => $$params{'exclude_dirs'},
					'exclude_items' => $$params{'exclude_items'},
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

					my $element_dirname = dirname($element);
					my @fileinfo = stat($element);
					my $file_extension = $1 if $element =~ /(\w{3,4})$/;

					# check if file is in db
					my @results = ();
					$self->select_db(
						{
							'query' => 'SELECT ID, DATE, SIZE, MIME_TYPE FROM FILES WHERE FULLNAME = ?',
							'parameters' => [ $element, ],
						},
						\@results,
					);

					if (defined($results[0]->{ID}))
					{
						if ($results[0]->{SIZE} != $fileinfo[7] || $results[0]->{DATE} != $fileinfo[9] || $results[0]->{MIME_TYPE} ne $mime_type)
						{
							# update the datbase entry (something changed)
							$self->update_db(
								{
									'query' => 'UPDATE FILES SET DATE = ?, SIZE = ?, MIME_TYPE = ?, TYPE = ? WHERE ID = ?;',
									'parameters' => [ $fileinfo[9], $fileinfo[7], $mime_type, $media_type, $results[0]->{ID}, ],
								},
							);

							# TODO delete FILEINFO entry
						}
					}
					else
					{
						# insert file to db
						$self->insert_db(
							{
								'query' => 'INSERT INTO FILES (NAME, PATH, FULLNAME, FILE_EXTENSION, DATE, SIZE, MIME_TYPE, TYPE) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
								'parameters' => [ $element_basename, $element_dirname, $element, $file_extension, $fileinfo[9], $fileinfo[7], $mime_type, $media_type, ],
							},
						);
					}
				}
			}
		}
		else
		{
			PDLNA::Log::log('Did not process '.$element.'.', 2, 'library');
		}
	}
}

sub select_db
{
	my $self = shift;
	my $params = shift;
	my $result = shift;

#	my $dbh = $self->{DBH}->clone();
#	my $sth = $dbh->prepare($$params{'query'});
	my $sth = $self->{DBH}->prepare($$params{'query'});
	$sth->execute(@{$$params{'parameters'}});
	while (my $data = $sth->fetchrow_hashref)
	{
		push(@{$result}, $data);
	}
}

sub insert_db
{
	my $self = shift;
	my $params = shift;

	my $sth = $self->{DBH}->prepare($$params{'query'});
	$sth->execute(@{$$params{'parameters'}});
}

sub update_db
{
	my $self = shift;
	my $params = shift;

	my $sth = $self->{DBH}->prepare($$params{'query'});
	$sth->execute(@{$$params{'parameters'}});
}

sub timestamp
{
	my $self = shift;

	my @results = ();
	$self->select_db(
		{
			'query' => 'SELECT VALUE FROM METADATA WHERE KEY = ?',
			'parameters' => [ 'TIMESTAMP', ],
		},
		\@results,
	);
	return $results[0]->{VALUE};
}

sub get_direct_childs
{
	my $self = shift;
	my $object_id = shift;
	my $dire_elements = shift;
	my $file_elements = shift;

	if ($object_id == 0)
	{
		my @results = ();
		$self->select_db(
			{
				'query' => 'SELECT ID FROM DIRECTORIES WHERE ROOT = 1',
				'parameters' => [],
			},
			\@results,
		);

		foreach my $result (@results)
		{
			push(@{$dire_elements}, $result->{ID});
		}
	}
	else
	{
#		SELECT DIRECTORIES.PATH FROM DIRECTORIES INNER JOIN FILES ON DIRECTORIES.PATH = FILES.PATH WHERE DIRECTORIES.ID = 147;
	}

	return 0;
}









sub get_directory_name
{
	my $self = shift;
	my $id = shift;

	my @results = ();
	$self->select_db(
		{
			'query' => 'SELECT NAME FROM DIRECTORIES WHERE ID = ?',
			'parameters' => [ $id, ],
		},
		\@results,
	);
	return $results[0]->{ID};
}

sub get_directory_parent
{
	my $self = shift;
	my $id = shift;

	my @results = ();
	$self->select_db(
		{
			'query' => 'SELECT ID FROM DIRECTORIES WHERE PATH IN ( SELECT DIRNAME FROM DIRECTORIES WHERE ID = ?)',
			'parameters' => [ $id, ],
		},
		\@results,
	);
	return $results[0]->{ID} if defined($results[0]->{ID});
	return 0;
}

# TODO ADD FILE AMOUNT
sub get_directory_childamount
{
	my $self = shift;
	my $id = shift;

	if ($id == 0)
	{
		my @results = ();
		$self->select_db(
			{
				'query' => 'SELECT COUNT(ID) AS AMOUNT FROM DIRECTORIES WHERE ROOT = 1',
				'parameters' => [],
			},
			\@results,
		);
		return $results[0]->{AMOUNT};
	}
	else
	{
		my @results = ();
		$self->select_db(
			{
				'query' => 'SELECT COUNT(ID) AS AMOUNT FROM DIRECTORIES WHERE DIRNAME IN ( SELECT PATH FROM DIRECTORIES WHERE ID = ? )',
				'parameters' => [ $id, ],
			},
			\@results,
		);
		return $results[0]->{AMOUNT};
	}
}

















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

sub initializer
{
	my $self = shift;
}







sub is_directory
{
	return 1;
}

sub is_item
{
	return 0;
}

sub directories
{
	my $self = shift;
	return $self->{DIRECTORIES};
}

sub print_object
{
	my $self = shift;

	my $size = 0;
	my $amount = 0;
	my $string = "\n\tObject PDLNA::ContentLibrary\n";
	foreach my $id (sort keys %{$self->{DIRECTORIES}})
	{
		$string .= $self->{DIRECTORIES}->{$id}->print_object("\t\t");

		$size += $self->{DIRECTORIES}->{$id}->size_recursive();
		$amount += $self->{DIRECTORIES}->{$id}->amount_items_recursive();
	}
	$string .= "\t\tTimestamp: ".$self->{TIMESTAMP}." (".time2str($CONFIG{'DATE_FORMAT'}, $self->{TIMESTAMP}).")\n";
	my $duration = $self->{TIMESTAMP_FINISHED} - $self->{TIMESTAMP};
	$string .= "\t\tDuration:  ".$duration." seconds\n";
	$string .= "\t\tItemAmount:".$amount."\n";
	$string .= "\t\tSize:      ".$size." Bytes (".PDLNA::Utils::convert_bytes($size).")\n";
	$string .= "\tObject PDLNA::ContentLibrary END\n";

	return $string;
}

sub get_object_by_id
{
	my $self = shift;
	my $id = shift;

	if ($id =~ /^\d+$/) # if ID is numeric
	{
		return $self->{DIRECTORIES}->{0}->get_object_by_id($id);
	}

	return undef;
}

1;
