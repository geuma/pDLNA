package PDLNA::Database;
#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2015 Stefan Heumader <stefan@heumader.at>
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

my %DBSTRING_AUTOINCREMENT = (
	'SQLITE3' => 'INTEGER PRIMARY KEY AUTOINCREMENT',
	'MYSQL' => 'INTEGER PRIMARY KEY AUTO_INCREMENT',
	'PGSQL' => 'SERIAL PRIMARY KEY',
);

my %DBSTRING_CHARACTERSET = (
	'SQLITE3' => '',
	'MYSQL' => 'DEFAULT CHARACTER SET=utf8',
	'PGSQL' => '',
);

sub connect
{
	my $dsn = undef;
	my %settings = (
		PrintError => 1,
		RaiseError => 1,
	);

	if ($CONFIG{'DB_TYPE'} eq 'SQLITE3')
	{
		$dsn = 'dbi:SQLite:dbname='.$CONFIG{'DB_NAME'};
		$settings{sqlite_unicode} = 1;
	}
	elsif ($CONFIG{'DB_TYPE'} eq 'MYSQL')
	{
		$dsn = 'dbi:mysql:dbname='.$CONFIG{'DB_NAME'}.';host=localhost';
		$settings{mysql_enable_utf8} = 1;
	}
	elsif ($CONFIG{'DB_TYPE'} eq 'PGSQL')
	{
		$dsn = 'dbi:Pg:dbname='.$CONFIG{'DB_NAME'}.';host=localhost';
		$settings{pg_enable_utf8} = 1;
	}

	my $dbh = DBI->connect($dsn, $CONFIG{'DB_USER'}, $CONFIG{'DB_PASS'}, \%settings);
	unless (defined($dbh))
	{
		PDLNA::Log::fatal('Unable to connect to Database: '.$DBI::errstr);
	}

	if ($CONFIG{'DB_TYPE'} eq 'SQLITE3')
	{
		$dbh->do('PRAGMA encoding="UTF-8";');
	}
	elsif ($CONFIG{'DB_TYPE'} eq 'PGSQL')
	{
		$dbh->do('set client_encoding = "utf-8";');
		$dbh->do('set client_encoding = "iso8859-2";'); # a crapy workaround to get our umlaute working for now - setting client encoding to Latin2 # TODO FIX ME
	}

	return $dbh;
}

sub disconnect
{
	my $dbh = shift;
	$dbh->disconnect() || PDLNA::Log::log('ERROR: Unable to disconnect from database: '.$DBI::errstr, 0, 'database');
}

sub initialize_db
{
	my $dbh = PDLNA::Database::connect();

	my @tables = select_db_tables($dbh);
	if (grep(/^metadata$/, @tables))
	{
		my @results = ();
		select_db(
			$dbh,
			{
				'query' => 'SELECT value FROM metadata WHERE param = ?',
				'parameters' => [ 'DBVERSION', ],
				'perfdata' => 0, # disable writing perfdata
			},
			\@results,
		);

		# check if DB was build with a different database version of pDLNA
		if (!defined($results[0]->{value}) || $results[0]->{value} ne $CONFIG{'PROGRAM_DBVERSION'})
		{
			$dbh->do('DELETE FROM metadata;');

			_insert_metadata($dbh, 'DBVERSION', $CONFIG{'PROGRAM_DBVERSION'});
			_insert_metadata($dbh, 'VERSION', PDLNA::Config::print_version());
			_insert_metadata($dbh, 'TIMESTAMP', time());

			$dbh->do('DROP TABLE items;') if grep(/^items$/, @tables);
			$dbh->do('DROP TABLE device_ip;') if grep(/^device_ip$/, @tables);
			$dbh->do('DROP TABLE device_bm;') if grep(/^device_bm$/, @tables);
			$dbh->do('DROP TABLE device_udn;') if grep(/^device_udn$/, @tables);
			$dbh->do('DROP TABLE device_nts;') if grep(/^device_nts$/, @tables);
			$dbh->do('DROP TABLE device_service;') if grep(/^device_service$/, @tables);
			$dbh->do('DROP TABLE stat_mem;') if grep(/^stat_mem$/, @tables);
			$dbh->do('DROP TABLE stat_items;') if grep(/^stat_items$/, @tables);
			$dbh->do('DROP TABLE stat_db;') if grep(/^stat_db$/, @tables);
			@tables = ();
		}
	}
	else
	{
		$dbh->do("CREATE TABLE metadata (
				param				VARCHAR(128) PRIMARY KEY,
				value				VARCHAR(128)
			) $DBSTRING_CHARACTERSET{$CONFIG{'DB_TYPE'}};"
		);

		_insert_metadata($dbh, 'DBVERSION', $CONFIG{'PROGRAM_DBVERSION'});
		_insert_metadata($dbh, 'VERSION', PDLNA::Config::print_version());
		_insert_metadata($dbh, 'TIMESTAMP', time());
	}

	unless (grep(/^items$/, @tables))
	{
		$dbh->do("CREATE TABLE items (
				id					$DBSTRING_AUTOINCREMENT{$CONFIG{'DB_TYPE'}},
				parent_id			INTEGER,
				ref_id				INTEGER,
				media_attributes	INTEGER DEFAULT 0,

				item_type			INTEGER DEFAULT 0,
				media_type			VARCHAR(12),
				mime_type			VARCHAR(128),

				fullname			VARCHAR(2048),
				title				VARCHAR(2048),
				file_extension		VARCHAR(4),

				date				BIGINT,
				size				BIGINT,

				width				INTEGER DEFAULT 0,
				height				INTEGER DEFAULT 0,

				duration			INTEGER DEFAULT 0,
				bitrate				INTEGER DEFAULT 0,
				vbr					INTEGER DEFAULT 0,

				container			VARCHAR(128),
				audio_codec			VARCHAR(128),
				video_codec			VARCHAR(128)
			) $DBSTRING_CHARACTERSET{$CONFIG{'DB_TYPE'}};"
		);

		# CREATE INDEX TO IMPROVE DB PERFORMANCE
		$dbh->do('CREATE INDEX parent_id ON items (parent_id)');
		$dbh->do('CREATE INDEX ref_id ON items (ref_id)');
		$dbh->do('CREATE INDEX item_type ON items (item_type)');
		$dbh->do('CREATE INDEX fullname ON items (fullname)');
		$dbh->do('CREATE INDEX title ON items (title)');
	}
	#
	# item_type VALUES
	#  0 - directory
	#  1 - media item (audio, video, image)
	#  2 - subtitles
	#

	unless (grep(/^device_ip$/, @tables))
	{
		$dbh->do("CREATE TABLE device_ip (
				id					$DBSTRING_AUTOINCREMENT{$CONFIG{'DB_TYPE'}},

				ip					VARCHAR(15),
				user_agent			VARCHAR(128),
				last_seen			BIGINT
			) $DBSTRING_CHARACTERSET{$CONFIG{'DB_TYPE'}};"
		);
	}

	unless (grep(/^device_bm$/, @tables))
	{
		$dbh->do("CREATE TABLE device_bm (
				id					$DBSTRING_AUTOINCREMENT{$CONFIG{'DB_TYPE'}},
				device_ip_ref		INTEGER,

				item_id_ref			INTEGER,
				pos_seconds			INTEGER
			) $DBSTRING_CHARACTERSET{$CONFIG{'DB_TYPE'}};"
		);
	}

	unless (grep(/^device_udn$/, @tables))
	{
		$dbh->do("CREATE TABLE device_udn (
				id					$DBSTRING_AUTOINCREMENT{$CONFIG{'DB_TYPE'}},
				device_ip_ref		INTEGER,

				udn					VARCHAR(64),
				ssdp_banner			VARCHAR(256),
				desc_url			VARCHAR(512),
				rela_url			VARCHAR(512),
				base_url			VARCHAR(512),

				type				VARCHAR(256),
				model_name			VARCHAR(256),
				friendly_name		VARCHAR(256)
			) $DBSTRING_CHARACTERSET{$CONFIG{'DB_TYPE'}};"
		);
	}

	unless (grep(/^device_nts$/, @tables))
	{
		$dbh->do("CREATE TABLE device_nts (
				id					$DBSTRING_AUTOINCREMENT{$CONFIG{'DB_TYPE'}},
				device_udn_ref		INTEGER,

				type				VARCHAR(128),
				expire				BIGINT
			) $DBSTRING_CHARACTERSET{$CONFIG{'DB_TYPE'}};"
		);
	}

	unless (grep(/^device_service$/, @tables))
	{
		$dbh->do("CREATE TABLE device_service (
				id					$DBSTRING_AUTOINCREMENT{$CONFIG{'DB_TYPE'}},
				device_udn_ref		INTEGER,

				service_id			VARCHAR(256),
				type				VARCHAR(256),
				control_url			VARCHAR(512),
				event_url			VARCHAR(512),
				scpd_url			VARCHAR(512)
			) $DBSTRING_CHARACTERSET{$CONFIG{'DB_TYPE'}};"
		);
	}

	unless (grep(/^stat_mem$/, @tables))
	{
		$dbh->do("CREATE TABLE stat_mem (
				date				BIGINT PRIMARY KEY,
				vms					BIGINT,
				rss					BIGINT
			) $DBSTRING_CHARACTERSET{$CONFIG{'DB_TYPE'}};"
		);
	}

	unless (grep(/^stat_items$/, @tables))
	{
		$dbh->do("CREATE TABLE stat_items (
				date				BIGINT PRIMARY KEY,
				audio				INTEGER,
				audio_size			BIGINT,
				video				INTEGER,
				video_size			BIGINT,
				image				INTEGER,
				image_size			BIGINT
			) $DBSTRING_CHARACTERSET{$CONFIG{'DB_TYPE'}};"
		);
	}

	unless (grep(/^stat_db$/, @tables))
	{
		$dbh->do("CREATE TABLE stat_db (
				date				BIGINT,
				query_type			VARCHAR(6),
				query				VARCHAR(512),
				exec_time			INTEGER
			) $DBSTRING_CHARACTERSET{$CONFIG{'DB_TYPE'}};"
		);
	}

	PDLNA::Database::disconnect($dbh);
}

sub select_db_tables
{
	my $dbh = shift;

	my %queries = (
		'SQLITE3' => "SELECT name FROM sqlite_master WHERE type = 'table'",
		'MYSQL' => "SELECT table_name FROM information_schema.tables WHERE table_type = 'base table'",
		'PGSQL' => "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'",
	);

	my @tables = ();
	select_db_array(
		$dbh,
		{
			'query' => $queries{$CONFIG{'DB_TYPE'}},
			'parameters' => [ ],
			'perfdata' => 0, # disable writing perfdata
		},
		\@tables,
	);

	return @tables;
}

sub select_db_array
{
	my $dbh = shift;
	my $params = shift;
	my $result = shift;

	my $perfdata = defined($$params{'perfdata'}) ? 0 : 1;

	my $starttime = PDLNA::Utils::get_timestamp_ms();

	my $sth = $dbh->prepare($$params{'query'}) || PDLNA::Log::log('ERROR: Cannot prepare database query: '.$DBI::errstr, 0, 'database');
	$sth->execute(@{$$params{'parameters'}}) || PDLNA::Log::log('ERROR: Cannot execute database query: '.$DBI::errstr, 0, 'database');
	while (my $data = $sth->fetchrow_array())
	{
		push(@{$result}, $data);
	}
	PDLNA::Log::log('ERROR: Data fetching terminated early by error: '.$DBI::errstr, 0, 'database') if $DBI::err;

	_log_query($dbh, $params, $starttime, $perfdata);
}

sub select_db_field_int
{
	my $dbh = shift;
	my $params = shift;

	my $perfdata = defined($$params{'perfdata'}) ? 0 : 1;

	my $starttime = PDLNA::Utils::get_timestamp_ms();

	my $sth = $dbh->prepare($$params{'query'}) || PDLNA::Log::log('ERROR: Cannot prepare database query: '.$DBI::errstr, 0, 'database');
	$sth->execute(@{$$params{'parameters'}}) || PDLNA::Log::log('ERROR: Cannot execute database query: '.$DBI::errstr, 0, 'database');
	my $result = $sth->fetchrow_array();

	_log_query($dbh, $params, $starttime, $perfdata);
	return $result || 0;
}

sub select_db
{
	my $dbh = shift;
	my $params = shift;
	my $result = shift;

	my $perfdata = defined($$params{'perfdata'}) ? 0 : 1;

	my $starttime = PDLNA::Utils::get_timestamp_ms();

	my $sth = $dbh->prepare($$params{'query'}) || PDLNA::Log::log('ERROR: Cannot prepare database query: '.$DBI::errstr, 0, 'database');
	$sth->execute(@{$$params{'parameters'}}) || PDLNA::Log::log('ERROR: Cannot execute database query: '.$DBI::errstr, 0, 'database');
	while (my $data = $sth->fetchrow_hashref)
	{
		push(@{$result}, $data);
	}
	PDLNA::Log::log('ERROR: Data fetching terminated early by error: '.$DBI::errstr, 0, 'database') if $DBI::err;

	_log_query($dbh, $params, $starttime, $perfdata);
}

sub insert_db
{
	my $dbh = shift;
	my $params = shift;

	my $perfdata = defined($$params{'perfdata'}) ? 0 : 1;

	my $starttime = PDLNA::Utils::get_timestamp_ms();

	my $sth = $dbh->prepare($$params{'query'}) || PDLNA::Log::log('ERROR: Cannot prepare database query: '.$DBI::errstr, 0, 'database');
	$sth->execute(@{$$params{'parameters'}}) || PDLNA::Log::log('ERROR: Cannot execute database query: '.$DBI::errstr, 0, 'database');

	_log_query($dbh, $params, $starttime, $perfdata);
}

sub update_db
{
	my $dbh = shift;
	my $params = shift;

	my $perfdata = defined($$params{'perfdata'}) ? 0 : 1;

	my $starttime = PDLNA::Utils::get_timestamp_ms();

	my $sth = $dbh->prepare($$params{'query'}) || PDLNA::Log::log('ERROR: Cannot prepare database query: '.$DBI::errstr, 0, 'database');
	$sth->execute(@{$$params{'parameters'}}) || PDLNA::Log::log('ERROR: Cannot execute database query: '.$DBI::errstr, 0, 'database');

	_log_query($dbh, $params, $starttime, $perfdata);
}

sub delete_db
{
	my $dbh = shift;
	my $params = shift;

	my $perfdata = defined($$params{'perfdata'}) ? 0 : 1;

	my $starttime = PDLNA::Utils::get_timestamp_ms();

	my $sth = $dbh->prepare($$params{'query'}) || PDLNA::Log::log('ERROR: Cannot prepare database query: '.$DBI::errstr, 0, 'database');
	$sth->execute(@{$$params{'parameters'}}) || PDLNA::Log::log('ERROR: Cannot execute database query: '.$DBI::errstr, 0, 'database');

	_log_query($dbh, $params, $starttime, $perfdata);
}

#
# HELPER FUNCTIONS
#

sub _insert_performance_data
{
	my $dbh = shift;
	my $query = shift;
	my $time = shift;

	my $query_type = substr($query, 0, 6);

	insert_db(
		$dbh,
		{
			'query' => 'INSERT INTO stat_db (date, query_type, query, exec_time) VALUES (?,?,?,?)',
			'parameters' => [ time(), $query_type, $query, $time, ],
			'perfdata' => 0, # disable writing perfdata
		},
	);
}

sub _insert_metadata
{
	my $dbh = shift;
	my $param = shift;
	my $value = shift;

	insert_db(
		$dbh,
		{
			'query' => 'INSERT INTO metadata (param, value) VALUES (?,?)',
			'parameters' => [ $param, $value, ],
			'perfdata' => 0, # disable writing perfdata
		},
	);
}

sub _log_query
{
	my $dbh = shift;
	my $params = shift;
	my $starttime = shift || 0;
	my $perfdata = shift;

	my $endtime = PDLNA::Utils::get_timestamp_ms();
	my $time = $endtime - $starttime;

	my $parameters = '';
	foreach my $param (@{$$params{'parameters'}})
	{
		if (defined($param))
		{
			$parameters .= $param.', ';
		}
		else
		{
			$parameters .= 'undefined, ';
		}
	}
	substr($parameters, -2) = '';

	if ($perfdata && $CONFIG{'ENABLE_DATABASE_STATISTICS'})
	{
		_insert_performance_data($dbh, $$params{'query'}, $time);
	}
	PDLNA::Log::log('(Query took '.$time.'ms): '. $$params{'query'}.' - '.$parameters, 1, 'database');
}

1;
